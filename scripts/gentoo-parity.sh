#!/usr/bin/env bash
# Copyright 2026 Lucas C.S. and bentoo contributors
# SPDX-License-Identifier: MIT
#
# Report where every bentoo package diverges from its ::gentoo counterpart.
#
# WHAT IT IS FOR
#
# An overlay that shadows ::gentoo accumulates silent drift: a package is forked
# for one reason, ::gentoo later ships the same fix, and the overlay copy stays
# behind forever because nothing ever compares the two. This script is that
# missing comparison. It reads the metadata of both trees, names every axis on
# which they differ, and writes the result to a report a human can act on.
#
# STRICTLY READ-ONLY
#
# It reads two package trees and writes two report files under .epic/. It never
# writes inside a package directory, never touches ::gentoo, and never runs git.
# A parity check that edits what it is measuring is not a measurement.
#
# USAGE
#
#   bash scripts/gentoo-parity.sh                    # full sweep, writes the reports
#   bash scripts/gentoo-parity.sh kde-plasma         # restrict to one category
#   bash scripts/gentoo-parity.sh kde-plasma/kwin    # restrict to one package
#   bash scripts/gentoo-parity.sh --self-test        # assertions only, no report
#
#   GENTOO_REPO=<path>   the ::gentoo tree to compare against
#                        (default /var/db/repos/gentoo)
#   PARITY_REPORT_DIR=<path>
#                        where the two reports are written
#                        (default .epic/reports/gentoo-parity)
#
# Exit status:
#   0  the sweep found nothing to act on, or every self-test assertion passed
#   1  an ALIGN or UNDOCUMENTED divergence was found, or a self-test assertion
#      failed. JUSTIFIED and REDUNDANT do not fail the run: the first is a
#      decision already recorded, the second is remediation tracked elsewhere
#   2  a precondition or a usage error - nothing was compared

set -euo pipefail

# Every glob below is a listing of a package directory or a cache directory. An
# unmatched pattern must expand to nothing rather than to itself: a directory
# holding no .ebuild is precisely how a non-package is recognised, and the
# literal string "…/*.ebuild" would be counted as one ebuild instead of none.
shopt -s nullglob

### where things live ################################################

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
OVERLAY_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)

# This file, absolutely. BASH_SOURCE is whatever the caller typed, so it is
# usually relative - and a relative path is resolved against the CALLER's
# directory, not against wherever it is later used. prepare_stale_scratch
# symlinks this script into a fixture tree, where a relative target would dangle
# and the run would die with exit 127.
SCRIPT_PATH="${SCRIPT_DIR}/${BASH_SOURCE[0]##*/}"

# Overridable so the sweep can run against a checkout somewhere else - a
# container, a second sync, a machine that keeps its trees elsewhere.
GENTOO_REPO=${GENTOO_REPO:-/var/db/repos/gentoo}

# Both reports are snapshots; the guard that regenerates them has to outlive the
# story that first asked for them, which is why this script lives in scripts/
# while its output goes under the gitignored .epic/.
#
# That output must NOT go inside .epic/stories/. It used to default to
# .epic/stories/007-gentoo-parity-baseline, and line ~2470 does `mkdir -p` on
# this path: once story 007 was archived, every run re-created a directory
# bearing an archived story's number, holding a single filtered report. Epic
# then listed 007 as an active story again, and overlay story numbers are never
# recycled. A report directory is not a story - keep it out of their namespace.
#
# Overridable for the reason GENTOO_REPO is, and for one of its own: A12 runs a
# whole sweep in a subprocess to prove that a run finding nothing still writes a
# complete report. Without somewhere else to put it, --self-test would publish
# over the real report on every invocation - a guard editing what it measures.
REPORT_DIR=${PARITY_REPORT_DIR:-"${OVERLAY_ROOT}/.epic/reports/gentoo-parity"}
PARITY_DATA="${REPORT_DIR}/parity-data.tsv"
PARITY_REPORT="${REPORT_DIR}/parity-report.md"

### command line #####################################################

SELF_TEST=0
FILTER=""

usage() {
	printf 'Usage: gentoo-parity.sh [--self-test] [<category>|<category>/<package>]\n'
	printf 'Env:   GENTOO_REPO   path to the ::gentoo tree (default /var/db/repos/gentoo)\n'
}

# validate_filter <argument>
# A filter is either <category> or <category>/<package>. Shape is checked here;
# whether it matches anything is the package-set stage's business. Both checks
# matter for the same reason: a filter that quietly selects nothing produces an
# empty report, and an empty report reads exactly like a clean one.
validate_filter() {
	local filter=$1
	local atom='[A-Za-z0-9][A-Za-z0-9+_.-]*'

	if [[ ${filter} =~ ^${atom}(/${atom})?$ ]]; then
		return 0
	fi

	printf 'not a category or a category/package: %s\n' "${filter}" >&2
	printf 'expected <category> (kde-plasma) or <category>/<package> (kde-plasma/kwin)\n' >&2
	return 1
}

parse_args() {
	local arg
	while (( $# )); do
		arg=$1
		case ${arg} in
		--self-test)
			SELF_TEST=1
			;;
		-h|--help)
			usage
			exit 0
			;;
		-*)
			printf 'unknown option: %s\n' "${arg}" >&2
			usage >&2
			return 2
			;;
		*)
			if [[ -n ${FILTER} ]]; then
				printf 'at most one filter is accepted, got %s and %s\n' \
					"${FILTER}" "${arg}" >&2
				return 2
			fi
			validate_filter "${arg}" || return 2
			FILTER=${arg}
			;;
		esac
		shift
	done
}

### preconditions ####################################################

# Enforced for a sweep. The self-test only PROBES this, and deliberately does
# not gate on it: --self-test has to stay runnable on a machine with no
# ::gentoo checkout at all. Its assertions are measurements of two real trees,
# so without one they all fail with an empty observed value and a note saying
# why - which is the honest outcome, not a reason to refuse to run.
check_preconditions() {
	if [[ ! -d ${GENTOO_REPO} ]]; then
		printf 'precondition failed: no ::gentoo tree at %s\n' "${GENTOO_REPO}" >&2
		printf '  point GENTOO_REPO at a synced checkout, e.g.\n' >&2
		printf '  GENTOO_REPO=/path/to/gentoo bash scripts/gentoo-parity.sh\n' >&2
		return 2
	fi

	# A directory that exists but is not a repository would make every overlay
	# package look overlay-only, and the sweep would report total divergence
	# while having compared against nothing. Refuse instead.
	if [[ ! -f ${GENTOO_REPO}/profiles/repo_name ]]; then
		printf 'precondition failed: %s has no profiles/repo_name, so it is not a package tree\n' \
			"${GENTOO_REPO}" >&2
		return 2
	fi

	# The comparison reads metadata, not ebuilds. No md5-cache on either side
	# means there is nothing to compare, which is not the same as "no drift".
	# This is the coarse "does a cache exist at all" gate; whether a given
	# package's cache entry is stale is the md5-cache stage's job.
	local tree
	for tree in "${GENTOO_REPO}" "${OVERLAY_ROOT}"; do
		if [[ ! -d ${tree}/metadata/md5-cache ]]; then
			printf 'precondition failed: %s has no metadata/md5-cache to compare\n' \
				"${tree}" >&2
			return 2
		fi
	done
}

### versions #########################################################
#
# Everything the baseline selector needs to know about a version string, and
# nothing else. A version here is always the part of PF after "<pn>-", so it
# carries the revision too: 2.46.1-r1, not 2.46.1.

# version_is_live <version>
# Whether the version marks a VCS ebuild rather than a release.
#
# This is the single most consequential predicate in the script. Live versions
# sort above every real one, and a first pass that let them into the version
# sort reported 34 packages as behind ::gentoo when none are (design.md).
#
# It matches more than the bare 9999 and 99999999 that R2.4 names, because
# ::gentoo also ships per-branch live ebuilds - sys-devel/binutils-2.46.9999
# and media-gfx/blender-{4.5,5.0}.9999 are in the shared set today - and those
# are live by exactly the same convention. Measured 2026-08-06: matching the
# two literal forms only would hand blender-5.2.0 the baseline 5.0.9999 and
# binutils-2.47 the baseline 2.46.9999, so two ebuilds would be compared
# against a git checkout's metadata. Widening the rule changes those two
# baselines to 5.0.0 and 2.46.1-r1 and moves no other row: the exact /
# same-series / cross-series split is the same either way. That split was
# 76 / 33 / 210 when it was first measured and is 76 / 33 / 212 now, the two
# extra ebuilds being the ones 05b58fec5 added to the shared set (see A01) -
# neither of them live, and neither of them a counter-example.
version_is_live() {
	# Read as: an optional dotted prefix, then a component of nothing but 9s,
	# then an optional revision, then end. So 9999, 99999999, 9999-r1 and
	# 2.46.9999 are live and 2.46.1-r1 is not.
	[[ $1 =~ ^([0-9._]+\.)?9{4,}(-r[0-9]+)?$ ]]
}

# version_series <version>
# The major.minor series the version belongs to, in VERSION_SERIES.
#
# Only the leading numeric run counts, so 1.16.0_pre20260806 is series 1.16 and
# 0_pre10291 is series 0. A version with a single component is its own series.
#
# Assigns rather than prints: it is called for every ::gentoo candidate of every
# ebuild that has no exact match, and a command substitution there costs a fork
# each time - some 2400 of them on a full sweep.
VERSION_SERIES=""
version_series() {
	local version=$1 numeric major rest

	# Cut at the first character that is neither a digit nor a dot: that drops
	# _pre20260806, -r1 and anything else Gentoo suffixes a version with.
	numeric=${version%%[!0-9.]*}
	numeric=${numeric%.}

	if [[ -z ${numeric} ]]; then
		VERSION_SERIES=${version}
		return 0
	fi

	major=${numeric%%.*}
	rest=${numeric#*.}

	if [[ ${rest} == "${numeric}" ]]; then
		VERSION_SERIES=${major}
	else
		VERSION_SERIES="${major}.${rest%%.*}"
	fi
}

# sort_versions
# Sorts the versions on stdin, one per line, in Gentoo order.
#
# Plain sort -V is GNU version sort, not Gentoo's ver_test, and the two disagree
# on suffixed versions: Gentoo orders 1.0_rc1 BELOW 1.0, sort -V puts it above.
# That was a known gap until 2026-10-06, when it first changed a pick:
# sys-apps/systemd-262-r1 got ::gentoo's 262_rc2 as its baseline instead of
# 262, and the rc's empty KEYWORDS surfaced as an UNDOCUMENTED row.
#
# The fix keeps sort -V and rewrites only the sort KEY: the four pre-release
# suffixes become "~" plus a letter in their Gentoo order (alpha < beta < pre
# < rc), and sort -V places "~" before the end of the string, so 1.0~r1 sorts
# below 1.0. _p and -rN are left alone - sort -V already puts both above the
# bare version, as Gentoo does.
sort_versions() {
	awk '{ k = $0; gsub(/_alpha/, "~a", k); gsub(/_beta/, "~b", k)
		gsub(/_pre/, "~p", k); gsub(/_rc/, "~r", k); print k "\t" $0 }' |
		sort -t $'\t' -k1,1V | cut -f2
}

# highest_version <version>...
# The greatest of the versions given, in Gentoo order (see sort_versions).
highest_version() {
	printf '%s\n' "$@" | sort_versions | tail -n1
}

### pipeline #########################################################
#
# One function per stage, in execution order, each an obvious seam.
#
# While the stages were being filled in one at a time, each unimplemented one
# registered itself as pending and the sweep exited 3 rather than 0, so that a
# skeleton run could never be mistaken for a clean tree. All seven are
# implemented now, so that scaffolding is gone and the exit contract in
# sweep_exit_code is the real one.

### what the stages publish ##########################################
#
# The pipeline's entire output surface. A stage writes here; nothing reads a
# stage's internals. That is what lets the self-test assert on results rather
# than re-deriving them - an assertion that walked the two trees itself would
# still be green with every stage below deleted, and would be testing coreutils
# instead of this script.
#
# Each one stays empty until the stage named beside it is implemented, which is
# why an assertion reading it is red until then. Stages 1 to 3 are filled in;
# the six assertions that read stages 4 to 6 are still red, and correctly so.

PARITY_SHARED_PACKAGES=()  # <category>/<pn> present in both trees      - stage 1
PARITY_SCOPE_EBUILDS=()    # <category>/<pf>, overlay side, in scope    - stage 1
PARITY_EXCLUDED=()         # <category>/<pn> TAB <why it is not compared>
                           #                                           - stage 1
PARITY_BASELINES=()        # <category>/<pf> TAB <baseline PV> TAB <distance>
                           #                                           - stage 2
PARITY_BEHIND=()           # <category>/<pn> whose overlay PV trails    - stage 2
PARITY_MD5_COVERED=()      # <category>/<pf> cached on BOTH sides       - stage 3
PARITY_IDENTICAL=()        # <category>/<pf> byte-identical to baseline - stage 6
PARITY_ROWS=()             # one divergence row per (ebuild, axis)      - stages 4-6
PARITY_ECLASS_DEFINITIONAL=()
                           # <eclass> TAB <why it is not a finding>     - stage 5

# Story 008 adds two more, and both are OUTPUT SURFACE rather than internals for
# the same reason as everything above: an assertion has to read what a stage
# concluded, not re-derive it.
#
# They are declared empty here rather than beside the logic that fills them so
# that the assertions reading them can be authored FIRST and fail by observing
# nothing recorded. Under set -u an assertion reading an undeclared array aborts
# the harness instead - which is a broken test, not a red one, and would prove
# nothing about the rule being absent.

PARITY_METADATA_SUPPRESSED=()  # <category>/<pn> TAB <why>
PARITY_FILES_SUPPRESSED=()  # <category>/<pn> TAB <axis> TAB <count> TAB <why>
                           # R1.5 again: a files/ row is dropped only when
                           # every name in it is reachable from an ebuild, and
                           # the record says which axis and how many.
PARITY_SLOT_SUPPRESSED=()  # <category>/<pn>-<PV> TAB <overlay SLOT> TAB
                           # <::gentoo SLOT> TAB <why it was suppressed>
                           # R1.5: a suppression nobody can audit is
                           # indistinguishable from a comparison that broke
PARITY_STALE_CACHE=()      # <category>/<pn> TAB <PV> TAB <eclass> TAB <note>
                           # R2.1-R2.2: an _eclasses_ hash difference for an
                           # eclass the overlay does not ship. Instrument error,
                           # reported outside the four verdicts and outside the
                           # divergence row count

# The 2026-09-04 parity audit added two more, and both sit outside the four
# verdicts for the same reason PARITY_STALE_CACHE does: neither is a divergence
# a human has to judge. One is a broken ebuild, the other is stale prose.

PARITY_ORPHAN_FILES=()     # <category>/<pn> TAB <count> TAB <names>
PARITY_CACHE_NO_EBUILD=()  # <category> TAB <name>  (md5-cache entry, no ebuild)
PARITY_MISSING_FILES=()    # <category>/<pn> TAB <ebuilds> TAB <pattern>
                           # A file under files/ that no ebuild of the package
                           # reaches through ${FILESDIR}. Dead weight: it does
                           # not break anything, so it does NOT fail the run -
                           # the same call PARITY_STALE_TAGS makes.
                           #
                           # OVERLAY-WIDE, like the digest check below and
                           # unlike every axis above. This used to be the
                           # files/unreferenced divergence axis, which meant it
                           # only ever looked at the 164 packages ::gentoo also
                           # carries - and an orphan file is not a divergence
                           # from ::gentoo at all, it is litter here. The 104
                           # overlay-only packages are exactly where nobody
                           # would look.

PARITY_MISSING_DIGEST=()   # <category>/<pn> TAB <PV> TAB <distfile> TAB <note>
                           # A distfile named in SRC_URI with no DIST line in
                           # the package Manifest. The ebuild cannot be merged
                           # at all: portage stops at "Insufficient data for
                           # checksum verification".
                           #
                           # WHY THIS AXIS EXISTS. On 2026-09-04 net-misc/
                           # rclone-1.75.0 and sci-ml/ollama-0.33.2 were both
                           # found in exactly this state, each shadowing a
                           # WORKING ::gentoo copy of the same version - the
                           # overlay wins on repo priority, so the user gets the
                           # broken one. Nothing caught it: the ebuild parses,
                           # pkgcheck is quiet, and md5-cache is happily
                           # regenerated. It surfaces only when someone emerges
                           # the package.
                           #
                           # Unlike every other axis here this one does NOT
                           # compare the two trees, so it is not restricted to
                           # shared packages. A missing digest is broken whether
                           # or not ::gentoo has an opinion, and the 101
                           # overlay-only packages are exactly where nobody
                           # would look. It DOES fail the run: this is not drift
                           # to schedule, it is an ebuild nobody can install.

PARITY_STALE_TAGS=()       # <category>/<pf> TAB <axis> TAB <note>
                           # A "# BENTOO-DIVERGENCE: <axis>" tag naming an axis
                           # on which the two trees no longer differ.
                           #
                           # WHY IT MATTERS MORE HERE THAN IN A NORMAL OVERLAY.
                           # bentoo never sends anything upstream, so a
                           # divergence is not a queue entry that eventually
                           # drains - it is permanent until someone notices
                           # ::gentoo caught up. That noticing is what this
                           # array automates. Without it the overlay rebases a
                           # patch long after the reason evaporated, which is
                           # how dev-games/godot ended up mirroring an upstream
                           # commit byte-for-byte.
                           #
                           # It does NOT fail the run: a stale tag misleads a
                           # reader but breaks nothing, and a guard that goes
                           # red over prose is a guard people learn to skip.

# <category>/<pf> -> <pn>, for every ebuild in scope. Published by stage 1 and
# read by every stage after it, because PN cannot be recovered from PF alone:
# net-libs/webkit-gtk-2.52.5-r411 splits at the second hyphen, not the first,
# and only the directory the ebuild was found in says so. Stage 1 knows it for
# free; anything downstream would have to guess.
declare -A PARITY_EBUILD_PN=()

# A PARITY_ROWS entry carries the columns parity-data.tsv carries, tab
# separated, in this order (design.md -> sub-task 6.1):
#
#   1 category/pn   2 overlay PV      3 baseline PV      4 distance
#   5 axis          6 overlay value   7 ::gentoo value   8 verdict
#
# Stages 4 and 5 append rows; stage 6 fills column 8. Values must arrive with
# tabs and newlines already stripped - the report format has no escaping, and a
# row that splits is a row nobody notices is wrong.

# Where the # BENTOO-DIVERGENCE: tag parser reads an ebuild from, keyed by
# <category>/<pf>. Empty during a sweep: the tag belongs in the ebuild, which
# is the whole point of putting it there.
#
# It exists for one reason. The overlay carries zero tags today (measured
# 2026-08-06), and R7 makes this story read-only, so the only honest way to
# assert "JUSTIFIED once tagged" is to tag a copy the overlay never sees. The
# self-test writes that copy under $TMPDIR and registers it here.
#
# Sub-task 5.2's parser must resolve an ebuild through this map FIRST and fall
# back to ${OVERLAY_ROOT}/<category>/<pn>/<pf>.ebuild. That single lookup is
# the entire seam.
declare -A PARITY_TAG_SOURCE=()

# filter_selects <category/pn>
# Whether the package survives FILTER. An empty filter selects everything, a
# filter with no slash names a whole category, one with a slash names a single
# package. Shape was already validated by validate_filter.
filter_selects() {
	local key=$1 scope

	if [[ -z ${FILTER} ]]; then
		return 0
	fi

	if [[ ${FILTER} == */* ]]; then
		scope=${key}
	else
		scope=${key%%/*}
	fi

	[[ ${scope} == "${FILTER}" ]]
}

# Stage 1. Enumerate the overlay's packages, honouring FILTER, and split them
# into those ::gentoo also carries and those it does not. Must fail loudly when
# a filter matches zero packages.
# Publishes: PARITY_SHARED_PACKAGES, PARITY_SCOPE_EBUILDS, PARITY_EXCLUDED,
# PARITY_EBUILD_PN.
build_package_sets() {
	local pkg_dir category pn key ebuild pf
	local -a overlay_ebuilds=() gentoo_ebuilds=()
	local matched=0

	for pkg_dir in "${OVERLAY_ROOT}"/*/*/; do
		pkg_dir=${pkg_dir%/}
		pn=${pkg_dir##*/}
		category=${pkg_dir%/*}
		category=${category##*/}
		key="${category}/${pn}"

		# The whole definition of "package": a directory holding at least one
		# ebuild. One structural rule, no list of directory names to keep in
		# sync - metadata/, profiles/, eclass/, licenses/ and scripts/ are
		# excluded because none of them holds an ebuild, not because they are
		# named here. .autoupdate/ and .git/ never even reach this loop, the
		# glob not matching a leading dot.
		overlay_ebuilds=( "${pkg_dir}"/*.ebuild )
		if (( ${#overlay_ebuilds[@]} == 0 )); then
			continue
		fi

		if ! filter_selects "${key}"; then
			continue
		fi
		matched=$(( matched + 1 ))

		# Overlay-only packages are recorded with the reason rather than
		# dropped: 82 of 314 have no ::gentoo counterpart at all, and a
		# package that silently vanishes between the tree and the report is
		# indistinguishable from one that was compared and found clean.
		gentoo_ebuilds=( "${GENTOO_REPO}/${key}"/*.ebuild )
		if (( ${#gentoo_ebuilds[@]} == 0 )); then
			PARITY_EXCLUDED+=( "${key}"$'\t'"overlay-only: ::gentoo carries no ${key}" )
			continue
		fi

		PARITY_SHARED_PACKAGES+=( "${key}" )

		for ebuild in "${overlay_ebuilds[@]}"; do
			pf=${ebuild##*/}
			pf=${pf%.ebuild}
			PARITY_SCOPE_EBUILDS+=( "${category}/${pf}" )
			PARITY_EBUILD_PN["${category}/${pf}"]=${pn}
		done
	done

	if (( matched == 0 )); then
		if [[ -n ${FILTER} ]]; then
			printf 'filter %s matched no package under %s\n' \
				"${FILTER}" "${OVERLAY_ROOT}" >&2
		else
			printf 'no directory under %s holds an ebuild\n' "${OVERLAY_ROOT}" >&2
		fi
		printf 'nothing would be compared, and an empty report reads exactly like\n' >&2
		printf 'a clean one\n' >&2
		return 2
	fi

	if (( ${#PARITY_SHARED_PACKAGES[@]} == 0 )); then
		printf '%d package(s) matched %s, but ::gentoo carries none of them\n' \
			"${matched}" "${FILTER:-the overlay}" >&2
		printf 'there is nothing to compare against, and an empty report reads\n' >&2
		printf 'exactly like a clean one\n' >&2
		return 2
	fi

	# R5.3's first count, established here because this is where it is known.
	printf '  [scope]    %d package(s) shared with ::gentoo, %d overlay-only (excluded), %d ebuild(s) in scope\n' \
		"${#PARITY_SHARED_PACKAGES[@]}" "${#PARITY_EXCLUDED[@]}" \
		"${#PARITY_SCOPE_EBUILDS[@]}"
}

# gentoo_candidates <category/pn> <pn>
# Every non-live ::gentoo version of the package, ascending, space separated.
# Empty when ::gentoo carries nothing but live ebuilds.
#
# Sorted once here rather than at each use, which is what lets the selector
# take the highest of any subset as its last element instead of forking a sort
# per ebuild.
gentoo_candidates() {
	local key=$1 pn=$2 ebuild version
	local -a versions=()

	for ebuild in "${GENTOO_REPO}/${key}"/*.ebuild; do
		version=${ebuild##*/}
		version=${version%.ebuild}
		version=${version#"${pn}-"}

		if version_is_live "${version}"; then
			continue
		fi
		versions+=( "${version}" )
	done

	if (( ${#versions[@]} == 0 )); then
		return 0
	fi

	printf '%s\n' "${versions[@]}" | sort_versions | tr '\n' ' '
}

CACHE_SLOT=""

# cache_slot <md5-cache file>
# The SLOT of one md5-cache entry, subslot dropped, into CACHE_SLOT. Empty when
# the entry is missing: stage 3 is the one that reports a missing entry, so this
# only declines to narrow anything.
cache_slot() {
	local line

	CACHE_SLOT=""
	[[ -f $1 ]] || return 0

	while IFS= read -r line; do
		if [[ ${line} == SLOT=* ]]; then
			CACHE_SLOT=${line#SLOT=}
			CACHE_SLOT=${CACHE_SLOT%%/*}
			return 0
		fi
	done <"$1"
}

# Stage 2. For each shared package, pick the ::gentoo version to compare
# against - the baseline the overlay copy is drifting from.
#
# Three distances, tried in this order (R2.1 -> R2.2 -> R2.3), and the one that
# hits is recorded on the row because it says how much the row is worth: at
# exact distance a dependency delta is real drift, at cross-series it is mostly
# the version having moved.
#
# Live ::gentoo ebuilds are out of the candidate pool entirely, which is R2.4
# read literally - "exclude them from baseline selection", not "exclude them
# from the sort at the end". A live OVERLAY ebuild is therefore never matched
# exactly and never shares a series with anything (9999 is its own series), so
# it falls through to cross-series against the highest real ::gentoo version
# and still gets a baseline row rather than disappearing. The overlay carries
# no live ebuild in a shared package today (measured 2026-08-06); this says
# what happens when it does.
#
# Publishes: PARITY_BASELINES, PARITY_BEHIND.
select_baseline() {
	local entry category pf pn key version candidate baseline distance wanted
	local overlay_top gentoo_top overlay_slot
	local -A candidates=() overlay_versions=() gentoo_slots=()
	local -a pool=() in_series=() overlay_pool=() slotted=()
	local exact=0 same=0 cross=0 unbaselined=0

	for entry in "${PARITY_SCOPE_EBUILDS[@]}"; do
		category=${entry%%/*}
		pf=${entry#*/}
		pn=${PARITY_EBUILD_PN[${entry}]}
		key="${category}/${pn}"
		version=${pf#"${pn}-"}

		# One directory listing and one sort per package, not per ebuild.
		if [[ -z ${candidates[${key}]+set} ]]; then
			candidates[${key}]=$(gentoo_candidates "${key}" "${pn}")
		fi
		read -r -a pool <<<"${candidates[${key}]}"

		if [[ -z ${overlay_versions[${key}]+set} ]]; then
			overlay_versions[${key}]=""
		fi
		if ! version_is_live "${version}"; then
			overlay_versions[${key}]+="${version} "
		fi

		if (( ${#pool[@]} == 0 )); then
			# Nothing non-live to compare against. Reported rather than
			# silently skipped: it leaves this ebuild out of PARITY_BASELINES,
			# which is a count the self-test pins.
			printf '  [NOTE]     %s: ::gentoo has only live ebuilds, so there is no baseline\n' \
				"${entry}"
			unbaselined=$(( unbaselined + 1 ))
			continue
		fi

		baseline=""
		distance=""

		# R2.1 - ::gentoo carries this very version. Matched on the whole
		# version string, revision included, which is what design.md's 76
		# was measured as ("filename match"). Ignoring the revision would
		# call 85 ebuilds exact instead, and the nine it adds are exactly
		# the ones where the revision IS the divergence: bentoo's
		# webkit-gtk-2.52.5-r411 is ::gentoo's -r410 plus a downstream
		# webdriver USE flag, and calling that pair exact would rank the
		# difference as unexplained drift at a distance that trusts every
		# axis.
		for candidate in "${pool[@]}"; do
			if [[ ${candidate} == "${version}" ]]; then
				baseline=${candidate}
				distance=exact
				break
			fi
		done

		# R2.2 and R2.3 only consider ::gentoo versions in the overlay
		# ebuild's own SLOT, when at least one exists. Without this, the
		# highest version of a multi-slot package wins regardless of slot:
		# webkit-gtk-2.54.1-r411 (SLOT 4.1) was paired with ::gentoo's
		# -r600 (SLOT 6) instead of -r400 (SLOT 4.1), and the slot
		# difference came out as an ALIGN row nobody could act on. A package
		# whose slots do not line up at all keeps the whole pool, so the
		# narrowing can never leave an ebuild without a baseline.
		if [[ -z ${distance} ]]; then
			cache_slot "${OVERLAY_ROOT}/metadata/md5-cache/${category}/${pf}"
			overlay_slot=${CACHE_SLOT}
			slotted=()
			for candidate in "${pool[@]}"; do
				if [[ -z ${gentoo_slots["${key}-${candidate}"]+set} ]]; then
					cache_slot "${GENTOO_REPO}/metadata/md5-cache/${category}/${pn}-${candidate}"
					gentoo_slots["${key}-${candidate}"]=${CACHE_SLOT}
				fi
				if [[ -n ${overlay_slot} &&
					${gentoo_slots["${key}-${candidate}"]} == "${overlay_slot}" ]]; then
					slotted+=( "${candidate}" )
				fi
			done
			if (( ${#slotted[@]} )); then
				pool=( "${slotted[@]}" )
			fi
		fi

		# R2.2 - highest ::gentoo version sharing major.minor.
		if [[ -z ${distance} ]]; then
			version_series "${version}"
			wanted=${VERSION_SERIES}
			in_series=()
			for candidate in "${pool[@]}"; do
				version_series "${candidate}"
				if [[ ${VERSION_SERIES} == "${wanted}" ]]; then
					in_series+=( "${candidate}" )
				fi
			done
			if (( ${#in_series[@]} )); then
				baseline=${in_series[-1]}
				distance='same-series'
			fi
		fi

		# R2.3 - the highest non-live version there is.
		if [[ -z ${distance} ]]; then
			baseline=${pool[-1]}
			distance='cross-series'
		fi

		# R2.5 - the baseline PV travels with every row from here on.
		PARITY_BASELINES+=( "${entry}"$'\t'"${baseline}"$'\t'"${distance}" )

		case ${distance} in
		exact)        exact=$(( exact + 1 )) ;;
		same-series)  same=$(( same + 1 )) ;;
		cross-series) cross=$(( cross + 1 )) ;;
		esac
	done

	# Which packages the overlay is actually behind on. Live versions are out
	# of both lists - that exclusion is the whole point: with 9999 left in, a
	# first pass reported 34 packages as behind ::gentoo when none are.
	for key in "${PARITY_SHARED_PACKAGES[@]}"; do
		read -r -a overlay_pool <<<"${overlay_versions[${key}]:-}"
		read -r -a pool <<<"${candidates[${key}]:-}"
		if (( ${#overlay_pool[@]} == 0 || ${#pool[@]} == 0 )); then
			continue
		fi

		overlay_top=$(highest_version "${overlay_pool[@]}")
		gentoo_top=${pool[-1]}

		if [[ ${overlay_top} != "${gentoo_top}" ]] &&
			[[ $(highest_version "${overlay_top}" "${gentoo_top}") == "${gentoo_top}" ]]; then
			PARITY_BEHIND+=( "${key}" )
		fi
	done

	printf '  [baseline] %d exact, %d same-series, %d cross-series' \
		"${exact}" "${same}" "${cross}"
	if (( unbaselined )); then
		printf ', %d without a baseline' "${unbaselined}"
	fi
	printf '; %d package(s) behind ::gentoo\n' "${#PARITY_BEHIND[@]}"
}

# Stage 3. Confirm both sides of every pair actually have the md5-cache entry
# the comparison is about to read.
#
# WHAT IT CHECKS AND WHAT IT DOES NOT. Presence, per pair: the overlay's entry
# for the overlay PF, and ::gentoo's entry for the baseline PF stage 2 picked.
# It does NOT check that an entry is up to date with its ebuild - measured
# 2026-08-06, all 319 overlay entries match their ebuild's md5, so the gap is
# real but currently empty, and it is named here rather than left to be
# discovered from a report that looked fine.
#
# Presence is the one that cannot be skipped. Every axis this script compares
# is read from md5-cache, so an absent entry yields an empty value on every
# axis at once, which compares equal to nothing and reads as "no divergence
# anywhere" - the most dangerous false negative the guard can produce.
#
# It is measured over PARITY_BASELINES rather than PARITY_SCOPE_EBUILDS on
# purpose: an ebuild stage 2 could not baseline has no ::gentoo entry to look
# for, and must not be counted as covered. The self-test's denominator is the
# full scope, so that shortfall surfaces there instead of being defined away.
#
# Publishes: PARITY_MD5_COVERED.
verify_md5_cache() {
	local line entry baseline category pf pn overlay_cache gentoo_cache
	local -a missing=()

	for line in "${PARITY_BASELINES[@]}"; do
		entry=${line%%$'\t'*}
		baseline=${line#*$'\t'}
		baseline=${baseline%%$'\t'*}

		category=${entry%%/*}
		pf=${entry#*/}
		pn=${PARITY_EBUILD_PN[${entry}]}

		overlay_cache="${OVERLAY_ROOT}/metadata/md5-cache/${category}/${pf}"
		gentoo_cache="${GENTOO_REPO}/metadata/md5-cache/${category}/${pn}-${baseline}"

		if [[ ! -f ${overlay_cache} ]]; then
			missing+=( "${entry}: no overlay entry at ${overlay_cache}" )
			continue
		fi
		if [[ ! -f ${gentoo_cache} ]]; then
			missing+=( "${entry}: no ::gentoo entry at ${gentoo_cache}" )
			continue
		fi

		PARITY_MD5_COVERED+=( "${entry}" )
	done

	printf '  [md5cache] %d/%d ebuild(s) in scope have a cache entry on both sides\n' \
		"${#PARITY_MD5_COVERED[@]}" "${#PARITY_SCOPE_EBUILDS[@]}"

	if (( ${#missing[@]} == 0 )); then
		return 0
	fi

	printf '%d md5-cache entr(ies) are missing, so those ebuilds cannot be compared:\n' \
		"${#missing[@]}" >&2
	for line in "${missing[@]}"; do
		printf '  - %s\n' "${line}" >&2
	done
	printf 'comparing without them would report every axis as identical, which is\n' >&2
	printf 'indistinguishable from finding no drift at all\n' >&2
	printf 'regenerate the overlay side with: egencache --update --repo bentoo\n' >&2
	printf 'and the ::gentoo side with: emaint sync -r gentoo\n' >&2
	return 2
}

### reading an md5-cache entry #######################################
#
# Every axis stage 4 compares comes out of one md5-cache file per side, so each
# file is read ONCE into an associative array and queried per axis afterwards.
# The obvious alternative - a grep per axis - is a dozen processes per file and
# some 7600 across a sweep, for work one read has already done.

# The pair of entries currently being compared, both sides in one array under
# the keys "overlay:<AXIS>" and "gentoo:<AXIS>". One array rather than two
# because the alternative is passing an array name into the reader, and a
# nameref is a variable shellcheck cannot follow.
declare -A MD5_FIELDS=()

# read_md5_cache <file> <side>
#
# Read one md5-cache entry into MD5_FIELDS under "<side>:<AXIS>". It ADDS to
# the array rather than clearing it, so that one side does not evict the other;
# the caller empties MD5_FIELDS once per pair.
#
# An md5-cache entry is one KEY=value per line and a value is never wrapped
# (checked across all 599 overlay entries, 2026-08-06). The split is at the
# FIRST = on the line, because values are full of them - the atom
# >=dev-qt/qtbase-6.10.1:6=[gui,wayland] carries two.
read_md5_cache() {
	local file=$1 side=$2
	local -a lines=()
	local line key

	mapfile -t lines <"${file}"

	for line in "${lines[@]}"; do
		key=${line%%=*}
		# A line with no = cannot be attributed to an axis. None exists
		# today; ignoring one is safer than guessing what it meant.
		[[ ${key} != "${line}" ]] || continue
		MD5_FIELDS["${side}:${key}"]=${line#*=}
	done
}

### comparing values #################################################
#
# One set difference and four normalisations. Each normalisation exists because
# comparing the raw strings would report something that is not drift.
#
# They all assign to a global instead of printing. Every one of them runs once
# per axis per side per ebuild - upwards of ten thousand calls on a sweep - and
# a command substitution would cost a fork each time.

SET_ONLY_A=""
SET_ONLY_B=""

# set_difference <space separated A> <space separated B>
# What each side has that the other has not, into SET_ONLY_A and SET_ONLY_B.
# Both empty means the two sets are equal.
#
# Each side keeps its own original order rather than being sorted. That is
# deterministic - portage writes md5-cache from the ebuild, in a fixed order -
# and it costs no fork. Nothing downstream depends on the order either: the
# self-test sorts before it compares.
set_difference() {
	local -a a=() b=()
	local -A in_a=() in_b=() seen=()
	local token

	read -r -a a <<<"$1"
	read -r -a b <<<"$2"

	for token in "${a[@]}"; do
		in_a["${token}"]=1
	done
	for token in "${b[@]}"; do
		in_b["${token}"]=1
	done

	SET_ONLY_A=""
	for token in "${a[@]}"; do
		[[ -z ${in_b[${token}]+set} && -z ${seen[${token}]+set} ]] || continue
		seen["${token}"]=1
		SET_ONLY_A+="${token} "
	done

	seen=()
	SET_ONLY_B=""
	for token in "${b[@]}"; do
		[[ -z ${in_a[${token}]+set} && -z ${seen[${token}]+set} ]] || continue
		seen["${token}"]=1
		SET_ONLY_B+="${token} "
	done

	SET_ONLY_A=${SET_ONLY_A% }
	SET_ONLY_B=${SET_ONLY_B% }
}

SET_INTERSECTION=""

# set_intersection <space separated A> <space separated B>
# What both sides have, in A's order, into SET_INTERSECTION.
set_intersection() {
	local -a a=() b=()
	local -A in_b=() seen=()
	local token

	read -r -a a <<<"$1"
	read -r -a b <<<"$2"

	for token in "${b[@]}"; do
		in_b["${token}"]=1
	done

	SET_INTERSECTION=""
	for token in "${a[@]}"; do
		[[ -n ${in_b[${token}]+set} && -z ${seen[${token}]+set} ]] || continue
		seen["${token}"]=1
		SET_INTERSECTION+="${token} "
	done
	SET_INTERSECTION=${SET_INTERSECTION% }
}

COLLAPSED=""

# collapse_whitespace <string>
# The string with runs of whitespace squeezed to one space and the ends
# trimmed, into COLLAPSED. Splitting on IFS and rejoining on it does both.
collapse_whitespace() {
	local -a words=()

	read -r -a words <<<"$1"
	COLLAPSED="${words[*]}"
}

ARCH_MEMBERSHIP=""

# arch_membership <KEYWORDS value>
# The keyword list as a bare arch set - the ~ prefix dropped, order kept,
# duplicates removed - into ARCH_MEMBERSHIP.
#
# This is R1.3, and it is not cosmetic. ::gentoo stabilises and the overlay
# never does, so comparing the raw strings would emit a KEYWORDS row for
# essentially every one of the 232 shared packages and not one of them would
# say anything. What survives the stripping is real: media-libs/mesa keeps
# ~amd64-linux and ~x86-linux, which ::gentoo does not carry at all.
#
# -* and -<arch> are left alone. They are "deliberately not keyworded" markers
# rather than arches, and one appearing on only one side IS a divergence.
#
# The self-test carries its own copy of this normalisation (arch_set) instead of
# calling in here, on purpose: a harness that reuses the code under test agrees
# with it by construction, including when both are wrong.
arch_membership() {
	local -a keywords=()
	local -A seen=()
	local keyword

	read -r -a keywords <<<"$1"

	ARCH_MEMBERSHIP=""
	for keyword in "${keywords[@]}"; do
		keyword=${keyword#\~}
		[[ -n ${keyword} && -z ${seen[${keyword}]+set} ]] || continue
		seen["${keyword}"]=1
		ARCH_MEMBERSHIP+="${keyword} "
	done
	ARCH_MEMBERSHIP=${ARCH_MEMBERSHIP% }
}

IUSE_SPLIT_FLAGS=""
IUSE_SPLIT_DEFAULTS=""

# iuse_split <IUSE value>
# The flag list split in two: IUSE_SPLIT_FLAGS is membership with the +/-
# default prefix removed, IUSE_SPLIT_DEFAULTS the names that carried a +.
#
# Two axes rather than one because they are two different findings. "the overlay
# added a flag" and "both carry the flag, but only the overlay turns it on by
# default" call for different actions, and a single row mixing them has to be
# read twice to tell which happened.
iuse_split() {
	local -a flags=()
	local -A seen=()
	local flag name

	read -r -a flags <<<"$1"

	IUSE_SPLIT_FLAGS=""
	IUSE_SPLIT_DEFAULTS=""
	for flag in "${flags[@]}"; do
		name=${flag#[+-]}
		[[ -n ${name} && -z ${seen[${name}]+set} ]] || continue
		seen["${name}"]=1
		IUSE_SPLIT_FLAGS+="${name} "
		if [[ ${flag} == '+'* ]]; then
			IUSE_SPLIT_DEFAULTS+="${name} "
		fi
	done
	IUSE_SPLIT_FLAGS=${IUSE_SPLIT_FLAGS% }
	IUSE_SPLIT_DEFAULTS=${IUSE_SPLIT_DEFAULTS% }
}

ATOM_SET=""

# atom_set <dependency string> <keep bounds: 0 or 1>
# The dependency string as a comparable set of atoms, into ATOM_SET.
#
# Grouping tokens - || ( ) and every use? conditional opener - are dropped:
# they say WHEN an atom applies, not WHICH atom it is. A dependency moving
# between an unconditional position and a use? block therefore reads as no
# change. That is a deliberate simplification; the alternative is a full
# dependency-spec parser to compare two strings with.
#
# With <keep bounds> 0 an atom is reduced to [!]category/pn - version bound,
# slot and USE dependency all come off. That is R1.4's atom set, and the reason
# for it is that a newer overlay version legitimately raises a minimum:
# >=foo-2 against >=foo-1 is the version having moved, not drift worth a row.
# The blocker ! is KEPT, because !foo/bar and foo/bar are opposite statements
# about the same package and must not collapse into one another.
#
# With <keep bounds> 1 the atom is kept whole. Used only at exact distance,
# where both sides are the same version and a bound that differs can only be a
# downstream change.
atom_set() {
	local keep_bounds=$2
	local -a tokens=()
	local -A seen=()
	local token atom blocker version

	read -r -a tokens <<<"$1"

	ATOM_SET=""
	for token in "${tokens[@]}"; do
		case ${token} in
		'('|')'|'||'|*'?') continue ;;
		esac

		atom=${token}

		if (( ! keep_bounds )); then
			blocker=""
			while [[ ${atom} == '!'* ]]; do
				blocker+='!'
				atom=${atom#'!'}
			done

			atom=${atom%%\[*}   # USE dependency
			atom=${atom%%:*}    # slot, sub-slot, slot operator

			# A version is only ever present behind an operator
			# (PMS 8.3.1), so this is exact rather than a guess at
			# where the name ends: net-libs/webkit-gtk keeps its
			# hyphen, >=net-libs/webkit-gtk-2.52.5-r410 loses both
			# trailing components and keeps it too.
			case ${atom} in
			[\<\>=~]*)
				atom=${atom#[\<\>~]}
				atom=${atom#=}
				version=${atom##*-}
				atom=${atom%-*}
				if [[ ${version} =~ ^r[0-9]+$ ]]; then
					atom=${atom%-*}
				fi
				;;
			esac

			atom="${blocker}${atom}"
		fi

		[[ -n ${atom} && -z ${seen[${atom}]+set} ]] || continue
		seen["${atom}"]=1
		ATOM_SET+="${atom} "
	done
	ATOM_SET=${ATOM_SET% }
}

# parity_row <category/pn> <overlay PV> <baseline PV> <distance> <axis> <overlay value> <::gentoo value>
# Append one divergence row in the eight-column shape declared above.
#
# Column 8, the verdict, is left EMPTY: stage 6 owns it, and a stage that
# guessed at it would be inventing the answer the report exists to give.
#
# Two things are enforced here rather than at each of the dozen call sites.
# Tabs and newlines are flattened out of both values, because the format has no
# escaping and a row that splits is a row nobody notices is wrong. And an empty
# value becomes (none), because a tab is IFS whitespace: bash collapses two
# adjacent tabs into one delimiter, so an empty column in the MIDDLE of a row
# silently shifts every column after it when the row is read back.
parity_row() {
	local pkg=$1 opv=$2 bpv=$3 distance=$4 axis=$5 overlay=$6 gentoo=$7

	overlay=${overlay//[$'\t\n']/ }
	gentoo=${gentoo//[$'\t\n']/ }

	PARITY_ROWS+=( "${pkg}"$'\t'"${opv}"$'\t'"${bpv}"$'\t'"${distance}"$'\t'"${axis}"$'\t'"${overlay:-(none)}"$'\t'"${gentoo:-(none)}"$'\t' )
}

# The four columns every row of the ebuild currently being compared shares, set
# once per pair by compare_ebuild_axes - and by stage 5's PATCHES comparison,
# which is per ebuild for the same reason and reuses compare_as_sets. Context
# rather than arguments so that each of the dozen comparisons below reads as
# what it compares - compare_as_sets KEYWORDS "${overlay}" "${gentoo}" - instead
# of restating the same four values a dozen times over.
ROW_PKG=""
ROW_OPV=""
ROW_BPV=""
ROW_DISTANCE=""

# compare_values <axis> <overlay value> <::gentoo value>
# Emit a row when the two values differ as strings, each carried whole. For the
# single-valued axes, where the value IS the finding.
compare_values() {
	if [[ $2 != "$3" ]]; then
		parity_row "${ROW_PKG}" "${ROW_OPV}" "${ROW_BPV}" "${ROW_DISTANCE}" \
			"$1" "$2" "$3"
	fi
}

# compare_as_sets <axis> <overlay value> <::gentoo value>
# Emit a row when the two space separated values differ as sets.
#
# Each side carries its SURPLUS rather than its whole value: on INHERIT the
# finding is "::gentoo also inherits cargo and flag-o-matic", and repeating the
# six eclasses both sides share would bury it.
compare_as_sets() {
	if [[ $2 == "$3" ]]; then
		return 0
	fi

	set_difference "$2" "$3"
	if [[ -n ${SET_ONLY_A} || -n ${SET_ONLY_B} ]]; then
		parity_row "${ROW_PKG}" "${ROW_OPV}" "${ROW_BPV}" "${ROW_DISTANCE}" \
			"$1" "${SET_ONLY_A}" "${SET_ONLY_B}"
	fi
}

# slot_component_derivable <slot component> <PV>
# Sub-task 3.1. Whether one slot component is that side's own version.
#
# THE BOUNDARY IS THE WHOLE POINT. A component derives from a PV when the PV -
# revision stripped - either IS it, or begins with it followed by a dot. The
# second half is what makes sys-devel/binutils work: ::gentoo sits at 2.46.1-r1
# and calls its slot 2.46, so nothing but a component-prefix match recognises it.
#
# And the dot is what stops that half from swallowing real slots. "2.4" is a
# prefix of the string "2.46.1", but it stops in the MIDDLE of a component and
# is not a version this package ever had; accepting it would fold genuinely
# different slots together. dev-libs/imath is the case that would go first - its
# 3/30 against 3/29 is an ABI counter, and 30 must not derive from 3.2.2.
#
# The revision is stripped because it is a downstream counter, not a version:
# net-libs/webkit-gtk carries -r411 against ::gentoo's -r600 at the same PV, and
# a slot never encodes one.
slot_component_derivable() {
	local component=$1 pv=$2

	[[ -n ${component} ]] || return 1

	if [[ ${pv} =~ ^(.+)-r[0-9]+$ ]]; then
		pv=${BASH_REMATCH[1]}
	fi

	[[ ${pv} == "${component}" || ${pv} == "${component}."* ]]
}

# compare_slot <overlay SLOT> <::gentoo SLOT>
# Sub-tasks 3.2 and 3.3, and story 008's R1. Emit a SLOT row only where the slot
# STRUCTURE differs, never where the two sides merely sit at different versions.
#
# WHY THIS AXIS NEEDED ITS OWN COMPARATOR. Ten of the sixteen SLOT rows story
# 007 produced differ only because the package encodes its version in the slot
# or the subslot - dev-db/redis at 0/8.10 against 0/8.8, dev-lang/lua at 5.5
# against 5.4. That is the same artifact story 007's own R1.4 already gates
# dependency bounds against; SLOT was simply never given the same treatment, and
# an inventory whose rows are mostly artifacts trains its reader to skim.
#
# THE COUNT IS COMPARED FIRST, AND THE ORDER IS LOAD-BEARING. net-libs/nodejs
# declares SLOT="24" where ::gentoo declares "0/24": the overlay drops the
# subslot entirely, so a := dependency on it cannot trigger a rebuild when the
# ABI changes. It is the most valuable single finding the 007 sweep produced.
# Both sides normalise to a placeholder-bearing form, so comparing the
# normalised forms without checking the component count first calls them
# identical and deletes the finding while looking like a success.
#
# ONLY DIFFERING COMPONENTS ARE TESTED FOR DERIVABILITY, which is R1.4 read
# literally ("either side's DIFFERING component"). Normalising the equal ones
# too would be the obvious reading of R1.1 and is subtly wrong: derivability is
# evaluated against each side's OWN PV, so a component identical on both sides
# can still be derivable on one side only and not on the other - and replacing
# it on that side alone manufactures a difference out of two equal strings.
# dev-libs/liborcus is the live near-miss: its slot 0 is the ordinary slot 0,
# and it is derivable from PV 0.21.0 purely by coincidence.
compare_slot() {
	local overlay=$1 gentoo=$2
	local -a o_parts=() g_parts=()
	local i reason=""

	if [[ ${overlay} == "${gentoo}" ]]; then
		return 0
	fi

	IFS=/ read -r -a o_parts <<<"${overlay}"
	IFS=/ read -r -a g_parts <<<"${gentoo}"

	# 3.2. A different number of components is a structural difference by
	# itself and is reported without normalising anything. This is nodejs.
	if (( ${#o_parts[@]} != ${#g_parts[@]} )); then
		parity_row "${ROW_PKG}" "${ROW_OPV}" "${ROW_BPV}" "${ROW_DISTANCE}" \
			SLOT "${overlay}" "${gentoo}"
		return 0
	fi

	# 3.3. Every component that differs must be its own side's version on
	# BOTH sides. One that is not - www-client/chromium's stable against
	# unstable, dev-util/glslang's soname 16.1 against 16.3 - is the finding.
	for (( i = 0; i < ${#o_parts[@]}; i++ )); do
		if [[ ${o_parts[i]} == "${g_parts[i]}" ]]; then
			continue
		fi

		if ! slot_component_derivable "${o_parts[i]}" "${ROW_OPV}" ||
			! slot_component_derivable "${g_parts[i]}" "${ROW_BPV}"; then
			parity_row "${ROW_PKG}" "${ROW_OPV}" "${ROW_BPV}" \
				"${ROW_DISTANCE}" SLOT "${overlay}" "${gentoo}"
			return 0
		fi

		reason+="component $(( i + 1 )) is each side's own version"
		reason+=" (${o_parts[i]} from ${ROW_OPV}, ${g_parts[i]} from ${ROW_BPV}); "
	done

	# R1.5. Recorded rather than dropped: a suppression nobody can audit is
	# indistinguishable from a comparison that silently broke, and this axis
	# now loses ten of its sixteen rows to exactly that mechanism.
	PARITY_SLOT_SUPPRESSED+=( "${ROW_PKG}-${ROW_OPV}"$'\t'"${overlay}"$'\t'"${gentoo}"$'\t'"${reason%; }" )
}

# axis_raw_differs <axis>
# Whether the two sides declare the axis differently before any normalisation.
#
# Every normalisation above is deterministic, so identical inputs cannot yield a
# divergent row - and normalising is the expensive half of the sweep. Asking
# this first collapses every axis a package copies from ::gentoo verbatim, which
# is most axes of most packages, into a single string comparison.
axis_raw_differs() {
	[[ ${MD5_FIELDS[overlay:$1]-} != "${MD5_FIELDS[gentoo:$1]-}" ]]
}

# compare_ebuild_axes <category/pn> <overlay PV> <baseline PV> <distance>
# Compare one pair of md5-cache entries - already read into MD5_FIELDS - and
# append a row per axis on which they differ.
#
# WHICH AXES, AND WHY EACH IS COMPARED THE WAY IT IS (design.md's axis table):
#
#   EAPI HOMEPAGE        exact string: one value, no ordering to normalise away
#   SLOT                 component count first, then per-component derivability
#                        against each side's own PV (story 008's R1) - see
#                        compare_slot
#   INHERIT              set - which eclasses are inherited is structural, the
#                        order portage happened to emit them in is not
#   DEFINED_PHASES       set
#   LICENSE              set
#   REQUIRED_USE         string, whitespace collapsed
#   IUSE                 membership as a set, + defaults as a second set
#   KEYWORDS             arch set, ~ stripped (R1.3)
#   DEPEND RDEPEND BDEPEND
#                        atom set reduced to category/pn, with bounds, slots and
#                        USE dependencies compared only at exact distance (R1.4)
#
# NOT COMPARED, ON PURPOSE - stated here so a later reader does not "fix" the
# omission (R1.5):
#
#   SRC_URI     differs by construction whenever the version does, and the
#               overlay legitimately fetches snapshots from hosts ::gentoo never
#               uses. Every row it produced would be noise hiding the rows that
#               are not.
#   DESCRIPTION cosmetic. A reworded one-line summary is not drift to act on.
#   _md5_       the hash OF the entry rather than an axis of it: it differs
#               whenever anything else does, and says nothing extra.
#   _eclasses_  a real axis and a real finding, but sub-task 4.3's, in stage 5.
#               It is about eclass VERSIONS; which eclasses are inherited is
#               INHERIT, above.
#   IDEPEND PDEPEND RESTRICT PROPERTIES
#               outside the list R1.2 fixes. Named here so their absence reads
#               as a decision and not as an oversight.
compare_ebuild_axes() {
	local axis overlay gentoo keep_bounds=0
	local overlay_flags overlay_defaults gentoo_flags gentoo_defaults

	ROW_PKG=$1
	ROW_OPV=$2
	ROW_BPV=$3
	ROW_DISTANCE=$4

	if [[ ${ROW_DISTANCE} == exact ]]; then
		keep_bounds=1
	fi

	# Single-valued axes. One absent from BOTH entries is two empty strings,
	# which compare equal and emit nothing - correctly, since neither side
	# declares it.
	#
	# SLOT used to be compared here, exactly, alongside these two. Story 008
	# moved it out: ten of its sixteen rows reported nothing but the two
	# sides sitting at different versions. See compare_slot.
	for axis in EAPI HOMEPAGE; do
		compare_values "${axis}" "${MD5_FIELDS[overlay:${axis}]-}" \
			"${MD5_FIELDS[gentoo:${axis}]-}"
	done

	compare_slot "${MD5_FIELDS[overlay:SLOT]-}" "${MD5_FIELDS[gentoo:SLOT]-}"

	# Set-valued axes: the order portage happened to emit them in is not
	# meaning, so it must not read as divergence.
	for axis in INHERIT DEFINED_PHASES LICENSE; do
		compare_as_sets "${axis}" "${MD5_FIELDS[overlay:${axis}]-}" \
			"${MD5_FIELDS[gentoo:${axis}]-}"
	done

	# REQUIRED_USE is a nested expression, so it is compared as a string and
	# not as a set: ^^ ( a b ) and ^^ ( b a ) mean the same thing but || ( a
	# b ) and ^^ ( a b ) do not, and a set comparison cannot tell those two
	# facts apart. Whitespace is collapsed so that reindentation alone never
	# reads as a divergence.
	if axis_raw_differs REQUIRED_USE; then
		collapse_whitespace "${MD5_FIELDS[overlay:REQUIRED_USE]-}"
		overlay=${COLLAPSED}
		collapse_whitespace "${MD5_FIELDS[gentoo:REQUIRED_USE]-}"
		gentoo=${COLLAPSED}
		compare_values REQUIRED_USE "${overlay}" "${gentoo}"
	fi

	# KEYWORDS, normalised to arch membership first - see arch_membership.
	if axis_raw_differs KEYWORDS; then
		arch_membership "${MD5_FIELDS[overlay:KEYWORDS]-}"
		overlay=${ARCH_MEMBERSHIP}
		arch_membership "${MD5_FIELDS[gentoo:KEYWORDS]-}"
		gentoo=${ARCH_MEMBERSHIP}
		compare_as_sets KEYWORDS "${overlay}" "${gentoo}"
	fi

	# IUSE, as membership and then defaults.
	if axis_raw_differs IUSE; then
		iuse_split "${MD5_FIELDS[overlay:IUSE]-}"
		overlay_flags=${IUSE_SPLIT_FLAGS}
		overlay_defaults=${IUSE_SPLIT_DEFAULTS}
		iuse_split "${MD5_FIELDS[gentoo:IUSE]-}"
		gentoo_flags=${IUSE_SPLIT_FLAGS}
		gentoo_defaults=${IUSE_SPLIT_DEFAULTS}

		compare_as_sets IUSE "${overlay_flags}" "${gentoo_flags}"

		# Defaults are compared only over the flags BOTH sides declare.
		# A flag that exists on one side alone has already been reported
		# once, as membership; counting its default as a second finding
		# would say the same thing twice and inflate every total.
		set_intersection "${overlay_defaults}" "${gentoo_flags}"
		overlay=${SET_INTERSECTION}
		set_intersection "${gentoo_defaults}" "${overlay_flags}"
		gentoo=${SET_INTERSECTION}
		compare_as_sets IUSE_DEFAULTS "${overlay}" "${gentoo}"
	fi

	# The three dependency variables, at the granularity the distance earns.
	# At exact distance the two sides are the SAME version, so a differing
	# bound, slot operator or USE dependency can only be a downstream change
	# and the whole atom is compared. Anywhere else only category/pn is,
	# because a raised minimum there is the version having moved.
	for axis in DEPEND RDEPEND BDEPEND; do
		if ! axis_raw_differs "${axis}"; then
			continue
		fi

		atom_set "${MD5_FIELDS[overlay:${axis}]-}" "${keep_bounds}"
		overlay=${ATOM_SET}
		atom_set "${MD5_FIELDS[gentoo:${axis}]-}" "${keep_bounds}"
		gentoo=${ATOM_SET}

		compare_as_sets "${axis}" "${overlay}" "${gentoo}"
	done
}

# Stage 4. Compare the metadata axes of overlay and baseline.
# Publishes: PARITY_ROWS (appends; column 8 left to stage 6).
compare_axes() {
	local line entry baseline distance category pf pn key opv
	local -A covered=()
	local before rows_before=${#PARITY_ROWS[@]}
	local compared=0 diverged=0

	for entry in "${PARITY_MD5_COVERED[@]}"; do
		covered["${entry}"]=1
	done

	for line in "${PARITY_BASELINES[@]}"; do
		entry=${line%%$'\t'*}

		# Stage 3 established which pairs have an entry on both sides. A
		# pair that has not is skipped rather than read anyway: a missing
		# file yields an empty value on every axis at once, which
		# compares equal to nothing and reads as "no divergence
		# anywhere" - the most dangerous false negative there is.
		[[ -n ${covered[${entry}]+set} ]] || continue

		baseline=${line#*$'\t'}
		distance=${baseline#*$'\t'}
		baseline=${baseline%%$'\t'*}

		category=${entry%%/*}
		pf=${entry#*/}
		pn=${PARITY_EBUILD_PN[${entry}]}
		key="${category}/${pn}"
		opv=${pf#"${pn}-"}

		# Emptied here, once per pair: the reader adds to MD5_FIELDS so
		# that the two sides can share it, so a stale axis from the
		# previous ebuild would otherwise be compared against this one.
		MD5_FIELDS=()
		read_md5_cache "${OVERLAY_ROOT}/metadata/md5-cache/${category}/${pf}" \
			overlay
		read_md5_cache "${GENTOO_REPO}/metadata/md5-cache/${category}/${pn}-${baseline}" \
			gentoo

		before=${#PARITY_ROWS[@]}
		compare_ebuild_axes "${key}" "${opv}" "${baseline}" "${distance}"
		compared=$(( compared + 1 ))
		if (( ${#PARITY_ROWS[@]} > before )); then
			diverged=$(( diverged + 1 ))
		fi
	done

	printf '  [axes]     %d metadata row(s); %d of %d ebuild(s) compared diverge on some axis\n' \
		"$(( ${#PARITY_ROWS[@]} - rows_before ))" "${diverged}" "${compared}"

	# R1.5, on stdout as well as in the report: the count a reader needs in
	# order to notice that a suppression rule has started swallowing the tree.
	printf '  [slot]     %d SLOT row(s) suppressed as version artifacts, each recorded with its reason\n' \
		"${#PARITY_SLOT_SUPPRESSED[@]}"
}

### the axes md5-cache does not carry #################################
#
# Stage 4 compared what egencache wrote down. Three things it never writes down
# still decide whether two copies of a package behave the same: the metadata.xml
# beside the ebuild, whatever sits under files/, and the PATCHES array in the
# ebuild text. Parity claimed on md5-cache alone is parity claimed on one file
# per package.
#
# A fourth, _eclasses_, IS in md5-cache but is not about the ebuild: it records
# which eclass CONTENT the entry was generated against, so it reads a
# repository-wide fact off a per-package entry (R4.3). Stage 4's header says it
# was left for here; this is here.

# The two positional columns a package-level row has no version to put in.
# metadata.xml and files/ belong to the package DIRECTORY, not to any one of the
# ebuilds in it, so there is no overlay PV and no baseline PV to name. They
# cannot simply be left empty: a tab is IFS whitespace, so an empty column in the
# middle of a row is swallowed and shifts every column after it when the row is
# read back. The distance column gets its own value rather than borrowing one of
# stage 2's three, because "exact" on a row that compares no versions would be a
# claim the row is not making.
PACKAGE_ROW_PV='(package)'
PACKAGE_ROW_DISTANCE='package'

# THE TWO AXES WITH NO JUSTIFICATION MECHANISM (R4.4)
#
# Every axis stage 4 emits lives in an ebuild, so a divergence on it can be
# justified where it is: sub-task 5.2's parser reads a "# BENTOO-DIVERGENCE:
# <axis>" comment out of the ebuild that carries the divergence. metadata.xml
# and files/ have no such ebuild. The difference is in a file holding no bash,
# sitting beside N ebuilds none of which owns it, so there is nowhere to put the
# tag and no rule that would pick which of the N should carry it.
#
# Decided at the Phase 1 gate and deliberately NOT worked around here: this
# inventory measures the volume first. If it is low no mechanism is needed, and
# if it is high the shape of the data decides what the mechanism should be -
# rather than a guess made before the data existed.
#
# The consequence is that every row on these axes reaches the report as ALIGN
# and can never be anything else. R3.1 requires exactly one of the four verdicts
# on every divergence, so "no verdict" was never available; what these axes lack
# is the EVIDENCE that promotes one. ALIGN there therefore means something
# weaker than ALIGN elsewhere - not "no reason was recorded" but "no reason
# COULD be recorded" - and nothing in the row itself distinguishes the two. So
# the report says which it is, and it says it IN PLACE.
#
# HOW SUB-TASK 6.2 CONSUMES THIS. parity-report.md groups rows by axis. For each
# section whose axis appears in PARITY_UNJUSTIFIABLE_AXES, print
# PARITY_UNJUSTIFIABLE_NOTE directly under that section's heading - not once at
# the foot of the report. The reader this is for is the one who skims to the
# files/ section and stops there; a footnote is read by whoever already knew.
# Sub-task 5.2 wants the same list for the opposite reason: a row on one of
# these axes must not be promoted to UNDOCUMENTED for lacking a tag it cannot
# carry. Both consume the array, so neither has to restate the list of axes.
# files/overlay-only and files/gentoo-only WERE here until 2026-09-06. They are
# no longer emitted at all: the first is partitioned into a suppression and the
# new files/unreferenced axis, the second is suppressed whole. See the files
# stage for the measurement that justified it.
#
# WHAT THIS LIST MEANS CHANGED ON 2026-09-06, and the old reading was a mistake
# worth recording. It used to be "these rows can never be JUSTIFIED either",
# argued from "the file holds no ebuild code, so it cannot carry a tag". That
# confuses WHERE THE DIFFERENCE IS with WHERE THE REASON CAN BE WRITTEN. A patch
# under files/ exists because an ebuild applies it, and a metadata.xml describes
# a package whose ebuilds are right there; the ebuild is the natural place for
# the reason, and collect_tags now registers a package-level key so a tag can
# reach these rows.
#
# The old reading had a cost. Every row on these two axes was ALIGN FOREVER, by
# construction, however deliberate the divergence - chromium's patched
# bin-finder.py, open-vm-tools' overlay-only init script, thirteen zed USE flags
# ::gentoo does not have. Eleven permanently red rows in a guard is how a guard
# becomes one people stop reading.
#
# What the list still does, and correctly: it keeps these axes from being
# promoted to UNDOCUMENTED. That verdict means "somebody added this to the
# overlay and recorded no reason", and it is a claim about ebuild content that
# a file-level difference cannot support.
PARITY_UNJUSTIFIABLE_AXES=(
	'metadata.xml'
	'files/content'
)
PARITY_UNJUSTIFIABLE_NOTE='never promoted to UNDOCUMENTED on this axis: the difference is in a file that holds no ebuild code, so nobody can have written an addition INTO it the way the UNDOCUMENTED rule means. A tag in any ebuild of the package still justifies the row - the file cannot carry the reason, but the package can.'

OVERLAY_EBUILD=""

# resolve_overlay_ebuild <category/pf> <pn>
# Which file to read the overlay ebuild's TEXT from, into OVERLAY_EBUILD.
#
# PARITY_TAG_SOURCE first, the tracked ebuild second. That order is the seam
# described where the map is declared: the self-test tags a COPY under $TMPDIR
# because R7 forbids editing a tracked ebuild even to test the parser that reads
# it. Sub-task 5.2's tag parser resolves through this same function - one
# lookup, so there is one place to get it wrong instead of two.
resolve_overlay_ebuild() {
	local entry=$1 pn=$2
	local category=${entry%%/*} pf=${entry#*/}

	if [[ -n ${PARITY_TAG_SOURCE[${entry}]-} ]]; then
		OVERLAY_EBUILD=${PARITY_TAG_SOURCE[${entry}]}
		return 0
	fi

	OVERLAY_EBUILD="${OVERLAY_ROOT}/${category}/${pn}/${pf}.ebuild"
}

FILE_TEXT=""

# read_file_text <path>
# The whole file in FILE_TEXT, or the empty string when there is no such file.
#
# read -d '' stops at the first NUL - which none of these files contains - and
# returns 1 having read everything, because it never found its delimiter. That
# is the normal case here, not a failure. Comparing two whole strings is exact
# where joining two mapfile arrays is not: two files differing only in where the
# newlines fall would join to the same string.
read_file_text() {
	FILE_TEXT=""
	[[ -f $1 ]] || return 0
	IFS= read -r -d '' FILE_TEXT <"$1" || true
}

ONE_LINE=""

# one_line <text> <maximum length>
# The text as one line of at most that many characters, into ONE_LINE. A summary
# column that grows to the size of what it summarises is not a summary.
one_line() {
	collapse_whitespace "$1"

	if (( ${#COLLAPSED} > $2 )); then
		ONE_LINE="${COLLAPSED:0:$2}..."
	else
		ONE_LINE=${COLLAPSED}
	fi
}

DIFF_ONLY_OVERLAY=""
DIFF_ONLY_GENTOO=""

# summarise_diff <overlay file> <::gentoo file>
# A textual diff reduced to one line per side, into DIFF_ONLY_OVERLAY and
# DIFF_ONLY_GENTOO: how many lines only that side has, and the first of them.
#
# Sub-task 4.1 asks for a summary rather than the diff, and the row format is
# the reason. parity-data.tsv has one row per divergence and no escaping, so a
# diff pasted into a value column would be either flattened into an unreadable
# run or split across rows. The count says how much diverged and the excerpt
# says what, which is enough to decide whether to go and look.
#
# Only "< " and "> " lines are read. diff's hunk headers start with a digit and
# its separator with a dash, so neither can be mistaken for content; a blank
# line in the file arrives as "< " and survives as the empty string it is.
summarise_diff() {
	local line text
	local -a only_overlay=() only_gentoo=()

	while IFS= read -r line; do
		case ${line} in
		'<'*)
			text=${line#<}
			only_overlay+=( "${text# }" )
			;;
		'>'*)
			text=${line#>}
			only_gentoo+=( "${text# }" )
			;;
		esac
	done < <(diff -- "$1" "$2" || true)

	DIFF_ONLY_OVERLAY=""
	DIFF_ONLY_GENTOO=""

	if (( ${#only_overlay[@]} )); then
		one_line "${only_overlay[0]}" 90
		DIFF_ONLY_OVERLAY="${#only_overlay[@]} line(s) only here: ${ONE_LINE}"
	fi
	if (( ${#only_gentoo[@]} )); then
		one_line "${only_gentoo[0]}" 90
		DIFF_ONLY_GENTOO="${#only_gentoo[@]} line(s) only here: ${ONE_LINE}"
	fi
}

IUSE_UNION=""

# iuse_union <repo root> <category/pn>
# Every IUSE flag name the side declares for this package, across all its
# md5-cache entries, +/- stripped, into IUSE_UNION padded with spaces so a
# membership test is a substring test.
iuse_union() {
	local root=$1 key=$2 cat=${2%%/*} pn=${2#*/}
	local f line flag

	IUSE_UNION=" "
	for f in "${root}/metadata/md5-cache/${cat}/${pn}"-*; do
		[[ -f ${f} ]] || continue
		# <pn>-<version>, not a sibling whose name merely starts the same
		[[ ${f##*/} =~ ^${pn}-[0-9] ]] || continue
		line=$(grep -m1 '^IUSE=' "${f}" 2>/dev/null) || continue
		for flag in ${line#IUSE=}; do
			flag=${flag#[+-]}
			case ${IUSE_UNION} in
				*" ${flag} "*) ;;
				*) IUSE_UNION+="${flag} " ;;
			esac
		done
	done
}

METADATA_FLAGS=""

# metadata_flags <metadata.xml>
# The <use><flag name=...> names it declares, space padded like IUSE_UNION.
metadata_flags() {
	local raw name

	METADATA_FLAGS=" "
	raw=$(xmllint --xpath '//use/flag/@name' "$1" 2>/dev/null) || raw=""
	for name in $(printf '%s' "${raw}" | sed -E 's/ ?name="([^"]*)"/\1\n/g'); do
		case ${METADATA_FLAGS} in
			*" ${name} "*) ;;
			*) METADATA_FLAGS+="${name} " ;;
		esac
	done
}

METADATA_BODY=""

# metadata_body <metadata.xml>
# Everything EXCEPT the maintainer and use blocks, whitespace collapsed. Those
# two are the parts an overlay is expected to differ on; the rest is content.
metadata_body() {
	local raw
	raw=$(xmllint --xpath '//pkgmetadata/*[not(self::maintainer) and not(self::use)]' "$1" 2>/dev/null) || raw=""
	METADATA_BODY=$(printf '%s' "${raw}" | tr -s '[:space:]' ' ')
}

# Sub-task 4.1. metadata.xml, for every shared package.
#
# R4.1 says every shared package, and an absent file is therefore a finding and
# not a licence to skip: a package with a metadata.xml on one side only has
# nothing to diff, which is the loudest divergence there is rather than the
# quietest. Measured 2026-08-06: all 232 have one on both sides, so the branch
# below is empty today and says so in the count rather than being left out.
compare_metadata_xml() {
	local key overlay_file gentoo_file overlay_text overlay_state gentoo_state
	local body_overlay flags_overlay iuse_overlay explained flag
	local diverged=0 incomplete=0 suppressed=0

	for key in "${PARITY_SHARED_PACKAGES[@]}"; do
		overlay_file="${OVERLAY_ROOT}/${key}/metadata.xml"
		gentoo_file="${GENTOO_REPO}/${key}/metadata.xml"

		if [[ ! -f ${overlay_file} || ! -f ${gentoo_file} ]]; then
			incomplete=$(( incomplete + 1 ))
			overlay_state='no metadata.xml'
			gentoo_state='no metadata.xml'
			if [[ -f ${overlay_file} ]]; then
				overlay_state='present'
			fi
			if [[ -f ${gentoo_file} ]]; then
				gentoo_state='present'
			fi
			parity_row "${key}" "${PACKAGE_ROW_PV}" "${PACKAGE_ROW_PV}" \
				"${PACKAGE_ROW_DISTANCE}" 'metadata.xml' \
				"${overlay_state}" "${gentoo_state}"
			continue
		fi

		read_file_text "${overlay_file}"
		overlay_text=${FILE_TEXT}
		read_file_text "${gentoo_file}"
		if [[ ${overlay_text} == "${FILE_TEXT}" ]]; then
			continue
		fi

		diverged=$(( diverged + 1 ))

		# Two of the three things metadata.xml holds cannot align, and
		# saying so is the whole of this block.
		#
		# The MAINTAINER is definitional. This overlay maintains its fork
		# and ::gentoo maintains theirs; a row saying the two names differ
		# will be true for every package here, forever, and clearing it
		# would mean handing the package back.
		#
		# A USE FLAG DESCRIPTION shadows the IUSE axis, which already has a
		# # BENTOO-DIVERGENCE: mechanism. QA REQUIRES a description for
		# every local flag, so adding a flag necessarily edits
		# metadata.xml: reporting both counted one decision twice. Checked
		# per side against that side's own IUSE rather than against the
		# axis row, so this does not depend on stage ordering.
		#
		# What is NOT suppressed: a flag described on a side whose IUSE
		# does not have it - that is a stale description, pkgcheck's
		# UnusedLocalUse - and any difference in the REST of the file,
		# longdescription and upstream, which is real content.
		metadata_body "${overlay_file}"
		body_overlay=${METADATA_BODY}
		metadata_body "${gentoo_file}"
		if [[ ${body_overlay} == "${METADATA_BODY}" ]]; then
			metadata_flags "${overlay_file}"
			flags_overlay=${METADATA_FLAGS}
			metadata_flags "${gentoo_file}"
			iuse_union "${OVERLAY_ROOT}" "${key}"
			iuse_overlay=${IUSE_UNION}
			iuse_union "${GENTOO_REPO}" "${key}"
			explained=yes
			for flag in ${flags_overlay}; do
				case ${METADATA_FLAGS} in
					*" ${flag} "*) continue ;;
				esac
				case ${iuse_overlay} in
					*" ${flag} "*) ;;
					*) explained="" ;;
				esac
			done
			for flag in ${METADATA_FLAGS}; do
				case ${flags_overlay} in
					*" ${flag} "*) continue ;;
				esac
				case ${IUSE_UNION} in
					*" ${flag} "*) ;;
					*) explained="" ;;
				esac
			done
			if [[ -n ${explained} ]]; then
				suppressed=$(( suppressed + 1 ))
				PARITY_METADATA_SUPPRESSED+=( "${key}"$'\t'"maintainer and/or USE flag descriptions that follow each side's own IUSE" )
				continue
			fi
		fi

		summarise_diff "${overlay_file}" "${gentoo_file}"
		parity_row "${key}" "${PACKAGE_ROW_PV}" "${PACKAGE_ROW_PV}" \
			"${PACKAGE_ROW_DISTANCE}" 'metadata.xml' \
			"${DIFF_ONLY_OVERLAY}" "${DIFF_ONLY_GENTOO}"
	done

	printf '  [metadata] %d of %d shared package(s) diverge on metadata.xml; %d examined without one on a side\n' \
		"${diverged}" "${#PARITY_SHARED_PACKAGES[@]}" "${incomplete}"
	printf '  [metadata] %d of those suppressed as maintainer or IUSE-shadow only, each recorded with its reason\n' \
		"${suppressed}"
}

# Every regular file under one files/ directory, keyed "<side>:<name relative to
# it>" with its SHA256. One array for both sides, for the reason MD5_FIELDS
# gives: the alternative is passing an array name in, and a nameref is a
# variable shellcheck cannot follow.
declare -A FILE_DIGESTS=()

DIGEST_NAMES=""

# digest_tree <directory> <side>
# Fill FILE_DIGESTS for that side, and leave the relative names, sorted and
# space separated, in DIGEST_NAMES. A directory that does not exist is not an
# error - it is the empty set, which is what the comparison needs it to be.
#
# Recursive, and that is not incidental. files/ is not flat: binutils keeps a
# whole patchset under files/patches-1/, thunderbird an icon/ subdirectory, and
# ::gentoo's lua a per-slot 5.1/. A comparison that listed only the top level
# would call two entirely different patchsets identical because both are "one
# directory named patches-1".
#
# One find and one batched sha256sum per side, not a fork per file: 560 files
# across the 80 shared packages that have a files/ directory on either side
# (measured 2026-08-06). sha256sum escapes a name containing a backslash or a
# newline and flags the line with a leading backslash; neither tree has such a
# name, and a newline in one would corrupt the read loop rather than be
# reported, which is stated here because it cannot be detected after the fact.
digest_tree() {
	local dir=$1 side=$2
	local line digest path rel

	DIGEST_NAMES=""
	[[ -d ${dir} ]] || return 0

	while IFS= read -r line; do
		digest=${line%% *}
		digest=${digest#\\}
		path=${line#* }
		path=${path# }
		rel=${path#"${dir}/"}

		FILE_DIGESTS["${side}:${rel}"]=${digest}
		DIGEST_NAMES+="${rel} "
	done < <(find "${dir}" -type f -exec sha256sum -- {} + 2>/dev/null | sort -k2)

	DIGEST_NAMES=${DIGEST_NAMES% }
}

FILESDIR_REFS=""
# Patterns NO ebuild text names -- an eclass reads them straight out of
# FILESDIR. Kept apart from FILESDIR_REFS because they answer opposite
# questions: they must SUPPRESS an orphan, but they must never be treated as a
# reference whose target has to exist. A package that inherits the eclass and
# has no README.gentoo is not broken.
FILESDIR_REFS_ECLASS=""

# filesdir_refs <repo root> <category/pn>
# Every files/ name the package's ebuilds reach through ${FILESDIR}, into
# FILESDIR_REFS as a space-separated list of GLOB patterns.
#
# WHY THIS EXISTS. Measured on 2026-09-06: 62 of 66 files/overlay-only names and
# 123 of 132 files/gentoo-only names are reached from an ebuild in their own
# package. So neither axis measures an independent divergence - both are shadows
# of PATCHES and the phase functions, which already carry a
# # BENTOO-DIVERGENCE: tag. Reporting them as ALIGN made half of all ALIGN rows
# noise that no action could ever clear.
#
# THREE WAYS TO GET THIS WRONG, all of them hit before this was right:
#   - a row's value is a SPACE-SEPARATED LIST of names, not one name;
#   - ebuilds name patches through interpolation (${P}-nettle-4.patch), so
#     matching the literal filename under-counts badly;
#   - "${FILESDIR}"/x puts a quote BETWEEN the variable and the path, so a
#     pattern that stops at the quote sees a bare ${FILESDIR} and misses the
#     reference entirely.
# Hence: read the expression past an optional quote, expand PN/P/PV/PF, and turn
# any remaining ${VAR} into a wildcard rather than guessing its value.
# expand_braces <string>
# One level of brace expansion, space separated. Bash does this for a literal
# but NOT for the contents of a variable, and eval on text lifted out of an
# ebuild is not a trade worth making.
#
# WHY IT IS NEEDED. Three ebuilds reference files this way today -
# flatpak-update.{service,timer}, rustdesk{,-link}.desktop and
# {50-${PN},wrapper.in} - and without expansion the reference matches nothing,
# so six files in active use were reported as orphans. That is the worst kind of
# false positive here: it invites someone to delete a file the build needs.
#
# The empty element matters: rustdesk{,-link} means rustdesk.desktop AND
# rustdesk-link.desktop, so the split has to preserve an empty field, which is
# why this reads with IFS into an array rather than looping over an unquoted
# expansion.
expand_braces() {
	local s=$1 pre mid post part out=""
	local -a parts=()

	if [[ ${s} != *\{*\}* ]]; then
		printf '%s' "${s}"
		return 0
	fi

	pre=${s%%\{*}
	mid=${s#*\{}
	mid=${mid%%\}*}
	post=${s#*\}}

	IFS=, read -r -a parts <<<"${mid}"
	for part in "${parts[@]}"; do
		out+="${pre}${part}${post} "
	done
	printf '%s' "${out% }"
}

filesdir_refs() {
	local root=$1 key=$2 pn=${2#*/}
	local eb base pv pvr expr

	FILESDIR_REFS=""
	FILESDIR_REFS_ECLASS=""
	FILESDIR_REFS_GUARDED=""
	for eb in "${root}/${key}"/*.ebuild; do
		[[ -f ${eb} ]] || continue
		base=${eb##*/}
		base=${base%.ebuild}
		# PVR carries the revision, PV does NOT, and ${P} is ${PN}-${PV}.
		# Deriving one number from the filename and using it for both was a
		# real false-positive source: dev-util/breakpad-2024.02.16-r1
		# references "${FILESDIR}"/${P}-gcc16-vtable.patch, which expands to
		# breakpad-2024.02.16-gcc16-vtable.patch. Substituting the revision
		# too produced breakpad-2024.02.16-r1-gcc16-vtable.patch, matched
		# nothing, and reported a live patch as an unreferenced file.
		pvr=${base#"${pn}-"}
		pv=${pvr%-r[0-9]*}
		while IFS= read -r expr; do
			expr=${expr//\$\{PF\}/${base}}
			expr=${expr//\$\{PVR\}/${pvr}}
			expr=${expr//\$\{P\}/${pn}-${pv}}
			expr=${expr//\$\{PN\}/${pn}}
			expr=${expr//\$\{PV\}/${pv}}
			expr=$(printf '%s' "${expr}" |
				sed -E 's/\$\{[A-Za-z_][A-Za-z0-9_]*\}/*/g')
			# After the variable substitutions, so {50-${PN},...} has
			# already become {50-openoffice-bin,...} by the time it splits.
			FILESDIR_REFS+="$(expand_braces "${expr}") "
		# A $(...) AFTER ${FILESDIR}/ is read as one unit, then globbed like
		# an unknown ${VAR}: left to the plain character class, its space
		# and ")" end the match early -- "$(ver_cut 1-2)-${p}" came out as
		# "$(ver_cut" (A32). Only after the prefix: a reference sitting INSIDE
		# one, as in $(cat "${FILESDIR}/condarc.user"), must still be read
		# (A33). Non-nested forms only, which is every one in the tree.
		done < <(grep -v '^[[:space:]]*#' "${eb}" 2>/dev/null |
			grep -hoE '\$\{FILESDIR\}"?/(\$\([^()]*\)|[^[:space:])"'"'"';])+' |
			sed -E 's/\$\([^()]*\)/*/g' |
			sed -E 's|^\$\{FILESDIR\}"?/||')

		# readme.gentoo-r1.eclass reads the file out of FILESDIR itself and
		# the ebuild never names it: readme.gentoo_create_doc falls back to
		# ${FILESDIR}/README.gentoo${README_GENTOO_SUFFIX}, and to
		# README.gentoo-${SLOT}, whenever DOC_CONTENTS is unset -- then dies
		# if neither exists. www-client/librewolf is exactly that shape, so
		# its README.gentoo was reported as an orphan and deleting it would
		# have broken src_install.
		#
		# Matched anywhere in the file rather than anchored to a line
		# starting with `inherit`, because a long inherit wraps with a
		# backslash and the eclass routinely lands on the continuation --
		# it does in librewolf. Crediting the whole README.gentoo* family
		# errs toward silence, which is the right direction here: the
		# remediation this check suggests is deletion.
		if grep -q 'readme\.gentoo-r1' "${eb}"; then
			FILESDIR_REFS_ECLASS+="README.gentoo* "
		fi

		# References the ebuild TESTS for before using them:
		#   [[ -d "${FILESDIR}"/${PV} ]] && eapply "${FILESDIR}"/${PV}
		# media-video/pipewire carries exactly that (as ::gentoo does), and
		# the missing-reference check reported it as a reference that DIES
		# at install -- false, the use is skipped when the path is absent.
		# Only the -d/-e/-f/-s tests count, and only for the path tested.
		while IFS= read -r expr; do
			expr=${expr//\$\{PF\}/${base}}
			expr=${expr//\$\{PVR\}/${pvr}}
			expr=${expr//\$\{P\}/${pn}-${pv}}
			expr=${expr//\$\{PN\}/${pn}}
			expr=${expr//\$\{PV\}/${pv}}
			expr=$(printf '%s' "${expr}" |
				sed -E 's/\$\{[A-Za-z_][A-Za-z0-9_]*\}/*/g')
			FILESDIR_REFS_GUARDED+="$(expand_braces "${expr}") "
		done < <(grep -v '^[[:space:]]*#' "${eb}" 2>/dev/null |
			grep -hoE -- '-[defs][[:space:]]+"?\$\{FILESDIR\}"?/[^][:space:])"'"'"';]+' |
			sed -E 's|^-[defs][[:space:]]+"?\$\{FILESDIR\}"?/||')
	done
	FILESDIR_REFS=${FILESDIR_REFS% }
	FILESDIR_REFS_ECLASS=${FILESDIR_REFS_ECLASS% }
	FILESDIR_REFS_GUARDED=${FILESDIR_REFS_GUARDED% }
}

# split_by_reference <names> <patterns>
# Partition a row's names into SPLIT_REFERENCED and SPLIT_ORPHAN. `case` rather
# than [[ == ]] so the glob works without a shellcheck suppression.
SPLIT_REFERENCED=""
SPLIT_ORPHAN=""
split_by_reference() {
	local names=$1 patterns=$2
	local -a name_list=() pattern_list=()
	local name pattern hit regex

	SPLIT_REFERENCED=""
	SPLIT_ORPHAN=""
	read -r -a name_list <<<"${names}"
	read -r -a pattern_list <<<"${patterns}"
	for name in "${name_list[@]}"; do
		hit=""
		for pattern in "${pattern_list[@]}"; do
			# Glob translated to a regex rather than matched as a
			# `case` pattern or with [[ == ]]. Both of those need an
			# UNQUOTED expansion to keep the glob alive, which raises
			# SC2254 and SC2053, and this file carries no
			# suppressions -- so the check has to pass on its own
			# terms rather than be silenced.
			#
			# Do NOT start a comment line here with the linter's own
			# name: a line beginning "# <that name>" is parsed as a
			# DIRECTIVE, and an unparseable one turns the whole
			# function into SC1009/SC1072/SC1073 parse errors while
			# bash -n still reports the file as fine.
			#
			# Every ERE metacharacter but the glob's own `*` is escaped,
			# not just the dot: a file name is a literal, and `+` is a
			# legal one. sys-apps/memtest86+ ships 39_memtest86+-r3,
			# which unescaped reads as "one or more 6" and never matched
			# its own name -- reported as an orphan while the ebuild
			# installed it.
			regex=${pattern//\\/\\\\}
			regex=${regex//./\\.}
			regex=${regex//+/\\+}
			regex=${regex//\?/\\?}
			regex=${regex//(/\\(}
			regex=${regex//)/\\)}
			regex=${regex//|/\\|}
			regex=${regex//^/\\^}
			regex=${regex//\$/\\$}
			regex=${regex//\[/\\[}
			regex=${regex//\{/\\\{}
			regex=${regex//\*/.*}
			if [[ ${name} =~ ^${regex}$ ]]; then
				hit=yes
				break
			fi
		done
		if [[ -n ${hit} ]]; then
			SPLIT_REFERENCED+="${name} "
		else
			SPLIT_ORPHAN+="${name} "
		fi
	done
	SPLIT_REFERENCED=${SPLIT_REFERENCED% }
	SPLIT_ORPHAN=${SPLIT_ORPHAN% }
}

# Sub-task 4.2. files/ as a set of names and SHA256 digests (R4.2).
#
# THREE CASES, THREE AXES, ON PURPOSE. A file only the overlay has is a
# downstream patch. A file only ::gentoo has is a fix the overlay may be
# missing. A file BOTH have under the same name with different content is the
# one that breaks a bump silently: the ebuild applies ${FILESDIR}/x.patch, both
# trees have an x.patch, and nothing anywhere says they are not the same patch.
# Folding the three into one row would make the third indistinguishable from the
# other two at a glance, which is the glance it has to survive. Task 3 set the
# precedent when it split IUSE into IUSE and IUSE_DEFAULTS: separate findings
# need separate names.
#
# HONEST CAVEAT, because the ::gentoo-only count is the big one. ::gentoo's
# files/ serves every version ::gentoo carries, and it carries versions the
# overlay does not - dev-lang/ghc's directory holds patches for 9.0.2 and 9.2.7.
# So a ::gentoo-only file is often a patch for an ebuild the overlay never had,
# not a fix it is missing. The overlay-only and same-name-different-content
# cases do not have this problem.
compare_files_dirs() {
	local key overlay_dir gentoo_dir name
	local overlay_list gentoo_list only_overlay only_gentoo
	local content_overlay content_gentoo
	local -a surplus=() shared_names=()
	local packages=0 n_overlay=0 n_gentoo=0 n_content=0
	local n_suppressed=0 n_orphan=0

	for key in "${PARITY_SHARED_PACKAGES[@]}"; do
		overlay_dir="${OVERLAY_ROOT}/${key}/files"
		gentoo_dir="${GENTOO_REPO}/${key}/files"
		if [[ ! -d ${overlay_dir} && ! -d ${gentoo_dir} ]]; then
			continue
		fi
		packages=$(( packages + 1 ))

		# Emptied per package rather than per side: digest_tree adds, so
		# that the two sides can share one array, and a name left over
		# from the previous package would be compared against this one.
		FILE_DIGESTS=()
		digest_tree "${overlay_dir}" overlay
		overlay_list=${DIGEST_NAMES}
		digest_tree "${gentoo_dir}" gentoo
		gentoo_list=${DIGEST_NAMES}

		set_difference "${overlay_list}" "${gentoo_list}"
		only_overlay=${SET_ONLY_A}
		only_gentoo=${SET_ONLY_B}

		content_overlay=""
		content_gentoo=""
		set_intersection "${overlay_list}" "${gentoo_list}"
		read -r -a shared_names <<<"${SET_INTERSECTION}"
		for name in "${shared_names[@]}"; do
			if [[ ${FILE_DIGESTS[overlay:${name}]} == "${FILE_DIGESTS[gentoo:${name}]}" ]]; then
				continue
			fi
			# Each side carries the digest it actually has, cut to
			# twelve characters: the row has to SAY they differ, and
			# a name repeated in both columns would only say they
			# are both there.
			content_overlay+="${name}:${FILE_DIGESTS[overlay:${name}]:0:12} "
			content_gentoo+="${name}:${FILE_DIGESTS[gentoo:${name}]:0:12} "
			n_content=$(( n_content + 1 ))
		done

		# An overlay-only file whose name an ebuild here reaches is not an
		# independent divergence: it exists BECAUSE a PATCHES or newinitd
		# line names it, and that line sits on an axis which already
		# carries a # BENTOO-DIVERGENCE: tag. Suppressed with its reason
		# recorded (R1.5). What survives is the file no ebuild names --
		# dead weight in the tree, which nothing measured before.
		if [[ -n ${only_overlay} ]]; then
			read -r -a surplus <<<"${only_overlay}"
			n_overlay=$(( n_overlay + ${#surplus[@]} ))
			filesdir_refs "${OVERLAY_ROOT}" "${key}"
			split_by_reference "${only_overlay}" "${FILESDIR_REFS} ${FILESDIR_REFS_ECLASS}"
			if [[ -n ${SPLIT_REFERENCED} ]]; then
				read -r -a surplus <<<"${SPLIT_REFERENCED}"
				n_suppressed=$(( n_suppressed + ${#surplus[@]} ))
				PARITY_FILES_SUPPRESSED+=( "${key}"$'\t''files/overlay-only'$'\t'"${#surplus[@]}"$'\t'"reached from an ebuild through \${FILESDIR}: ${SPLIT_REFERENCED}" )
			fi
			# The orphans are NOT emitted here any more. They moved to
			# check_orphan_files, which scans the whole overlay: a file
			# no ebuild names is litter in THIS tree, not a divergence
			# from ::gentoo, and keying it to the shared set meant the
			# 104 overlay-only packages were never looked at. Counted
			# here only for the stage line below.
			if [[ -n ${SPLIT_ORPHAN} ]]; then
				read -r -a surplus <<<"${SPLIT_ORPHAN}"
				n_orphan=$(( n_orphan + ${#surplus[@]} ))
			fi
		fi
		# files/gentoo-only is suppressed whole, and for a different reason
		# than the above: it is not actionable in this overlay AT ALL. It
		# says ::gentoo carries patch files we do not, which follows from
		# shipping different versions with different patch sets. If we ever
		# needed one of them, the PATCHES axis is where that would show,
		# with a mechanism to justify it. 123 of its 132 names were reached
		# from a ::gentoo ebuild when this was measured; the other nine are
		# dead weight on their side, not ours.
		if [[ -n ${only_gentoo} ]]; then
			read -r -a surplus <<<"${only_gentoo}"
			n_gentoo=$(( n_gentoo + ${#surplus[@]} ))
			PARITY_FILES_SUPPRESSED+=( "${key}"$'\t''files/gentoo-only'$'\t'"${#surplus[@]}"$'\t'"::gentoo's own patch set for its own versions; the PATCHES axis is where a missing fix would show" )
		fi
		if [[ -n ${content_overlay} ]]; then
			parity_row "${key}" "${PACKAGE_ROW_PV}" "${PACKAGE_ROW_PV}" \
				"${PACKAGE_ROW_DISTANCE}" 'files/content' \
				"${content_overlay% }" "${content_gentoo% }"
		fi
	done

	printf '  [files]    %d package(s) with a files/ directory on some side: %d file(s) overlay-only, %d ::gentoo-only, %d same name and different content\n' \
		"${packages}" "${n_overlay}" "${n_gentoo}" "${n_content}"
	printf '  [files]    %d name(s) suppressed as reachable from an ebuild, each recorded with its reason; %d overlay file(s) no ebuild references\n' \
		"${n_suppressed}" "${n_orphan}"
}

ECLASSES_FIELD=""

# eclasses_field <md5-cache file>
# The entry's _eclasses_ value, into ECLASSES_FIELD. Empty when the entry has no
# such line, which is an ebuild that inherits nothing.
eclasses_field() {
	local -a lines=()
	local line

	ECLASSES_FIELD=""
	mapfile -t lines <"$1"

	for line in "${lines[@]}"; do
		if [[ ${line} == '_eclasses_='* ]]; then
			ECLASSES_FIELD=${line#_eclasses_=}
			return 0
		fi
	done
}

# The eclass hashes of the pair being compared, keyed "<side>:<eclass>". One
# array for both sides, as above.
declare -A ECLASS_HASH=()

ECLASS_NAMES=""

# read_eclass_hashes <_eclasses_ value> <side>
# Fill ECLASS_HASH for that side and leave the eclass names, in the order the
# entry lists them, in ECLASS_NAMES.
#
# The field is one flat TAB separated list alternating name and hash -
# "ecm<TAB>03a0...<TAB>xdg<TAB>3ef4..." - and it is the TRANSITIVE closure, so
# an eclass no ebuild ever names is in it because something it inherits is.
read_eclass_hashes() {
	local side=$2 i
	local -a fields=()

	ECLASS_NAMES=""
	IFS=$'\t' read -r -a fields <<<"$1"

	for (( i = 0; i + 1 < ${#fields[@]}; i += 2 )); do
		ECLASS_HASH["${side}:${fields[i]}"]=${fields[i + 1]}
		ECLASS_NAMES+="${fields[i]} "
	done

	ECLASS_NAMES=${ECLASS_NAMES% }
}

# Sub-task 4.3. Eclasses whose recorded hash differs between the two trees.
#
# R1.6, AND WHY THE LOCAL LIST IS READ FROM A DIRECTORY. An eclass the overlay
# ships is resolved from the overlay for every overlay ebuild that inherits it,
# so the hash in the overlay's md5-cache is the hash of the OVERLAY's copy and
# differs from ::gentoo's by construction. Reporting that would be reporting the
# decision to ship a copy, not a consequence of it, so those are recorded as
# definitionally divergent in PARITY_ECLASS_DEFINITIONAL instead.
#
# The list comes from eclass/*.eclass rather than from three names written here,
# and the difference is not cosmetic. Two of the three - gstreamer-meson and rpm
# - shadow a ::gentoo eclass and would be findable from the data. brave has no
# ::gentoo counterpart at all AND is inherited only by www-client/brave-browser,
# which ::gentoo does not carry, so it is not in the shared set and never
# reaches this comparison. Built from observations it would silently not be
# recorded; built from the directory it is recorded, with its inheritor count
# reading 0 and saying exactly why.
#
# Membership is not compared here. An eclass present on one side only is the
# INHERIT axis's finding when it is inherited directly, and the mechanical
# consequence of a hash that already has its own row when it is transitive.
# R4.3 is about an eclass whose CONTENT differs, which is the intersection.
#
# STORY 008: THIS AXIS NO LONGER EMITS A DIVERGENCE ROW, AND THAT IS EXHAUSTIVE
# RATHER THAN A LOSS. Every differing hash falls into one of exactly two cases,
# and neither is drift in the tree:
#
#   the overlay SHIPS the eclass    the two trees hashed two different files,
#                                   so they differ by construction. Story 007's
#                                   R1.6 already recorded these as definitional
#
#   the overlay does NOT ship it    then BOTH trees resolved the same ::gentoo
#                                   file, so the hashes cannot describe
#                                   different content - only different moments.
#                                   The overlay's md5-cache is out of date.
#                                   Story 008's R2.1: a stale cache
#
# There is no third case, which is why the row-emitting path was removed rather
# than left unreachable. Story 008's R2.5 - "keep reporting a real finding where
# the overlay does carry the eclass" - is met by the first branch below keeping
# those definitional exactly as before, never by this axis reporting them as
# divergence, which story 007 had already decided against.
compare_eclass_hashes() {
	local line entry baseline distance category pf pn key opv name
	local eclass overlay_hash gentoo_hash note
	local -A covered=() is_local=() inheritors=()
	local -a names=()
	local path stale=0 compared=0

	for path in "${OVERLAY_ROOT}"/eclass/*.eclass; do
		eclass=${path##*/}
		eclass=${eclass%.eclass}
		is_local["${eclass}"]=1
		inheritors["${eclass}"]=0
	done

	for entry in "${PARITY_MD5_COVERED[@]}"; do
		covered["${entry}"]=1
	done

	for line in "${PARITY_BASELINES[@]}"; do
		entry=${line%%$'\t'*}
		[[ -n ${covered[${entry}]+set} ]] || continue

		baseline=${line#*$'\t'}
		distance=${baseline#*$'\t'}
		baseline=${baseline%%$'\t'*}

		category=${entry%%/*}
		pf=${entry#*/}
		pn=${PARITY_EBUILD_PN[${entry}]}
		key="${category}/${pn}"
		opv=${pf#"${pn}-"}

		ECLASS_HASH=()
		eclasses_field "${OVERLAY_ROOT}/metadata/md5-cache/${category}/${pf}"
		read_eclass_hashes "${ECLASSES_FIELD}" overlay
		names=()
		read -r -a names <<<"${ECLASS_NAMES}"
		eclasses_field "${GENTOO_REPO}/metadata/md5-cache/${category}/${pn}-${baseline}"
		read_eclass_hashes "${ECLASSES_FIELD}" gentoo
		compared=$(( compared + 1 ))

		for name in "${names[@]}"; do
			if [[ -n ${is_local[${name}]+set} ]]; then
				inheritors["${name}"]=$(( inheritors["${name}"] + 1 ))
			fi

			gentoo_hash=${ECLASS_HASH[gentoo:${name}]-}
			[[ -n ${gentoo_hash} ]] || continue
			overlay_hash=${ECLASS_HASH[overlay:${name}]}
			[[ ${overlay_hash} != "${gentoo_hash}" ]] || continue

			# THE DISCRIMINATOR, sub-task 4.1, and it is asked of
			# is_local - which was built by listing eclass/ at the top
			# of this function, not from any name written here. A
			# fourth overlay-local eclass added later is covered
			# without an edit, and would be misfiled as a stale cache
			# by a check written against the three that exist today.
			if [[ -n ${is_local[${name}]+set} ]]; then
				# Story 007's R1.6. The overlay ships this eclass,
				# so every overlay ebuild that inherits it resolves
				# it from the overlay: the hash differs BY
				# CONSTRUCTION. That is the decision to ship a copy,
				# recorded as definitional below, not a finding.
				continue
			fi

			# Story 008's R2.1. The overlay does not ship this eclass,
			# so BOTH trees resolved it from the same ::gentoo file and
			# the two hashes cannot describe different content. They can
			# only have been recorded at different times - the overlay's
			# md5-cache entry was generated against an older ::gentoo
			# eclass and never regenerated.
			#
			# So this is the instrument reporting itself, not the tree
			# drifting. Left as a divergence row it is classified
			# UNDOCUMENTED, which asks a human to decide about a
			# measurement error the guard made.
			stale=$(( stale + 1 ))
			PARITY_STALE_CACHE+=( "${key}"$'\t'"${opv}"$'\t'"${name}"$'\t'"overlay md5-cache records ${overlay_hash:0:12}, ::gentoo's ${gentoo_hash:0:12}, for an eclass the overlay does not ship" )
		done
	done

	for eclass in "${!is_local[@]}"; do
		if [[ -f ${GENTOO_REPO}/eclass/${eclass}.eclass ]]; then
			note="overlay ships its own ${eclass}.eclass, which shadows ::gentoo's"
		else
			note="overlay ships ${eclass}.eclass and ::gentoo has none"
		fi
		note+="; inherited by ${inheritors[${eclass}]} in-scope ebuild(s)"
		PARITY_ECLASS_DEFINITIONAL+=( "${eclass}"$'\t'"${note}" )
	done

	printf '  [eclass]   %d overlay-local eclass(es) recorded as definitional, not as findings; %d of %d pair(s) carry a stale md5-cache entry\n' \
		"${#PARITY_ECLASS_DEFINITIONAL[@]}" "${stale}" "${compared}"
}

NORMALISED_PATCH=""

# normalise_patch <array element> <pn> <PV> <PVR>
# One PATCHES element as a comparable patch name, into NORMALISED_PATCH.
#
# WHAT IS NORMALISED, AND WHY EACH ONE HAS TO BE. Two ebuilds can name the same
# patch in different words, and every one of those differences would otherwise
# read as drift:
#
#   quotes        "${FILESDIR}/x.patch" and "${FILESDIR}"/x.patch are the same
#                 element written by two people
#   ${FILESDIR}   says WHERE the patch is, not WHICH patch it is, and both trees
#                 mean the same directory by it
#   ${PN}         expands to the same string on both sides - it is the same
#                 package - so ${PN}-x.patch and spectacle-x.patch are one name
#   ${P} ${PV}    expand to DIFFERENT strings on the two sides whenever the
#   ${PF} ${PVR}  versions differ, which is most pairs. Mapped to a placeholder
#                 rather than expanded, so that the same patch carried across a
#                 bump is one name and not two
#
# All four version variables collapse to the SAME placeholder. ${PF} and ${PVR}
# differ from ${P} and ${PV} only by the revision, which is a downstream counter
# rather than a different patch, and keeping them apart would make one ebuild's
# ${P}-x.patch differ from another's ${PF}-x.patch when both resolve to the same
# file.
#
# WHAT IS NOT NORMALISED, stated so the gaps are not rediscovered as bugs.
#
# A version SPELLED OUT in the element is left alone, and that is a measurement
# rather than an omission. Rewriting it looks obviously right - it would make
# libixion-0.20.0-boost-m4.patch match itself across a revision bump - and it is
# wrong: app-editors/vim-core carries the literal
# vim-core-9.1.1652-r1-unbundle-xxd.patch on BOTH sides, and ::gentoo happens to
# sit at 9.1.1652, so replacing each side's own version turns two references to
# one file into a divergence (measured 2026-08-06). A literal in a filename is
# part of the filename.
#
# ${MY_P}, ${WORKDIR}, ${S} and any ebuild-local variable - chromium's
# "${cr_patchset_dir}/common/" - are left exactly as written. They cannot be
# resolved without executing the ebuild, they are rare, and an element that
# differs only because one side used a private variable is a divergence worth
# looking at anyway.
normalise_patch() {
	local elem=$1 pn=$2

	elem=${elem//\"/}
	elem=${elem//\'/}

	# The patterns below are LITERAL variable names, not expansions: "\$" is
	# a dollar sign that this script must not expand and the ebuild has not
	# expanded either. Written with a backslash rather than in single
	# quotes because '${PN}' is exactly the shape SC2016 warns about, and
	# the bar here is a shellcheck run with no suppressions in it.
	elem=${elem//"\${FILESDIR}"/}
	elem=${elem//"\$FILESDIR"/}
	elem=${elem#/}

	elem=${elem//"\${PF}"/${pn}-<PV>}
	elem=${elem//"\${PVR}"/<PV>}
	elem=${elem//"\${PN}"/${pn}}
	elem=${elem//"\${PV}"/<PV>}
	elem=${elem//"\${P}"/${pn}-<PV>}

	# Unbraced, longest name first: $PN starts with $P, so replacing $P
	# first would turn $PN into <pn>-<PV>N.
	elem=${elem//"\$PF"/${pn}-<PV>}
	elem=${elem//"\$PVR"/<PV>}
	elem=${elem//"\$PN"/${pn}}
	elem=${elem//"\$PV"/<PV>}
	elem=${elem//"\$P"/${pn}-<PV>}

	NORMALISED_PATCH=${elem}
}

PATCH_SET=""

# patches_of <ebuild path> <pn>
# The ebuild's PATCHES array as a comparable set of names, into PATCH_SET.
#
# No version is passed: every version variable normalises to one placeholder, so
# what each side is actually at never enters the comparison.
#
# EVERY assignment in the file contributes, and their union is the answer. A
# conditional PATCHES+=( ... ) inside an if or behind a use flag therefore reads
# as "this patch is in the set", which over-approximates on purpose: the
# question this axis answers is which patches the ebuild can apply, and deciding
# which branch is taken would mean evaluating the ebuild.
#
# ONE LIMITATION, measured rather than assumed. The assignment has to be the
# first thing on its line, optionally after "local". chromium has one that is
# not - [[ ${#category_patches[@]} -gt 0 ]] && PATCHES+=( "${category}" ) - and
# it is the only such line in either tree's shared packages (2026-08-06). Its
# element is an ebuild-local variable, so it would be unresolvable even if it
# were read. Matching PATCHES+=( anywhere on a line instead would pick the
# string out of prose in a comment, which is the worse trade.
patches_of() {
	local file=$1 pn=$2
	local -a lines=() tokens=()
	local -A seen=()
	local line token inside=0
	local opener='^[[:space:]]*(local[[:space:]]+)?PATCHES\+?=\((.*)$'

	PATCH_SET=""

	mapfile -t lines <"${file}"

	for line in "${lines[@]}"; do
		if (( ! inside )); then
			[[ ${line} =~ ${opener} ]] || continue
			line=${BASH_REMATCH[2]}
			inside=1
		fi

		read -r -a tokens <<<"${line}"
		for token in "${tokens[@]}"; do
			# A word starting with # comments out the rest of the
			# line, which is how the arrays in chromium and the
			# kde-plasma ebuilds explain themselves.
			if [[ ${token} == '#'* ]]; then
				break
			fi

			if [[ ${token} == *')' ]]; then
				token=${token%)}
				inside=0
			fi

			if [[ -n ${token} ]]; then
				normalise_patch "${token}" "${pn}"
				if [[ -n ${NORMALISED_PATCH} && -z ${seen[${NORMALISED_PATCH}]+set} ]]; then
					seen["${NORMALISED_PATCH}"]=1
					PATCH_SET+="${NORMALISED_PATCH} "
				fi
			fi

			if (( ! inside )); then
				break
			fi
		done
	done

	PATCH_SET=${PATCH_SET% }
}

# Sub-task 4.5. The PATCHES axis.
#
# WHY IT IS HERE AND NOT IN STAGE 4. Every other ebuild-level axis is read from
# md5-cache, which does not record PATCHES at all - it is a plain bash array
# consumed by src_prepare, not metadata. So it is read from the ebuild TEXT, and
# reading ebuild text is this stage's business.
#
# WHY IT IS AN EBUILD-LEVEL AXIS AT ALL, given that files/ covers the same
# ground. The two answer different questions and only one of them can be
# answered. files/ says which patch FILES exist and whether their content
# matches; PATCHES says which of them the ebuild actually applies - and, because
# it lives in the ebuild, it is a divergence a # BENTOO-DIVERGENCE: comment can
# sit next to. kde-plasma/spectacle is exactly that case: the overlay applies
# ${PN}-opencv5.patch and ::gentoo applies nothing, and the ebuild already
# explains why in prose that no parser reads.
compare_patch_sets() {
	local line entry baseline distance category pf pn key opv
	local overlay_patches gentoo_patches gentoo_ebuild
	local before compared=0 diverged=0

	for line in "${PARITY_BASELINES[@]}"; do
		entry=${line%%$'\t'*}
		baseline=${line#*$'\t'}
		distance=${baseline#*$'\t'}
		baseline=${baseline%%$'\t'*}

		category=${entry%%/*}
		pf=${entry#*/}
		pn=${PARITY_EBUILD_PN[${entry}]}
		key="${category}/${pn}"
		opv=${pf#"${pn}-"}

		resolve_overlay_ebuild "${entry}" "${pn}"
		gentoo_ebuild="${GENTOO_REPO}/${key}/${pn}-${baseline}.ebuild"
		if [[ ! -f ${OVERLAY_EBUILD} || ! -f ${gentoo_ebuild} ]]; then
			continue
		fi

		patches_of "${OVERLAY_EBUILD}" "${pn}"
		overlay_patches=${PATCH_SET}
		patches_of "${gentoo_ebuild}" "${pn}"
		gentoo_patches=${PATCH_SET}
		compared=$(( compared + 1 ))

		ROW_PKG=${key}
		ROW_OPV=${opv}
		ROW_BPV=${baseline}
		ROW_DISTANCE=${distance}

		before=${#PARITY_ROWS[@]}
		compare_as_sets PATCHES "${overlay_patches}" "${gentoo_patches}"
		if (( ${#PARITY_ROWS[@]} > before )); then
			diverged=$(( diverged + 1 ))
		fi
	done

	printf '  [patches]  %d of %d ebuild pair(s) compared differ on PATCHES\n' \
		"${diverged}" "${compared}"
}

# Stage 5. Compare what md5-cache does not carry: metadata.xml, whatever is
# under files/, the eclasses the recorded hashes refer to, and the PATCHES array
# read from the ebuild text.
# Publishes: PARITY_ROWS (appends; column 8 left to stage 6),
# PARITY_ECLASS_DEFINITIONAL.
compare_auxiliary_files() {
	local axis axes=""

	compare_metadata_xml
	compare_files_dirs
	compare_eclass_hashes
	compare_patch_sets

	# R4.4, said here as well as in the report. A sweep that printed four
	# counts and left the reader to work out that two of those axes can
	# never be justified would be leaving the most misreadable part of its
	# own output unexplained.
	for axis in "${PARITY_UNJUSTIFIABLE_AXES[@]}"; do
		axes+="${axis}, "
	done
	printf '  [aux]      %s%s\n' "${axes%, }" ':'
	printf '  [aux]      %s\n' "${PARITY_UNJUSTIFIABLE_NOTE}"
}

# The axes whose row carries each side's WHOLE value rather than its surplus.
# Everything else is set-valued, where (none) on a side means "this side adds
# nothing" - which is what the UNDOCUMENTED rule below reads.
PARITY_SINGLE_VALUED_AXES=(
	'EAPI'
	'SLOT'
	'HOMEPAGE'
	'REQUIRED_USE'
)

# axis_in <axis> <axis name>...
# Membership test shared by the two axis lists, so a new axis is added in one
# place rather than in two loops that must not drift apart. The list arrives
# expanded rather than by name: an indirect expansion would leave shellcheck
# unable to see either array being read, and the bar here is a clean run with no
# suppressions in it.
axis_in() {
	local axis=$1 known
	shift

	for known in "$@"; do
		if [[ ${axis} == "${known}" ]]; then
			return 0
		fi
	done
	return 1
}

# Which (ebuild, axis) pairs carry a # BENTOO-DIVERGENCE: tag naming that axis.
# Keyed "<category>/<pf>|<axis>".
declare -A PARITY_TAGGED_AXES=()

# collect_tags <category/pf> <pn>
# Read one overlay ebuild's tags into PARITY_TAGGED_AXES.
#
# THE MATCHER IS DELIBERATELY TIGHT. R3.3 justifies an axis only when a tag
# NAMES it, and 5.2's risk is the opposite: a matcher loose enough to read any
# comment as a justification hides exactly the drift this script exists to find.
# So the axis token is captured immediately after the colon and must equal the
# divergent axis; the reason after it is free text and is not parsed.
#
# The separator between the axis and the reason is NOT matched at all. design.md
# writes the tag with an em-dash and the self-test writes it with a plain
# hyphen; a matcher that enumerated separators would be one punctuation mark
# away from silently failing to justify a correctly-tagged divergence.
collect_tags() {
	local entry=$1 pn=$2
	local line axis pkg_key

	resolve_overlay_ebuild "${entry}" "${pn}"
	if [[ ! -f ${OVERLAY_EBUILD} ]]; then
		return 0
	fi

	# The package-level key, alongside the per-ebuild one. metadata.xml and
	# files/content are compared for the PACKAGE, so their rows carry the
	# literal "(package)" where a PV would go and assign_verdicts looks them up
	# under "<category>/<pn>-(package)|<axis>". Registering only the per-ebuild
	# key left those two axes unreachable by any tag - see the note beside
	# PARITY_UNJUSTIFIABLE_AXES for why that was wrong.
	pkg_key="${entry%%/*}/${pn}-(package)"

	while IFS= read -r line; do
		if [[ ${line} =~ ^[[:space:]]*#[[:space:]]*BENTOO-DIVERGENCE:[[:space:]]*([^[:space:]]+) ]]; then
			axis=${BASH_REMATCH[1]}
			PARITY_TAGGED_AXES["${entry}|${axis}"]=1
			PARITY_TAGGED_AXES["${pkg_key}|${axis}"]=1
		fi
	done <"${OVERLAY_EBUILD}"
}

# Stage 6. Turn the raw differences into a verdict per package.
# Publishes: PARITY_IDENTICAL, and column 8 of every PARITY_ROWS entry. Reads
# PARITY_TAG_SOURCE before the tracked ebuild when looking for a tag.
#
# THE FOUR VERDICTS AND THE EVIDENCE EACH ONE NEEDS.
#
# R3.2 makes ALIGN the default and R3.5 forbids inferring intent, so every row
# starts at ALIGN and is promoted only by something the script can point at:
#
#   REDUNDANT     the whole ebuild is byte-identical to its exact baseline
#   JUSTIFIED     a tag in the overlay ebuild names THIS axis
#   UNDOCUMENTED  the overlay carries something on this axis that ::gentoo does
#                 not, and no tag explains it
#   ALIGN         everything else
#
# THE UNDOCUMENTED RULE, STATED MECHANICALLY, because R3.5 forbids the other
# kind. A set-valued row carries each side's SURPLUS. An overlay surplus of
# (none) means the overlay adds nothing and is merely BEHIND - residue, which is
# ALIGN. An overlay surplus that is NOT (none) means somebody wrote that into
# the overlay ebuild: the divergence is an addition rather than a residue, and
# an addition with no tag is precisely what a human has to decide about.
#
# It is a criterion a reader can check, not a guess about why. It reproduces all
# four hand-inspected calibration cases in design.md:
#
#   kwin PYTHON_COMPAT        overlay surplus (none)     -> ALIGN
#   kdeplasma-addons INHERIT  overlay surplus (none)     -> ALIGN
#   plasma-desktop qtbase[X]  overlay surplus present    -> UNDOCUMENTED
#   spectacle PATCHES         overlay surplus present    -> UNDOCUMENTED untagged,
#                                                           JUSTIFIED once tagged
#
# Single-valued axes are EXCLUDED from the rule rather than fitted to it. Both
# sides always carry a value there, so "the overlay carries something ::gentoo
# does not" is true of every single one of them and separates nothing. They stay
# ALIGN - the honest default - instead of being promoted by a test that does not
# discriminate.
#
# Byte-identity is read from the TRACKED ebuild, never through
# resolve_overlay_ebuild. The self-test's scratch copy has a tag appended, so
# resolving through it would make a byte-identical ebuild look modified and
# quietly move the count off 67.
assign_verdicts() {
	local line entry baseline distance category pn pf
	local row pkg opv bpv axis overlay gentoo verdict key
	local overlay_ebuild gentoo_ebuild
	local -A identical=()
	local -A counts=( [ALIGN]=0 [JUSTIFIED]=0 [UNDOCUMENTED]=0 [REDUNDANT]=0 )
	local -a kept=()

	# --- 5.1 byte-identity, and the tags, one pass over the pairs ------

	for line in "${PARITY_BASELINES[@]}"; do
		entry=${line%%$'\t'*}
		baseline=${line#*$'\t'}
		distance=${baseline#*$'\t'}
		baseline=${baseline%%$'\t'*}

		category=${entry%%/*}
		pf=${entry#*/}
		pn=${PARITY_EBUILD_PN[${entry}]}

		collect_tags "${entry}" "${pn}"

		if [[ ${distance} != exact ]]; then
			continue
		fi

		overlay_ebuild="${OVERLAY_ROOT}/${category}/${pn}/${pf}.ebuild"
		gentoo_ebuild="${GENTOO_REPO}/${category}/${pn}/${pn}-${baseline}.ebuild"

		if [[ -f ${overlay_ebuild} && -f ${gentoo_ebuild} ]] &&
			cmp -s -- "${overlay_ebuild}" "${gentoo_ebuild}"; then
			PARITY_IDENTICAL+=( "${entry}" )
			identical["${entry}"]=1
		fi
	done

	# --- 5.3 verdict per surviving row, 5.1 suppression on the rest ----

	for row in "${PARITY_ROWS[@]}"; do
		IFS=$'\t' read -r pkg opv bpv distance axis overlay gentoo _ <<<"${row}"

		# R3.4: one REDUNDANT row for the ebuild replaces every
		# per-axis row it would otherwise emit. 67 ebuilds each
		# reporting zero-difference axes would bury the real findings.
		key="${pkg}-${opv}"
		if [[ -n ${identical[${key}]-} ]]; then
			continue
		fi

		verdict=ALIGN

		if [[ -n ${PARITY_TAGGED_AXES["${key}|${axis}"]-} ]]; then
			verdict=JUSTIFIED
		elif ! axis_in "${axis}" "${PARITY_UNJUSTIFIABLE_AXES[@]}" &&
			! axis_in "${axis}" "${PARITY_SINGLE_VALUED_AXES[@]}" &&
			[[ ${overlay} != '(none)' ]]; then
			verdict=UNDOCUMENTED
		fi

		counts["${verdict}"]=$(( counts["${verdict}"] + 1 ))
		kept+=( "${pkg}"$'\t'"${opv}"$'\t'"${bpv}"$'\t'"${distance}"$'\t'"${axis}"$'\t'"${overlay}"$'\t'"${gentoo}"$'\t'"${verdict}" )
	done

	# --- 5.1 the REDUNDANT rows themselves -----------------------------

	for entry in "${PARITY_IDENTICAL[@]}"; do
		category=${entry%%/*}
		pf=${entry#*/}
		pn=${PARITY_EBUILD_PN[${entry}]}
		opv=${pf#"${pn}-"}

		counts[REDUNDANT]=$(( counts[REDUNDANT] + 1 ))
		kept+=( "${category}/${pn}"$'\t'"${opv}"$'\t'"${opv}"$'\t'"exact"$'\t'"(ebuild)"$'\t'"${pf}.ebuild"$'\t'"${pf}.ebuild"$'\t'"REDUNDANT" )
	done

	PARITY_ROWS=( "${kept[@]}" )

	printf '  [verdicts] %d row(s): %d ALIGN, %d JUSTIFIED, %d UNDOCUMENTED, %d REDUNDANT\n' \
		"${#PARITY_ROWS[@]}" "${counts[ALIGN]}" "${counts[JUSTIFIED]}" \
		"${counts[UNDOCUMENTED]}" "${counts[REDUNDANT]}"
}

# gentoo_sync_stamp
# When the ::gentoo tree being compared against was last synced, into
# GENTOO_SYNC_STAMP. R5 wants the snapshot dated: ::gentoo moves daily, so a
# report that does not say WHICH ::gentoo it read is a report nobody can
# reproduce or argue with six weeks later.
GENTOO_SYNC_STAMP=""
gentoo_sync_stamp() {
	local stamp="${GENTOO_REPO}/metadata/timestamp.chk"

	GENTOO_SYNC_STAMP='(unknown - no metadata/timestamp.chk)'
	if [[ -f ${stamp} ]]; then
		IFS= read -r GENTOO_SYNC_STAMP <"${stamp}" || true
	fi
}

# Sub-task 6.1. One row per divergence, processable without parsing prose.
# Columns as declared at the top of the file, tab separated, following story
# 006's sweep-data.tsv convention.
write_parity_data() {
	local row

	{
		printf 'package\toverlay_pv\tbaseline_pv\tdistance\taxis\toverlay_value\tgentoo_value\tverdict\n'
		if (( ${#PARITY_ROWS[@]} )); then
			printf '%s\n' "${PARITY_ROWS[@]}"
		fi
	} >"${PARITY_DATA}"
}

# Sub-task 6.2. The readable report: grouped by verdict, broken down per
# category, and dated.
#
# WHY EVERY PERCENTAGE IS ACCOMPANIED BY ITS PER-CATEGORY BREAKDOWN (R5.4).
# kde-plasma is 72 of the 232 shared packages and media-plugins is 76 - 64%
# between them. A single "N% of packages diverge" is therefore a statement about
# those two categories wearing the whole overlay's name, and a reader who acted
# on it would be acting on the wrong thing.
write_parity_report() {
	local row pkg opv bpv distance axis overlay gentoo verdict category
	local -A cat_packages=() cat_diverging=() axis_rows=() verdict_rows=()
	local -A cat_verdict=() package_diverges=()
	local -a categories=() axes=()
	local key name diverging=0 clean=0

	for pkg in "${PARITY_SHARED_PACKAGES[@]}"; do
		category=${pkg%%/*}
		cat_packages["${category}"]=$(( ${cat_packages["${category}"]-0} + 1 ))
	done

	for row in "${PARITY_ROWS[@]}"; do
		IFS=$'\t' read -r pkg opv bpv distance axis overlay gentoo verdict <<<"${row}"
		category=${pkg%%/*}

		verdict_rows["${verdict}"]=$(( ${verdict_rows["${verdict}"]-0} + 1 ))
		axis_rows["${axis}"]=$(( ${axis_rows["${axis}"]-0} + 1 ))
		cat_verdict["${category}|${verdict}"]=$(( ${cat_verdict["${category}|${verdict}"]-0} + 1 ))

		if [[ -z ${package_diverges[${pkg}]-} ]]; then
			package_diverges["${pkg}"]=1
			cat_diverging["${category}"]=$(( ${cat_diverging["${category}"]-0} + 1 ))
		fi
	done

	diverging=${#package_diverges[@]}
	clean=$(( ${#PARITY_SHARED_PACKAGES[@]} - diverging ))

	# GUARDED BECAUSE AN EMPTY ASSOCIATIVE ARRAY IS NOT AN EMPTY LIST. printf
	# over "${!map[@]}" with no keys still emits one blank line, so mapfile
	# hands back a ONE-element array holding "", and the loops below then
	# index ${map[""]} - a bad array subscript, fatal under set -e.
	#
	# axis_rows is empty exactly when the scope holds no divergence, which is
	# the state this guard exists to reward: the run died writing the very
	# report that says the work is done (A12 pins it). cat_packages cannot be
	# empty today - an empty shared set stops the sweep at exit 2 long before
	# here - but the defect is the idiom, not the array, so both sites are
	# guarded rather than only the reachable one.
	if (( ${#cat_packages[@]} )); then
		mapfile -t categories < <(printf '%s\n' "${!cat_packages[@]}" | sort)
	fi
	if (( ${#axis_rows[@]} )); then
		mapfile -t axes < <(printf '%s\n' "${!axis_rows[@]}" | sort)
	fi

	{
		printf '# Gentoo parity report\n\n'
		printf "Structural comparison of this overlay against \`::gentoo\`.\n"
		printf 'It reports where the two differ; it changes nothing.\n\n'

		printf '| | |\n|---|---|\n'
		printf "| overlay | \`%s\` |\n" "${OVERLAY_ROOT}"
		printf "| \`::gentoo\` | \`%s\` |\n" "${GENTOO_REPO}"
		printf "| \`::gentoo\` synced | %s |\n" "${GENTOO_SYNC_STAMP}"
		printf '| filter | %s |\n\n' "${FILTER:-(none - full sweep)}"

		printf '## Scope\n\n'
		printf -- "- **%d shared packages** examined - every overlay package \`::gentoo\` also carries.\n" \
			"${#PARITY_SHARED_PACKAGES[@]}"
		printf -- '- **%d overlay-only packages** excluded: there is no baseline to compare them against.\n' \
			"${#PARITY_EXCLUDED[@]}"
		printf -- '- **%d ebuilds** in scope, **%d** with an md5-cache entry on both sides.\n' \
			"${#PARITY_SCOPE_EBUILDS[@]}" "${#PARITY_MD5_COVERED[@]}"
		printf -- "- **%d packages behind \`::gentoo\`** once live ebuilds leave the version sort.\n\n" \
			"${#PARITY_BEHIND[@]}"

		printf '## Result\n\n'
		printf -- '- **%d of %d packages diverge** on at least one axis.\n' \
			"${diverging}" "${#PARITY_SHARED_PACKAGES[@]}"
		printf -- '- **%d packages show no divergence** on any axis compared.\n' "${clean}"
		printf -- '- **%d divergence rows** in total.\n\n' "${#PARITY_ROWS[@]}"

		printf 'That headline figure is dominated by two categories and is broken\n'
		printf 'down per category below rather than reported alone.\n\n'

		printf '### By verdict\n\n'
		printf '| Verdict | Rows | Meaning |\n|---|---:|---|\n'
		printf "| \`ALIGN\` | %d | Converge to \`::gentoo\` - divergence with no declared reason |\n" \
			"${verdict_rows[ALIGN]-0}"
		printf "| \`JUSTIFIED\` | %d | Keep - a \`# BENTOO-DIVERGENCE:\` tag names this axis |\n" \
			"${verdict_rows[JUSTIFIED]-0}"
		printf "| \`UNDOCUMENTED\` | %d | Maintainer decides - the overlay adds something, with no tag |\n" \
			"${verdict_rows[UNDOCUMENTED]-0}"
		printf "| \`REDUNDANT\` | %d | The overlay shadows \`::gentoo\` byte-for-byte, for nothing |\n\n" \
			"${verdict_rows[REDUNDANT]-0}"

		printf '### By category\n\n'
		printf "| Category | Packages | Diverging | \`ALIGN\` | \`JUSTIFIED\` | \`UNDOCUMENTED\` | \`REDUNDANT\` |\n"
		printf '|---|---:|---:|---:|---:|---:|---:|\n'
		for name in "${categories[@]}"; do
			printf '| %s | %d | %d | %d | %d | %d | %d |\n' \
				"${name}" \
				"${cat_packages[${name}]}" \
				"${cat_diverging[${name}]-0}" \
				"${cat_verdict[${name}|ALIGN]-0}" \
				"${cat_verdict[${name}|JUSTIFIED]-0}" \
				"${cat_verdict[${name}|UNDOCUMENTED]-0}" \
				"${cat_verdict[${name}|REDUNDANT]-0}"
		done
		printf '\n'

		printf '### By axis\n\n'
		for name in "${axes[@]}"; do
			printf "#### \`%s\` - %d row(s)\n\n" "${name}" "${axis_rows[${name}]}"
			# R4.4, printed HERE rather than in a footnote: the reader
			# this is for is the one who skims to this section and
			# stops. A footnote is read by whoever already knew.
			if axis_in "${name}" "${PARITY_UNJUSTIFIABLE_AXES[@]}"; then
				printf '> **%s**\n\n' "${PARITY_UNJUSTIFIABLE_NOTE}"
			fi
		done

		printf '## Definitionally divergent eclasses\n\n'
		printf "These are overlay-local: \`::gentoo\` has no counterpart to compare\n"
		printf 'against, so they are recorded rather than reported as findings (R1.6).\n\n'
		if (( ${#PARITY_ECLASS_DEFINITIONAL[@]} )); then
			# An entry is <eclass> TAB <why it is not a finding>, so it needs
			# splitting before it is rendered: printing the whole tuple through
			# one %s put the tab INSIDE the code span, and the reason came out
			# looking like part of the eclass name.
			for name in "${PARITY_ECLASS_DEFINITIONAL[@]}"; do
				printf -- "- \`%s\` - %s\n" "${name%%$'\t'*}" "${name#*$'\t'}"
			done
		else
			printf -- '- none\n'
		fi
		printf '\n'

		# R1.5. The rows this run decided NOT to show, and why it decided
		# that. Without this the reader cannot tell a working suppression
		# from a comparison that silently stopped comparing - and ten of
		# this axis's sixteen rows now go through it.
		printf "## Suppressed \`SLOT\` rows\n\n"
		printf 'The two sides differ here only because they sit at different\n'
		printf -- 'versions and the package encodes its version in the slot. Listed\n'
		printf -- 'rather than dropped: a suppression nobody can audit is\n'
		printf -- 'indistinguishable from a comparison that broke (story 008, R1.5).\n\n'
		if (( ${#PARITY_SLOT_SUPPRESSED[@]} )); then
			printf "| Package | overlay | \`::gentoo\` | Why it was suppressed |\n"
			printf '|---|---|---|---|\n'
			for name in "${PARITY_SLOT_SUPPRESSED[@]}"; do
				IFS=$'\t' read -r key overlay gentoo verdict <<<"${name}"
				printf -- "| \`%s\` | \`%s\` | \`%s\` | %s |\n" \
					"${key}" "${overlay}" "${gentoo}" "${verdict}"
			done
		else
			printf -- '- none\n'
		fi
		printf '\n'

		printf "## Suppressed \`metadata.xml\` rows\n\n"
		printf -- 'Two of the three things this file holds cannot align. The\n'
		printf -- 'MAINTAINER is definitional -- this overlay maintains its fork and\n'
		printf -- '`::gentoo` maintains theirs, so that row would be true forever and\n'
		printf -- 'clearing it would mean handing the package back. A USE FLAG\n'
		printf -- 'DESCRIPTION shadows the `IUSE` axis, which already has a mechanism:\n'
		printf -- 'QA REQUIRES a description for every local flag, so adding a flag\n'
		printf -- 'necessarily edits this file, and reporting both counted one decision\n'
		printf -- 'twice. Checked against the OWN `IUSE` of each side, so a\n'
		printf -- 'description for a flag that side does not have is NOT suppressed -\n'
		printf -- 'that is a stale description, and it survives here as it does in\n'
		printf -- 'pkgcheck.\n\n'
		if (( ${#PARITY_METADATA_SUPPRESSED[@]} )); then
			printf "| Package | Why it was suppressed |\n"
			printf '|---|---|\n'
			for name in "${PARITY_METADATA_SUPPRESSED[@]}"; do
				IFS=$'\t' read -r key verdict <<<"${name}"
				printf -- "| \`%s\` | %s |\n" "${key}" "${verdict}"
			done
		else
			printf -- '- none\n'
		fi
		printf '\n'

		# Same obligation as the SLOT block above, for a suppression that
		# removes far more: 68 of the 338 rows this report used to carry.
		# A drop that large is exactly the one a reader must be able to
		# audit line by line, or the guard has quietly stopped measuring
		# two of its axes and looks like it got better.
		printf "## Suppressed \`files/\` rows\n\n"
		printf -- 'A `files/` difference is not an independent divergence. An\n'
		printf -- 'overlay-only file is there BECAUSE a `PATCHES` or `newinitd` line\n'
		printf -- 'names it, and that line already sits on an axis with a\n'
		printf -- '`# BENTOO-DIVERGENCE:` mechanism; a `::gentoo`-only file is their\n'
		printf -- 'patch set for their versions, which nothing here can act on.\n'
		printf -- 'Measured on 2026-09-06 before suppressing anything: 62 of 66\n'
		printf -- 'overlay-only names and 123 of 132 `::gentoo`-only names were\n'
		printf -- 'reachable from an ebuild. What survives suppression is the\n'
		printf -- '`files/unreferenced` axis above - an overlay file NO ebuild names,\n'
		printf -- 'which nothing measured before this.\n\n'
		if (( ${#PARITY_FILES_SUPPRESSED[@]} )); then
			printf "| Package | Axis | Names | Why it was suppressed |\n"
			printf '|---|---|---|---|\n'
			for name in "${PARITY_FILES_SUPPRESSED[@]}"; do
				IFS=$'\t' read -r key overlay gentoo verdict <<<"${name}"
				printf -- "| \`%s\` | \`%s\` | %s | %s |\n" \
					"${key}" "${overlay}" "${gentoo}" "${verdict}"
			done
		else
			printf -- '- none\n'
		fi
		printf '\n'

		# R2.2 and R2.3. Its own section, outside the four verdicts and
		# outside the row count above: this is the guard reporting a fault
		# in its own measurement, not a divergence for a human to judge.
		printf "## Stale \`md5-cache\` entries\n\n"
		printf "An \`_eclasses_\` hash differs for an eclass the overlay does not\n"
		printf -- 'ship. Both trees resolved the same file, so the two hashes cannot\n'
		printf -- 'describe different content - only different moments. The overlay\n'
		printf -- 'cache is out of date; the tree is not divergent (story 008, R2).\n\n'
		printf -- 'These are **not** counted among the divergence rows above and do\n'
		printf -- 'not affect the exit code.\n\n'
		if (( ${#PARITY_STALE_CACHE[@]} )); then
			printf "| Package | \`PV\` | Eclass | Observation |\n"
			printf '|---|---|---|---|\n'
			for name in "${PARITY_STALE_CACHE[@]}"; do
				IFS=$'\t' read -r key overlay gentoo verdict <<<"${name}"
				printf -- "| \`%s\` | \`%s\` | \`%s\` | %s |\n" \
					"${key}" "${overlay}" "${gentoo}" "${verdict}"
			done
			printf '\n'
			printf -- "Remediation: \`egencache --update --repo bentoo\`\n\n"
		else
			printf -- '- none\n\n'
		fi

		# Integrity, not divergence: both sections below describe the
		# overlay on its own terms rather than against ::gentoo.
		printf "## Distfiles with no digest\n\n"
		printf -- 'A file named in `SRC_URI` with no `DIST` line in the package\n'
		printf -- '`Manifest`. Portage stops at "Insufficient data for checksum\n'
		printf -- 'verification", so the ebuild cannot be merged at all -- and if\n'
		printf -- '`::gentoo` ships the same version, the overlay shadows a working\n'
		printf -- 'copy with a broken one.\n\n'
		printf -- 'Unlike everything above, this axis does **not** compare the two\n'
		printf -- 'trees, so overlay-only packages are in scope too. It **does** fail\n'
		printf -- 'the run.\n\n'
		if (( ${#PARITY_MISSING_DIGEST[@]} )); then
			printf "| Package | \`PV\` | Distfile | Observation |\n"
			printf '|---|---|---|---|\n'
			for name in "${PARITY_MISSING_DIGEST[@]}"; do
				IFS=$'\t' read -r key overlay gentoo verdict <<<"${name}"
				printf -- "| \`%s\` | \`%s\` | \`%s\` | %s |\n" \
					"${key}" "${overlay}" "${gentoo}" "${verdict}"
			done
			printf '\n'
			printf -- "Remediation: \`pkgdev manifest <category/package>\` -- always with an\n"
			printf -- 'explicit target.\n\n'
		else
			printf -- '- none\n\n'
		fi

		printf "## \`\${FILESDIR}\` references matching no file\n\n"
		printf -- 'A path an ebuild reads through `${FILESDIR}` that no file under\n'
		printf -- 'the package `files/` matches. Under EAPI 8 the install helpers die\n'
		printf -- 'on it, so the package cannot install. A path the ebuild first\n'
		printf -- 'tests with `-d`/`-e`/`-f`/`-s` is optional and is not listed.\n\n'
		if (( ${#PARITY_MISSING_FILES[@]} )); then
			printf "| Package | Ebuilds | Pattern |\n"
			printf '|---|---|---|\n'
			for name in "${PARITY_MISSING_FILES[@]}"; do
				IFS=$'\t' read -r key overlay gentoo <<<"${name}"
				printf -- "| \`%s\` | \`%s\` | \`%s\` |\n" \
					"${key}" "${overlay}" "${gentoo}"
			done
			printf '\n'
		else
			printf -- '- none\n\n'
		fi

		printf "## Files no ebuild names\n\n"
		printf -- 'A file under a package `files/` directory that no ebuild of\n'
		printf -- 'that package reaches through `${FILESDIR}`. Usually a patch\n'
		printf -- 'left behind by a bump: the ebuild that applied it is gone and\n'
		printf -- 'the file stayed.\n\n'
		printf -- 'Overlay-wide, like the digest check above -- an orphan is litter\n'
		printf -- 'in this tree, not a difference from `::gentoo`, so restricting it\n'
		printf -- 'to shared packages would have skipped the ones nobody reviews. It\n'
		printf -- 'does **not** fail the run: it misleads a reader and breaks\n'
		printf -- 'nothing, the same call the stale-tag section makes.\n\n'
		if (( ${#PARITY_ORPHAN_FILES[@]} )); then
			printf "| Package | Count | Names |\n"
			printf '|---|---|---|\n'
			for name in "${PARITY_ORPHAN_FILES[@]}"; do
				IFS=$'\t' read -r key overlay gentoo <<<"${name}"
				printf -- "| \`%s\` | %s | \`%s\` |\n" \
					"${key}" "${overlay}" "${gentoo}"
			done
			printf '\n'
			printf -- 'Remediation: delete them, or restore the ebuild that used\n'
			printf -- 'them. Check `git log` before deleting -- a file can be\n'
			printf -- 'orphaned by a bump that is about to be reverted.\n\n'
		else
			printf -- '- none\n\n'
		fi

		printf "## Divergence tags whose reason evaporated\n\n"
		printf -- 'A `# BENTOO-DIVERGENCE:` tag naming an axis on which the two\n'
		printf -- 'trees no longer differ. `::gentoo` caught up; the tag now\n'
		printf -- 'documents a difference that is not there.\n\n'
		printf -- 'This overlay sends nothing upstream, so a divergence never drains\n'
		printf -- 'on its own -- noticing that it became unnecessary is the only way\n'
		printf -- 'the maintenance debt ever shrinks. These rows do **not** fail the\n'
		printf -- 'run.\n\n'
		if (( ${#PARITY_STALE_TAGS[@]} )); then
			printf "| Ebuild | Axis | Observation |\n"
			printf '|---|---|---|\n'
			for name in "${PARITY_STALE_TAGS[@]}"; do
				IFS=$'\t' read -r key overlay gentoo <<<"${name}"
				printf -- "| \`%s\` | \`%s\` | %s |\n" \
					"${key}" "${overlay}" "${gentoo}"
			done
			printf '\n'
		else
			printf -- '- none\n\n'
		fi

		printf '## What this report does not cover\n\n'
		printf -- "- \`SRC_URI\` and \`DESCRIPTION\` are excluded by design: the first differs\n"
		printf '  by construction whenever the version differs, the second is cosmetic.\n'
		printf -- "- Dependency version bounds are compared only at \`exact\` distance. A newer\n"
		printf '  overlay version legitimately raises a minimum.\n'
		printf -- "- The %d overlay-only packages have no \`::gentoo\` baseline and are out of\n" \
			"${#PARITY_EXCLUDED[@]}"
		printf '  scope; auditing them against the devmanual is separate work.\n'
	} >"${PARITY_REPORT}"
}

### the two integrity checks the 2026-09-04 audit added #################

# src_uri_distfiles <SRC_URI value>
# The distfile NAMES a SRC_URI resolves to, one per line.
#
# This is deliberately a name extractor and not a SRC_URI parser. It walks the
# token stream and keeps only what portage would end up fetching into DISTDIR:
#
#   "a? ( ... )"  the conditional wrapper and its parens are structure, not
#                 files. Every branch is kept, because a Manifest must cover
#                 the distfiles of EVERY USE combination, not of this one.
#   "|| ( ... )"  same; any arm may be the one used.
#   "URL -> name" the arrow renames, so the DIST line carries `name`, not the
#                 basename of the URL. Missing this is how a rename-heavy
#                 package would report a false positive on every fetch.
#   "URL"         plain: the basename after the last slash.
#
# A token with no slash and no arrow is not a URL - it is a leftover operator
# from some construct not enumerated above - and is skipped rather than guessed
# at. Guessing here would invent a distfile name and report a missing digest for
# a file that was never meant to exist.
src_uri_distfiles() {
	local src_uri=$1
	local -a tokens
	local i tok

	read -r -a tokens <<<"${src_uri}"

	for (( i = 0; i < ${#tokens[@]}; i++ )); do
		tok=${tokens[i]}

		case ${tok} in
			'('|')'|'||') continue ;;
			*'?')         continue ;;
		esac

		# "URL -> name": consume both and emit the rename target.
		if [[ ${tokens[i+1]-} == '->' && -n ${tokens[i+2]-} ]]; then
			printf '%s\n' "${tokens[i+2]}"
			i=$(( i + 2 ))
			continue
		fi

		[[ ${tok} == *'/'* ]] || continue
		printf '%s\n' "${tok##*/}"
	done
}

# Every overlay package with a Manifest, filtered the way the sweep is.
#
# Not PARITY_SCOPE_EBUILDS: that array holds only packages ::gentoo also ships,
# and a missing digest is broken independently of ::gentoo. See the note on
# PARITY_MISSING_DIGEST.
check_manifest_digests() {
	local cache_entry pkg category pn pf pv src_uri manifest distfile

	for cache_entry in "${OVERLAY_ROOT}"/metadata/md5-cache/*/*; do
		[[ -f ${cache_entry} ]] || continue

		pf=${cache_entry##*/}
		category=${cache_entry%/*}
		category=${category##*/}

		# The filter is a category or a category/package; match the same
		# way the sweep does so a targeted run stays targeted.
		if [[ -n ${FILTER} ]]; then
			case ${FILTER} in
				*/*) [[ ${category}/${pf} == "${FILTER}"-* ]] || continue ;;
				*)   [[ ${category} == "${FILTER}" ]] || continue ;;
			esac
		fi

		src_uri=$(sed -n 's/^SRC_URI=//p' "${cache_entry}")
		[[ -n ${src_uri} ]] || continue

		# md5-cache is keyed by PF and carries no PN, so the package
		# directory is found by asking which one holds this ebuild.
		pn=""
		for pkg in "${OVERLAY_ROOT}/${category}"/*/; do
			if [[ -f ${pkg}${pf}.ebuild ]]; then
				pn=$(basename -- "${pkg}")
				break
			fi
		done
		# No ebuild: a stale cache entry, which is a different problem
		# and is not this check's to report.
		[[ -n ${pn} ]] || continue

		pv=${pf#"${pn}-"}
		manifest="${OVERLAY_ROOT}/${category}/${pn}/Manifest"

		while IFS= read -r distfile; do
			[[ -n ${distfile} ]] || continue
			if [[ ! -f ${manifest} ]] ||
				! grep -qF "DIST ${distfile} " "${manifest}"; then
				PARITY_MISSING_DIGEST+=(
					"${category}/${pn}"$'\t'"${pv}"$'\t'"${distfile}"$'\t'"named in SRC_URI, no DIST line in Manifest - the ebuild cannot be fetched"
				)
			fi
		# sort -u: two mirrors of one file resolve to the same name, and
		# two identical rows describe one problem twice.
		done < <(src_uri_distfiles "${src_uri}" | sort -u)
	done

	printf '  [digest]   %d distfile(s) named in SRC_URI with no DIST line in a Manifest\n' \
		"${#PARITY_MISSING_DIGEST[@]}"
}

# Every ${FILESDIR} reference that matches no file -- the ORPHAN CHECK RUN
# BACKWARDS, and the more dangerous of the two directions.
#
# An orphan is litter: it misleads a reader and breaks nothing. A reference with
# no file behind it is FATAL -- under EAPI 8 the install helpers die, so the
# package cannot install at all.
#
# WHY IT EXISTS. dev-util/antigravity-hub-bin carried exactly this: newicon read
# "${FILESDIR}/${PN}.png", PN is antigravity-hub-bin, and the file is named
# antigravity-hub.png. The package had never installed once. It was found ONLY
# because the unreferenced png surfaced in the orphan list -- from the other
# direction, by luck, and only because the mismatch happened to leave litter
# behind. Rename both halves consistently and nothing would have shown at all.
#
# Reuses filesdir_refs, so brace expansion and PN/PV/PF substitution are the
# same code the suppression side uses. FILESDIR_REFS_ECLASS is deliberately NOT
# consulted: those patterns are read by an eclass, and a package inheriting
# readme.gentoo-r1 without shipping a README.gentoo is not broken.
check_missing_filesdir_refs() {
	local pkg_dir key category pn pattern eb_names g is_guarded
	local -a patterns=() ebuilds=() guarded=()

	for pkg_dir in "${OVERLAY_ROOT}"/*/*/; do
		pkg_dir=${pkg_dir%/}
		pn=${pkg_dir##*/}
		category=${pkg_dir%/*}
		category=${category##*/}
		key="${category}/${pn}"

		if [[ -n ${FILTER} ]]; then
			case ${FILTER} in
				*/*) [[ ${key} == "${FILTER}" ]] || continue ;;
				*)   [[ ${category} == "${FILTER}" ]] || continue ;;
			esac
		fi

		ebuilds=( "${pkg_dir}"/*.ebuild )
		(( ${#ebuilds[@]} )) || continue
		[[ -f ${ebuilds[0]} ]] || continue

		filesdir_refs "${OVERLAY_ROOT}" "${key}"
		[[ -n ${FILESDIR_REFS} ]] || continue

		read -r -a patterns <<<"${FILESDIR_REFS}"
		read -r -a guarded <<<"${FILESDIR_REFS_GUARDED}"
		for pattern in "${patterns[@]}"; do
			[[ -n ${pattern} ]] || continue
			# A path the package tests with -d/-e/-f/-s before using it
			# is optional by construction: absent, the use is skipped.
			# Exact string match on the expanded pattern -- the test and
			# the use name the same path, so they expand the same way.
			is_guarded=""
			for g in "${guarded[@]}"; do
				[[ ${g} == "${pattern}" ]] && { is_guarded=1; break; }
			done
			[[ -z ${is_guarded} ]] || continue
			if ! compgen -G "${pkg_dir}/files/${pattern}" >/dev/null; then
				# Recorded per PACKAGE, not per ebuild: filesdir_refs pools
				# every ebuild of the package, so blaming one of them would
				# be a guess.
				eb_names=${ebuilds[*]##*/}
				PARITY_MISSING_FILES+=(
					"${key}"$'\t'"${eb_names}"$'\t'"${pattern}"
				)
			fi
		done
	done

	printf '  [missing]  %d ${FILESDIR} reference(s) matching no file -- these DIE at install\n' \
		"${#PARITY_MISSING_FILES[@]}"
}

# Every md5-cache entry naming an ebuild that is not in the tree.
#
# Publishes PARITY_CACHE_NO_EBUILD. Overlay-wide like the orphan check, and for
# the same reason: this is litter in THIS repository, not a difference from
# ::gentoo, so restricting it to the shared set would skip the packages nobody
# compares against anything.
#
# WHY IT EXISTS. On 2026-09-07 this was 548 of 916 entries -- sixty percent of
# the directory -- across 221 packages. Two mechanical sources: a bump writes
# the new entry and leaves the old one, and a package removed from the overlay
# leaves its entire set behind. Nothing reads them, so nothing breaks; they
# describe a tree that is not there. Without a check the count just climbs
# again, which is how it reached 548.
#
# Does NOT fail the run, matching the orphan and stale-tag sections.
check_cache_without_ebuild() {
	local cache_dir cat_dir category entry name cats
	local -a categories=()

	cache_dir="${OVERLAY_ROOT}/metadata/md5-cache"
	if [[ ! -d ${cache_dir} ]]; then
		printf '  [cache]    no md5-cache directory to check\n'
		return 0
	fi

	for cat_dir in "${cache_dir}"/*/; do
		[[ -d ${cat_dir} ]] || continue
		cat_dir=${cat_dir%/}
		category=${cat_dir##*/}

		if [[ -n ${FILTER} ]]; then
			case ${FILTER} in
				*/*) [[ ${category} == "${FILTER%%/*}" ]] || continue ;;
				*)   [[ ${category} == "${FILTER}" ]] || continue ;;
			esac
		fi

		for entry in "${cat_dir}"/*; do
			[[ -f ${entry} ]] || continue
			name=${entry##*/}

			# A cache entry is named like its ebuild minus the extension,
			# but PN cannot be split back out unambiguously -- so glob the
			# category for the filename rather than guess where the
			# boundary between PN and PV falls.
			if ! compgen -G "${OVERLAY_ROOT}/${category}/*/${name}.ebuild" >/dev/null; then
				PARITY_CACHE_NO_EBUILD+=( "${category}"$'\t'"${name}" )
				categories+=( "${category}" )
			fi
		done
	done

	cats=0
	if (( ${#categories[@]} )); then
		cats=$(printf '%s\n' "${categories[@]}" | sort -u | grep -c .)
	fi
	printf '  [cache]    %d md5-cache entr%s naming an ebuild that is not in the tree, across %d categor%s\n' \
		"${#PARITY_CACHE_NO_EBUILD[@]}" \
		"$( (( ${#PARITY_CACHE_NO_EBUILD[@]} == 1 )) && printf 'y' || printf 'ies' )" \
		"${cats}" \
		"$( (( cats == 1 )) && printf 'y' || printf 'ies' )"
}

# Every file under a package's files/ that no ebuild of that package names.
#
# Publishes PARITY_ORPHAN_FILES. Scans the whole overlay rather than the shared
# set, for the reason recorded beside the array.
#
# It reuses filesdir_refs and split_by_reference unchanged - the same pair the
# files/ stage uses to decide which overlay-only names to suppress. That is
# deliberate: the question "does an ebuild reach this name" has exactly one
# right answer, and two implementations of it would drift.
check_orphan_files() {
	local pkg_dir key category pn files_dir name
	local -a names=() surplus=()
	local packages=0 total=0

	for pkg_dir in "${OVERLAY_ROOT}"/*/*/; do
		pkg_dir=${pkg_dir%/}
		pn=${pkg_dir##*/}
		category=${pkg_dir%/*}
		category=${category##*/}
		key="${category}/${pn}"

		files_dir="${pkg_dir}/files"
		[[ -d ${files_dir} ]] || continue

		# Same filter shape the sweep and the digest check use, so a
		# targeted run stays targeted.
		if [[ -n ${FILTER} ]]; then
			case ${FILTER} in
				*/*) [[ ${key} == "${FILTER}" ]] || continue ;;
				*)   [[ ${category} == "${FILTER}" ]] || continue ;;
			esac
		fi

		# A directory holding no ebuild is not a package; files/ under one
		# is unreachable by definition and saying so per entry would be
		# noise, not a finding.
		names=( "${pkg_dir}"/*.ebuild )
		(( ${#names[@]} )) || continue

		FILE_DIGESTS=()
		digest_tree "${files_dir}" overlay
		[[ -n ${DIGEST_NAMES} ]] || continue
		packages=$(( packages + 1 ))

		filesdir_refs "${OVERLAY_ROOT}" "${key}"
		split_by_reference "${DIGEST_NAMES}" "${FILESDIR_REFS} ${FILESDIR_REFS_ECLASS}"
		[[ -n ${SPLIT_ORPHAN} ]] || continue

		surplus=()
		read -r -a surplus <<<"${SPLIT_ORPHAN}"
		total=$(( total + ${#surplus[@]} ))
		PARITY_ORPHAN_FILES+=( "${key}"$'\t'"${#surplus[@]}"$'\t'"${SPLIT_ORPHAN}" )
	done

	printf '  [orphans]  %d file(s) under files/ that no ebuild names, across %d package(s) with a files/ dir\n' \
		"${total}" "${packages}"
}

# Which tagged axes no longer name a real divergence.
#
# Reads two things stage 5 and stage 6 already published - PARITY_TAGGED_AXES
# and the axis column of PARITY_ROWS - so it re-derives nothing. A tag is stale
# when its axis produced no row for that ebuild, which covers both ways the
# reason can evaporate: ::gentoo adopted the same value, or the whole ebuild
# went byte-identical and stage 6 suppressed its rows.
#
# A tag naming an axis this script does not compare is NOT reported. It may be a
# typo, or it may name something real that md5-cache does not carry; calling
# either one "stale" would be a claim the evidence does not support.
#
# ONLY EXACT-DISTANCE EBUILDS ARE JUDGED, and this restriction is the whole
# correctness of the check. "No row for this axis" has two causes that look
# identical from here: the two sides agreed, or the axis was never compared.
# Stage 4 compares dependency bounds ONLY at exact distance, because a newer
# overlay version legitimately raises a minimum -- so at any other distance a
# DEPEND tag produces no row no matter how far apart the trees are.
#
# Measured on the first full sweep, before this guard was added: all six tags it
# reported as stale were same-series or package-distance Vulkan/SPIR-V ebuilds
# whose DEPEND had simply not been compared. Six false positives out of six is
# how a new check gets switched off in its first week.
check_stale_tags() {
	local key entry axis row rowpkg rowaxis rowpv found baseline distance
	local -a known_axes=(
		EAPI SLOT HOMEPAGE REQUIRED_USE
		INHERIT DEFINED_PHASES LICENSE
		DEPEND RDEPEND BDEPEND
		IUSE IUSE_DEFAULTS KEYWORDS
		PATCHES
	)

	for key in "${!PARITY_TAGGED_AXES[@]}"; do
		entry=${key%|*}
		axis=${key##*|}

		axis_in "${axis}" "${known_axes[@]}" || continue

		# Silence unless the pair is at exact distance, where every axis
		# above really was compared and "no row" really does mean "equal".
		distance=""
		for baseline in "${PARITY_BASELINES[@]}"; do
			if [[ ${baseline%%$'\t'*} == "${entry}" ]]; then
				distance=${baseline##*$'\t'}
				break
			fi
		done
		[[ ${distance} == exact ]] || continue

		found=0
		for row in "${PARITY_ROWS[@]}"; do
			IFS=$'\t' read -r rowpkg rowpv _ _ rowaxis _ <<<"${row}"
			if [[ "${rowpkg}-${rowpv}" == "${entry}" && ${rowaxis} == "${axis}" ]]; then
				found=1
				break
			fi
		done

		if (( ! found )); then
			PARITY_STALE_TAGS+=(
				"${entry}"$'\t'"${axis}"$'\t'"tag names this axis but the two trees no longer differ on it - ::gentoo caught up; drop the tag and whatever it justified"
			)
		fi
	done

	printf '  [tags]     %d of %d divergence tag(s) name an axis the two trees no longer differ on\n' \
		"${#PARITY_STALE_TAGS[@]}" "${#PARITY_TAGGED_AXES[@]}"
}

# Stage 7. Write the machine-readable table and the human-readable report.
write_reports() {
	# .epic/ is gitignored, so the report directory is not tracked and may
	# not exist on a fresh checkout.
	mkdir -p -- "${REPORT_DIR}"

	gentoo_sync_stamp
	write_parity_data
	write_parity_report

	printf '  [reports]  %s\n' "${PARITY_DATA}"
	printf '  [reports]  %s\n' "${PARITY_REPORT}"
}

# Sub-task 6.3. The exit contract, so the script can gate a future workflow.
#
# Non-zero when at least one ALIGN or UNDOCUMENTED divergence exists: both are
# open questions, one with a default answer and one needing a human.
#
# JUSTIFIED and REDUNDANT do NOT fail the run. The first is a decision already
# recorded in the ebuild - failing on it would mean the guard never goes green
# and stops being run. The second is remediation tracked elsewhere: the 67
# byte-identical ebuilds are a known, pre-approved cleanup, and a gate that
# stayed red until they were removed would block every unrelated change.
sweep_exit_code() {
	local row verdict

	# A missing digest is not drift to schedule - it is an ebuild nobody can
	# install, shadowing whatever ::gentoo ships at the same version. It fails
	# the run on its own, ahead of the verdict scan.
	#
	# PARITY_STALE_TAGS deliberately does not: it misleads a reader and breaks
	# nothing, and a guard that turns red over prose is one people learn to
	# skip - the same reasoning that keeps check-edk2-dbx-freshness.sh out of
	# the pre-commit hook.
	if (( ${#PARITY_MISSING_DIGEST[@]} )); then
		return 1
	fi

	for row in "${PARITY_ROWS[@]}"; do
		verdict=${row##*$'\t'}
		if [[ ${verdict} == ALIGN || ${verdict} == UNDOCUMENTED ]]; then
			return 1
		fi
	done
	return 0
}

run_sweep() {
	check_preconditions || return 2

	printf 'overlay  : %s\n' "${OVERLAY_ROOT}"
	printf '::gentoo : %s\n' "${GENTOO_REPO}"
	printf 'filter   : %s\n' "${FILTER:-(none - full sweep)}"
	printf 'reports  : %s\n' "${REPORT_DIR}"
	printf '\n'

	# A stage that cannot establish what the next one reads stops the sweep
	# here, with its own status and having named what is missing. Carrying on
	# would produce a report covering part of the tree in a format that says
	# nothing about which part.
	build_package_sets || return $?
	select_baseline
	verify_md5_cache || return $?
	compare_axes
	compare_auxiliary_files
	assign_verdicts
	check_manifest_digests
	check_orphan_files
	check_cache_without_ebuild
	check_missing_filesdir_refs
	check_stale_tags
	write_reports

	# The verdict lands here: non-zero when any package needs action.
	sweep_exit_code
}

### self-test ########################################################
#
# Everything --self-test writes lives under $TMPDIR and is removed again before
# it returns: one copy of one ebuild (see prepare_tag_scratch), the two-tree
# stale-cache fixture (see prepare_stale_scratch), and the reports the two
# subprocess runs publish into it. No report anywhere else, and nothing at all
# near either package tree.

ASSERT_TOTAL=0
FAILURES=()
# An assertion whose PINNED subject is not in the tree. Kept apart from
# FAILURES because the two mean opposite things about the RULE: a failure says
# the rule broke, a skip says the rule was never exercised.
SKIPPED=()

# The one ebuild A09 needs a tag on. Pinned rather than discovered: the
# assertion is about a specific hand-inspected divergence, so a version that
# moved on is a stale assertion to re-measure, not a lookup to make dynamic.
SELF_TEST_TAGGED_PKG='kde-plasma/spectacle'
# RE-PINNED 2026-09-05: spectacle was revbumped to -r1 and the unrevised
# ebuild left the tree, so the exact PV this fixture copies had to follow.
SELF_TEST_TAGGED_PV='6.7.4-r1'

# The filter A12 drives a whole sweep through. Pinned for the same reason: it
# names a category the overlay shares with ::gentoo and diverges from on
# nothing, which is the state a run has to survive and used not to.
#
# If a bump ever gives app-dicts a divergence this assertion goes red as a stale
# measurement - repin it on another clean category, never loosen it to accept a
# non-zero exit. A guard that cannot go green once remediation succeeds is a
# guard nobody re-runs.
SELF_TEST_CLEAN_FILTER='app-dicts'

# The scope A18, A19 and A21 are measured against, and it is BUILT rather than
# pinned - the one place in this harness where that is the right answer.
#
# It used to be dev-ruby/erb, the tree's only stale md5-cache entry when story
# 008 measured it. That worked exactly once. A stale cache is a TRANSIENT STATE
# of the tree, not a property of a package: on 2026-09-05 a remediation pass ran
# egencache, erb's ruby-fakegem hash caught up with ::gentoo's, and all three
# assertions went red having lost their subject - not because the rule broke,
# but because the tree stopped exhibiting it. Repinning on whichever entry is
# stale today only schedules the same failure for the next egencache run.
#
# So the fixture manufactures the state instead. prepare_stale_scratch writes a
# two-tree pair under $TMPDIR carrying BOTH cases the rule has to tell apart:
#
#   fixture-shared   an eclass the overlay does NOT ship, hashes differing.
#                    Both trees resolved the same ::gentoo file, so this can
#                    only be a stale cache - R2.1
#   fixture-local    an eclass the overlay DOES ship, hashes differing. A
#                    deliberate override, definitional - story 007's R1.6
#
# Neither can be regenerated away, and neither depends on what the overlay is
# carrying this week. The names are deliberately not real eclasses: a fixture
# that borrowed one would pass by accident on a tree that happens to ship it.
SELF_TEST_STALE_FILTER='dev-fixture'
SELF_TEST_STALE_PKG='dev-fixture/staleness'
SELF_TEST_STALE_PV='1.0'
SELF_TEST_STALE_LOCAL_ECLASS='fixture-local'
SELF_TEST_STALE_SHARED_ECLASS='fixture-shared'

# The second fixture, and the reason it exists is A08's history. That assertion
# was pinned on kde-plasma/kwin until kwin left the overlay, then on
# media-gfx/freecad - a package the parity remediation is actively working to
# fix. Pinning a guard on a divergence you intend to CLOSE is the same mistake
# the stale-cache fixture above was built to end: the subject is transient by
# construction, and the assertion goes red when the work succeeds.
#
# It also fills a hole A08 never covered. UNDOCUMENTED is the verdict that asks
# a human to decide, and the tree has held ZERO of them since 2026-09-05 with no
# assertion anywhere proving the rule still fires. "0 undocumented" and "the
# rule stopped working" print the same. One package now exhibits all three
# reachable verdicts at once, so each is asserted against a real signal.
SELF_TEST_VERDICT_FILTER='dev-verdict'
# A SECOND fixture package, in its own category so it perturbs no existing
# assertion. It inherits readme.gentoo-r1 and ships NO README.gentoo -- the one
# shape the verdict fixture cannot hold, because A26 needs that file present.
SELF_TEST_ECLASS_FILTER='dev-eclassreader'
SELF_TEST_VERDICT_PKG='dev-verdict/triple'
SELF_TEST_VERDICT_PV='1.0'

# Where prepare_stale_scratch put the pair. Empty until it runs, which is what
# the pass below checks before reporting anything.
SELF_TEST_FIXTURE_ROOT=''

# q <value>
# Render a value for a report line: newlines flattened, empty made visible. On
# the first run every observed value IS empty, which is exactly the moment a
# line that prints nothing is least readable.
q() {
	local s=${1//$'\n'/ \\n }
	printf '%s' "${s:-(empty)}"
}

# assert_eq <id> <description> <expected> <actual>
# Never aborts. The value of this harness is the whole picture of what is and
# is not implemented; stopping at the first red hides the other ten.
assert_eq() {
	local id=$1 desc=$2 expected=$3 actual=$4

	ASSERT_TOTAL=$(( ASSERT_TOTAL + 1 ))

	if [[ ${actual} == "${expected}" ]]; then
		printf '  [PASS] (%s) %s\n' "${id}" "${desc}"
		return 0
	fi

	# A probe that pins an exact PVR stops finding its subject the moment that
	# ebuild is bumped, revbumped, or -- as happened on 2026-09-07 -- simply
	# deleted by a CONCURRENT SESSION mid-bump, with the replacement still
	# untracked. Reporting that as FAIL says the rule broke, which is false and
	# is how a suite teaches people to ignore it.
	#
	# It is NOT downgraded to a pass. A skip is an assertion that did not run,
	# printed as such and counted separately, because a pinned subject that
	# vanished is a real loss of coverage -- the same call the SLOT comments
	# make when they record a half as UNCOVERED rather than reword it into
	# something weaker that would look green.
	if [[ ${actual} == *subject-missing* ]]; then
		printf '  [SKIP] (%s) %s\n' "${id}" "${desc}"
		printf '         subject absent: %s\n' "$(q "${actual}")"
		SKIPPED+=( "(${id}) ${desc} | subject absent: $(q "${actual}")" )
		return 0
	fi

	printf '  [FAIL] (%s) %s\n' "${id}" "${desc}"
	printf '         expected: %s\n' "$(q "${expected}")"
	printf '         observed: %s\n' "$(q "${actual}")"
	FAILURES+=( "(${id}) ${desc} | expected: $(q "${expected}") | observed: $(q "${actual}")" )
	return 0
}

# assert_eq_direct <id> <desc> <expected> <actual>
# assert_eq WITHOUT the skip branch, for the one assertion that pins the skip
# branch. Routing that assertion through the mechanism it tests is circular, and
# the circularity is not theoretical: a mutant that turned EVERY mismatch into a
# skip silenced its own detector, and the suite exited 0 reporting a skip where
# a clean tree must have none. The mutant survived until this function existed.
#
# Nothing else should use it. A real subject can vanish; this one is a literal.
assert_eq_direct() {
	local id=$1 desc=$2 expected=$3 actual=$4

	ASSERT_TOTAL=$(( ASSERT_TOTAL + 1 ))

	if [[ ${actual} == "${expected}" ]]; then
		printf '  [PASS] (%s) %s\n' "${id}" "${desc}"
		return 0
	fi

	printf '  [FAIL] (%s) %s\n' "${id}" "${desc}"
	printf '         expected: %s\n' "$(q "${expected}")"
	printf '         observed: %s\n' "$(q "${actual}")"
	FAILURES+=( "(${id}) ${desc} | expected: $(q "${expected}") | observed: $(q "${actual}")" )
	return 0
}

### querying what the pipeline published ##############################

# baselines_at_distance <distance>
# How many ebuilds select_baseline placed at <distance>. The distance is the
# last of the three columns.
baselines_at_distance() {
	local wanted=$1 line distance count=0

	for line in "${PARITY_BASELINES[@]}"; do
		distance=${line##*$'\t'}
		if [[ ${distance} == "${wanted}" ]]; then
			count=$(( count + 1 ))
		fi
	done
	printf '%d' "${count}"
}

# verdict_count <verdict>
# How many divergence rows carry <verdict>. The verdict is the last column.
verdict_count() {
	local wanted=$1 row verdict count=0

	for row in "${PARITY_ROWS[@]}"; do
		verdict=${row##*$'\t'}
		if [[ ${verdict} == "${wanted}" ]]; then
			count=$(( count + 1 ))
		fi
	done
	printf '%d' "${count}"
}

# align_survivors
# Every package still carrying an ALIGN row, named and sorted, with the count
# beside it.
#
# A SECOND IMPLEMENTATION of the count verdict_count already produces, and
# deliberately so - the same reasoning arch_set carries. A25 asking
# verdict_count how many ALIGN rows there are is the harness asking the code
# under test to grade itself: a mutant that made verdict_count return 0
# unconditionally left A25 green, which was measured, not imagined. This reads
# column 8 of PARITY_ROWS itself.
#
# NAMED, not just counted, for the reason slot_survivors is: when this goes red
# the next question is always "which package", and a bare number sends the
# reader back to the report to find out.
align_survivors() {
	local row verdict pkg out count=0
	local -a hits=()

	for row in "${PARITY_ROWS[@]}"; do
		verdict=${row##*$'\t'}
		[[ ${verdict} == ALIGN ]] || continue
		count=$(( count + 1 ))
		hits+=( "${row%%$'\t'*}" )
	done

	if (( count == 0 )); then
		printf 'align=0 packages=(none)'
		return 0
	fi
	out=$(printf '%s\n' "${hits[@]}" | sort -u | tr '\n' ' ')
	printf 'align=%d packages=%s' "${count}" "${out% }"
}

# select_rows <category/pn> <PV> <axis> <value> <column>
# Query the divergence table. An empty <PV>, <axis> or <value> matches
# anything. <value> is matched as a substring of the overlay and ::gentoo
# values joined, so an assertion can pin what a row SAYS without pinning how
# the stage that emitted it chose to format the two sides.
#
# Prints the distinct values of <column> across every matching row - sorted,
# space separated - or the placeholder below. Never nothing: an observed value
# of "" would silently agree with an expected value of "".
select_rows() {
	local want_pkg=$1 want_pv=$2 want_axis=$3 want_value=$4 column=$5
	local row pkg opv distance axis overlay gentoo verdict picked out
	local -a hits=()

	for row in "${PARITY_ROWS[@]}"; do
		IFS=$'\t' read -r pkg opv _ distance axis overlay gentoo verdict <<<"${row}"

		[[ ${pkg} == "${want_pkg}" ]] || continue
		[[ -z ${want_pv} || ${opv} == "${want_pv}" ]] || continue
		[[ -z ${want_axis} || ${axis} == "${want_axis}" ]] || continue
		[[ -z ${want_value} || "${overlay} ${gentoo}" == *"${want_value}"* ]] || continue

		case ${column} in
		axis)     picked=${axis} ;;
		verdict)  picked=${verdict} ;;
		distance) picked=${distance} ;;
		overlay)  picked=${overlay} ;;
		gentoo)   picked=${gentoo} ;;
		*)        picked="(select_rows: no column named ${column})" ;;
		esac
		hits+=( "${picked}" )
	done

	if (( ${#hits[@]} == 0 )); then
		printf '(no matching divergence row)'
		return 0
	fi

	out=$(printf '%s\n' "${hits[@]}" | sort -u | tr '\n' ' ')
	printf '%s' "${out% }"
}

# arch_set <KEYWORDS value>
# A keyword list reduced to a comparable set: ~ stripped, sorted, deduplicated.
#
# Deliberately a second implementation of the normalisation the comparator
# performs, rather than a call into it. A harness that reuses the code under
# test agrees with it by construction - including when both are wrong.
arch_set() {
	printf '%s\n' "$1" | tr ' ' '\n' | sed -e 's/^~//' -e '/^$/d' | sort -u | tr '\n' ' '
}

# keywords_false_positives
# KEYWORDS rows that say nothing: both sides carry the same arch set once the ~
# is stripped. ::gentoo stabilises and the overlay does not, so an unnormalised
# comparison emits one of these for essentially every shared package. They are
# the noise the arch-set normalisation exists to remove, and every one that
# survives is a reader trained to skim the report.
keywords_false_positives() {
	local row axis overlay gentoo count=0

	for row in "${PARITY_ROWS[@]}"; do
		IFS=$'\t' read -r _ _ _ _ axis overlay gentoo _ <<<"${row}"
		[[ ${axis} == KEYWORDS ]] || continue
		if [[ "$(arch_set "${overlay}")" == "$(arch_set "${gentoo}")" ]]; then
			count=$(( count + 1 ))
		fi
	done
	printf '%d' "${count}"
}

### story 008: querying the two new rules #############################

# in_md5_scope <category/pn> <PV>
# Whether stage 3 put this exact ebuild in the compared set.
#
# THE DENOMINATOR EVERY SUPPRESSION ASSERTION IS PAIRED WITH. "redis reports no
# SLOT row" is trivially true of a redis that left the overlay, or that ::gentoo
# stopped carrying, or that lost its md5-cache entry - and that is the one way a
# suppression assertion goes green having suppressed nothing.
in_md5_scope() {
	local wanted="$1-$2" entry

	for entry in "${PARITY_MD5_COVERED[@]}"; do
		if [[ ${entry} == "${wanted}" ]]; then
			printf 'yes'
			return 0
		fi
	done
	printf 'no'
}

# slot_outcome <category/pn> <PV>
# What the SLOT axis concluded for one ebuild, with its denominator attached.
slot_outcome() {
	local verdict pn=${1#*/}

	# Absent subject before absent row. in_md5_scope answers `no` for both an
	# ebuild that is gone and an ebuild the cache never covered, and those are
	# not the same claim -- the first says nothing about the SLOT rule.
	if [[ ! -f ${OVERLAY_ROOT}/$1/${pn}-$2.ebuild ]]; then
		printf 'subject-missing'
		return 0
	fi

	verdict=$(select_rows "$1" "$2" SLOT '' verdict)
	if [[ ${verdict} == '(no matching divergence row)' ]]; then
		verdict=none
	fi
	printf 'compared=%s slot=%s' "$(in_md5_scope "$1" "$2")" "${verdict}"
}

# slot_survivors
# Every package still reporting a SLOT row, named and sorted, with the row count
# beside it.
#
# NAMED RATHER THAN COUNTED, and the distinction is the whole assertion. The
# rule findings.md proposed also suppresses nine of the sixteen - while hiding
# imath and glslang, whose subslots are real, and leaving lua, blender and
# binutils standing, whose slots are versions. A count assertion is green for
# both rules. The count is carried anyway because nodejs contributes two of the
# six rows under one name, and losing one of them must not read as unchanged.
slot_survivors() {
	local row pkg axis out rows=0
	local -a hits=()

	for row in "${PARITY_ROWS[@]}"; do
		IFS=$'\t' read -r pkg _ _ _ axis _ _ _ <<<"${row}"
		[[ ${axis} == SLOT ]] || continue
		rows=$(( rows + 1 ))
		hits+=( "${pkg}" )
	done

	if (( rows == 0 )); then
		printf 'rows=0 packages=(none)'
		return 0
	fi

	out=$(printf '%s\n' "${hits[@]}" | sort -u | tr '\n' ' ')
	printf 'rows=%d packages=%s' "${rows}" "${out% }"
}

# slot_survivors_count
# Just the surviving SLOT row count, for the assertions that need it as a
# denominator beside something else.
slot_survivors_count() {
	local row axis count=0

	for row in "${PARITY_ROWS[@]}"; do
		IFS=$'\t' read -r _ _ _ _ axis _ _ _ <<<"${row}"
		if [[ ${axis} == SLOT ]]; then
			count=$(( count + 1 ))
		fi
	done
	printf '%d' "${count}"
}

# eclass_row_verdict <category/pn> <PV>
# The verdict on this ebuild's _eclasses_ divergence row, or "none" when it has
# none. select_rows' own placeholder is spelled out for a reader of the report
# line; here the assertion is about presence, so it reads better as none.
eclass_row_verdict() {
	local verdict

	verdict=$(select_rows "$1" "$2" '_eclasses_' '' verdict)
	if [[ ${verdict} == '(no matching divergence row)' ]]; then
		verdict=none
	fi
	printf '%s' "${verdict}"
}

# slot_suppression_record
# R1.5, read back: how many suppressions were recorded and how many carry a
# reason. Paired with the surviving row count, because "0 recorded, 0 with a
# reason" is what a script that never suppressed anything also reports.
slot_suppression_record() {
	local entry recorded=0 with_reason=0 reason

	for entry in "${PARITY_SLOT_SUPPRESSED[@]}"; do
		recorded=$(( recorded + 1 ))
		reason=${entry##*$'\t'}
		if [[ -n ${reason} && ${entry} == *$'\t'* ]]; then
			with_reason=$(( with_reason + 1 ))
		fi
	done

	printf 'recorded=%d with-reason=%d' "${recorded}" "${with_reason}"
}

# stale_cache_for <category/pn>
# Which eclass the run recorded as a stale cache entry for this package.
stale_cache_for() {
	local wanted=$1 entry rest

	for entry in "${PARITY_STALE_CACHE[@]}"; do
		[[ ${entry%%$'\t'*} == "${wanted}" ]] || continue
		rest=${entry#*$'\t'}     # drop the package
		rest=${rest#*$'\t'}      # drop the PV
		printf '%s' "${rest%%$'\t'*}"
		return 0
	done
	printf '(none recorded)'
}

# local_eclasses_in_stale
# How many of the eclasses the overlay actually SHIPS were filed as a stale
# cache. Must be zero: an overlay-local eclass is a deliberate override, and
# calling one a stale cache is the blanket-suppression failure this rule is most
# likely to have. Read from eclass/ at run time for the reason sub-task 4.1
# gives - a fourth local eclass added later must be covered without an edit.
local_eclasses_in_stale() {
	local path eclass entry rest count=0

	for path in "${OVERLAY_ROOT}"/eclass/*.eclass; do
		eclass=${path##*/}
		eclass=${eclass%.eclass}
		for entry in "${PARITY_STALE_CACHE[@]}"; do
			rest=${entry#*$'\t'}
			rest=${rest#*$'\t'}
			if [[ ${rest%%$'\t'*} == "${eclass}" ]]; then
				count=$(( count + 1 ))
			fi
		done
	done
	printf '%d' "${count}"
}

# definitional_eclasses
# The overlay-local eclasses stage 5 recorded, named and sorted. The other half
# of the converse: they must still be recorded as definitional, not moved into
# the stale-cache bucket.
definitional_eclasses() {
	local entry out
	local -a names=()

	for entry in "${PARITY_ECLASS_DEFINITIONAL[@]}"; do
		names+=( "${entry%%$'\t'*}" )
	done

	if (( ${#names[@]} == 0 )); then
		printf '(none)'
		return 0
	fi
	out=$(printf '%s\n' "${names[@]}" | sort -u | tr '\n' ' ')
	printf '%s' "${out% }"
}

# row_arithmetic
# R2.2, read back: the divergence row total, the sum of the four verdicts, and
# the stale-cache observations recorded outside both.
#
# The four verdicts must still SUM to the row total. That is what "reported in a
# section of their own, excluded from the row count" has to mean operationally,
# and it is the invariant a fifth verdict would break.
row_arithmetic() {
	local sum

	sum=$(( $(verdict_count ALIGN) + $(verdict_count JUSTIFIED) +
		$(verdict_count UNDOCUMENTED) + $(verdict_count REDUNDANT) ))

	printf 'rows=%d verdict-sum=%d stale=%d' \
		"${#PARITY_ROWS[@]}" "${sum}" "${#PARITY_STALE_CACHE[@]}"
}

# stale_cache_run <scratch dir>
# Drive a real sweep over a scope whose ONLY finding is the stale cache, and
# report "exit=<rc> rows=<n> stale=<state>".
#
# A SUBPROCESS for the reason zero_divergence_run is one: what is under test is
# the whole path through write_reports to the exit code, and an in-process run
# would inherit this shell's already-populated arrays.
#
# All three halves are needed, which is what Task 2.3 asks the assertion to
# distinguish. exit=0 alone is also what a scope with nothing in it returns;
# rows=0 alone says nothing about whether the observation was kept; and
# stale=present alone says nothing about the exit contract. rows=-1 is a fourth
# state - the data file was never written - kept distinct from rows=0 so a run
# that died before publishing cannot read as a clean one.
stale_cache_run() {
	local scratch=$1
	local dir="${scratch}/stale-cache"
	local report="${dir}/parity-report.md"
	local data="${dir}/parity-data.tsv"
	local rc=0 rows=-1 stale=absent lines

	mkdir -p -- "${dir}"

	if [[ -z ${SELF_TEST_FIXTURE_ROOT} ]]; then
		printf 'exit=- rows=-1 stale=(fixture not built)'
		return 0
	fi

	# Started through the SYMLINK inside the fixture, not through this file:
	# that is what makes the subprocess treat the fixture as its overlay,
	# without an env var that could repoint a real sweep. See
	# prepare_stale_scratch.
	GENTOO_REPO="${SELF_TEST_FIXTURE_ROOT}/gentoo" PARITY_REPORT_DIR="${dir}" \
		bash -- "${SELF_TEST_FIXTURE_ROOT}/overlay/scripts/gentoo-parity.sh" \
		"${SELF_TEST_STALE_FILTER}" \
		>/dev/null 2>&1 || rc=$?

	if [[ -f ${data} ]]; then
		lines=$(wc -l <"${data}")
		rows=$(( lines - 1 ))
	fi

	# The remediation string R2.3 requires beside the observation. Emitted
	# only when there IS one, so grepping for it is exactly "at least one
	# stale-cache entry was reported" and needs no prose parsing.
	if [[ -f ${report} ]] &&
		grep -qF -- 'egencache --update --repo bentoo' "${report}"; then
		stale=present
	fi

	printf 'exit=%d rows=%d stale=%s' "${rc}" "${rows}" "${stale}"
}

# zero_divergence_run <scratch dir>
# Drive a real sweep over a scope that holds no divergence, and report what came
# back as "exit=<rc> report=<state>".
#
# A SUBPROCESS, not a call into run_sweep. What is under test is the whole path
# from the stages through write_reports to the exit code, and an in-process run
# would inherit this shell's already-populated arrays - the one state in which
# the empty case cannot happen.
#
# PARITY_REPORT_DIR sends both files to the scratch directory. GENTOO_REPO is
# passed explicitly because it is a shell variable here, not an exported one,
# and a subprocess falling back to the default would compare a different tree
# from the one the other eleven assertions just measured.
#
# report=<state> is three-valued on purpose: "missing" (write_reports never
# ran), "truncated" (it died partway and left a fragment) and "complete" are
# three different defects, and a boolean would collapse them into one red.
zero_divergence_run() {
	local scratch=$1
	local dir="${scratch}/zero-divergence"
	local report="${dir}/parity-report.md"
	local rc=0 state

	mkdir -p -- "${dir}"

	GENTOO_REPO="${GENTOO_REPO}" PARITY_REPORT_DIR="${dir}" \
		bash -- "${BASH_SOURCE[0]}" "${SELF_TEST_CLEAN_FILTER}" \
		>/dev/null 2>&1 || rc=$?

	# The last heading write_parity_report emits. Reached only by walking the
	# per-axis loop that used to be fatal here, so its presence is what
	# separates a complete report from one cut off at "### By axis".
	if [[ ! -f ${report} ]]; then
		state=missing
	elif grep -q '^## What this report does not cover$' -- "${report}"; then
		state=complete
	else
		state=truncated
	fi

	printf 'exit=%d report=%s' "${rc}" "${state}"
}

### driving the pipeline for the self-test ############################

# prepare_tag_scratch <scratch dir>
# A09 asserts a verdict no ebuild in the tree can currently produce: the
# overlay carries zero # BENTOO-DIVERGENCE: tags (measured 2026-08-06), and R7
# makes this story read-only - a guard that edits an ebuild to test its own tag
# parser is editing what it measures.
#
# So the tag goes on a COPY under the scratch directory, registered in
# PARITY_TAG_SOURCE. The overlay is only ever read. This is the seam sub-task
# 5.2 fills: its parser looks an ebuild up in that map before falling back to
# the tracked file, and nothing else about the pipeline changes.
#
# Called BEFORE the stages run, so the override is in place when the verdicts
# are assigned.
prepare_tag_scratch() {
	local scratch=$1
	local category=${SELF_TEST_TAGGED_PKG%%/*}
	local pn=${SELF_TEST_TAGGED_PKG##*/}
	local pf="${pn}-${SELF_TEST_TAGGED_PV}"
	local src="${OVERLAY_ROOT}/${SELF_TEST_TAGGED_PKG}/${pf}.ebuild"
	local copy="${scratch}/${pf}.ebuild"

	if [[ ! -f ${src} ]]; then
		printf '  [NOTE] no %s to copy, so A09 can only fail\n' "${src}"
		printf '         either the package moved on, or the assertion needs repinning\n'
		return 0
	fi

	cp -- "${src}" "${copy}"
	printf '\n# BENTOO-DIVERGENCE: PATCHES - opencv5 fix not in ::gentoo yet\n' >>"${copy}"
	PARITY_TAG_SOURCE["${category}/${pf}"]=${copy}

	printf '  [SEAM] tag source %s -> %s\n' \
		"${category}/${pf}" "${PARITY_TAG_SOURCE["${category}/${pf}"]}"
}

# prepare_stale_scratch <scratch dir>
# Build the two-tree fixture A18, A19 and A21 are measured against, and record
# where it went in SELF_TEST_FIXTURE_ROOT. See the constants above for why the
# state is manufactured rather than found in the tree.
#
# WHY THE SCRIPT IS SYMLINKED INTO IT. OVERLAY_ROOT is derived from the script's
# own location and is deliberately NOT overridable - an env var that repoints
# what the sweep measures is one typo away from a report about the wrong tree.
# A symlink at <fixture>/overlay/scripts/gentoo-parity.sh needs no such var:
# dirname resolves to the fixture's scripts/, so a subprocess started through
# the symlink treats the fixture as its overlay and nothing else changes. There
# is no second copy of the script to drift from this one.
#
# WHAT EACH FILE IS FOR, because every one of them is load-bearing:
#
#   the two md5-cache entries  identical on every compared axis except
#                              _eclasses_, so the ONLY observation the run can
#                              make is the stale cache. That is R2.4's exact
#                              state and what lets A21 expect rows=0
#   the two ebuilds            differ by their comment line. Byte-identical
#                              ones would be classified REDUNDANT, which is a
#                              row, and rows=0 is the point
#   the two metadata.xml       identical, and present on BOTH sides. A package
#                              missing one on either side emits a metadata.xml
#                              row of its own, and that row is not what is
#                              under test here
#   no SRC_URI                 so the digest check has nothing to look for. A
#                              fixture that failed the run on a missing DIST
#                              line would fail A21 for the wrong reason
prepare_stale_scratch() {
	local scratch=$1
	local root="${scratch}/stale-fixture"
	local category=${SELF_TEST_STALE_PKG%%/*}
	local pn=${SELF_TEST_STALE_PKG##*/}
	local pf="${pn}-${SELF_TEST_STALE_PV}"
	local side dir

	mkdir -p -- \
		"${root}/overlay/scripts" \
		"${root}/overlay/eclass" \
		"${root}/overlay/metadata/md5-cache/${category}" \
		"${root}/overlay/${category}/${pn}" \
		"${root}/gentoo/profiles" \
		"${root}/gentoo/metadata/md5-cache/${category}" \
		"${root}/gentoo/${category}/${pn}"

	ln -sf -- "${SCRIPT_PATH}" "${root}/overlay/scripts/gentoo-parity.sh"

	# check_preconditions refuses a directory with no repo_name: without it a
	# fixture typo would read as "::gentoo carries nothing", which is the one
	# failure that looks like total divergence.
	printf 'gentoo\n' >"${root}/gentoo/profiles/repo_name"

	# The overlay-local half of the pair. Empty on purpose - compare_eclass_
	# hashes asks only whether eclass/<name>.eclass EXISTS, never what is in it.
	: >"${root}/overlay/eclass/${SELF_TEST_STALE_LOCAL_ECLASS}.eclass"

	for side in overlay gentoo; do
		dir="${root}/${side}/${category}/${pn}"

		printf '# %s copy of the stale-cache fixture\nEAPI=8\n' "${side}" \
			>"${dir}/${pf}.ebuild"

		cat >"${dir}/metadata.xml" <<-'EOF'
			<?xml version="1.0" encoding="UTF-8"?>
			<!DOCTYPE pkgmetadata SYSTEM "https://www.gentoo.org/dtd/metadata.dtd">
			<pkgmetadata>
				<longdescription>stale-md5-cache fixture</longdescription>
			</pkgmetadata>
		EOF
	done

	stale_fixture_cache overlay 1111111111111111 aaaaaaaaaaaaaaaa \
		>"${root}/overlay/metadata/md5-cache/${category}/${pf}"
	stale_fixture_cache gentoo 2222222222222222 bbbbbbbbbbbbbbbb \
		>"${root}/gentoo/metadata/md5-cache/${category}/${pf}"

	SELF_TEST_FIXTURE_ROOT=${root}

	printf '  [SEAM] stale-cache fixture %s -> %s\n' \
		"${SELF_TEST_STALE_PKG}" "${SELF_TEST_FIXTURE_ROOT}"
}

# stale_fixture_cache <side> <shared eclass hash> <local eclass hash>
# One md5-cache entry for the fixture. Every axis the comparator reads is the
# same string on both sides; only _eclasses_ takes the two hashes.
stale_fixture_cache() {
	local side=$1 shared_hash=$2 local_hash=$3

	cat <<-EOF
		DEFINED_PHASES=install
		DESCRIPTION=fixture for the stale md5-cache assertions
		EAPI=8
		HOMEPAGE=https://example.invalid/
		INHERIT=${SELF_TEST_STALE_LOCAL_ECLASS} ${SELF_TEST_STALE_SHARED_ECLASS}
		KEYWORDS=~amd64
		LICENSE=GPL-2
		SLOT=0
	EOF
	printf '_eclasses_=%s\t%s\t%s\t%s\n' \
		"${SELF_TEST_STALE_LOCAL_ECLASS}" "${local_hash}" \
		"${SELF_TEST_STALE_SHARED_ECLASS}" "${shared_hash}"
	printf '_md5_=%s\n' "$(printf '%s' "${side}" | md5sum | cut -d' ' -f1)"
}

# prepare_verdict_scratch
# Extend the fixture trees with one package that exhibits all three verdicts
# assign_verdicts can reach without a byte-identical ebuild. Runs after
# prepare_stale_scratch and reuses its trees; a separate CATEGORY is what keeps
# the two apart, because fixture_pass and A21 both scope by one.
#
# HOW EACH VERDICT IS PRODUCED, and each is one line of md5-cache:
#
#   RDEPEND       only ::gentoo has it. The overlay's surplus is empty, so the
#                 overlay adds nothing and is merely BEHIND - residue, ALIGN
#   IUSE          only the overlay has it, and no tag names IUSE. Somebody put
#                 it there and no reason is recorded - UNDOCUMENTED
#   DEPEND        only the overlay has it, and a tag names DEPEND - JUSTIFIED
#   REQUIRED_USE  only the overlay has it and no tag names it either, so by the
#                 rule above it would be UNDOCUMENTED - except REQUIRED_USE is
#                 in PARITY_SINGLE_VALUED_AXES and can never be promoted. ALIGN
#
# WHY THE FIRST CASE IS RDEPEND AND NOT REQUIRED_USE, which is what it was for
# one draft. REQUIRED_USE cannot reach UNDOCUMENTED on ANY input, so asserting
# ALIGN on it proves nothing about the residue rule - a mutant that deleted the
# surplus test outright still passed. Found by mutation, not by reading.
#
# The same flaw was in BOTH of A08's previous subjects: kwin's PYTHON_COMPAT
# surfaced on a single-valued axis, and freecad's divergence IS REQUIRED_USE. So
# for its whole life this assertion was documented as guarding the residue rule
# while never once exercising it.
#
# The four cases differ only in the criterion each is meant to exercise. A case
# that differed on several things at once would stay green under a rule that
# read the wrong one - which is exactly what happened.
prepare_verdict_scratch() {
	local root=${SELF_TEST_FIXTURE_ROOT}
	local category=${SELF_TEST_VERDICT_PKG%%/*}
	local pn=${SELF_TEST_VERDICT_PKG##*/}
	local pf="${pn}-${SELF_TEST_VERDICT_PV}"
	local side dir

	if [[ -z ${root} ]]; then
		printf '  [NOTE] no fixture tree, so A08 can only fail\n'
		return 0
	fi

	mkdir -p -- \
		"${root}/overlay/metadata/md5-cache/${category}" \
		"${root}/overlay/${category}/${pn}" \
		"${root}/gentoo/metadata/md5-cache/${category}" \
		"${root}/gentoo/${category}/${pn}"

	for side in overlay gentoo; do
		dir="${root}/${side}/${category}/${pn}"
		# DIFFERENT ON THE TWO SIDES, on purpose: metadata.xml is compared
		# for the package rather than per ebuild, so its row is the one that
		# exercises the package-level tag key. Identical files here would
		# emit no row and the fifth case would silently test nothing.
		cat >"${dir}/metadata.xml" <<-EOF
			<?xml version="1.0" encoding="UTF-8"?>
			<!DOCTYPE pkgmetadata SYSTEM "https://www.gentoo.org/dtd/metadata.dtd">
			<pkgmetadata>
				<longdescription>verdict fixture, ${side} side</longdescription>
			</pkgmetadata>
		EOF
	done

	# The tag lives on the OVERLAY ebuild, where the parser looks for it, and
	# names exactly one axis. A second tag naming IUSE would turn the
	# UNDOCUMENTED case into a JUSTIFIED one and the assertion would still be
	# green on two thirds of the rule - which is why it is not there.
	cat >"${root}/overlay/${category}/${pn}/${pf}.ebuild" <<-'EOF'
		# overlay copy of the three-verdict fixture
		# BENTOO-DIVERGENCE: DEPEND - the tagged addition.
		# BENTOO-DIVERGENCE: metadata.xml - the package-level axis. This tag
		# lives in an ebuild but justifies a row keyed on the package, which
		# is the whole point of the package-level key in collect_tags.
		# IUSE deliberately carries no tag at all.
		EAPI=8
	EOF
	printf '# gentoo copy of the three-verdict fixture\nEAPI=8\n' \
		>"${root}/gentoo/${category}/${pn}/${pf}.ebuild"

	# files/ for check_orphan_files: one name the ebuild reaches directly, two
	# it reaches through a brace expansion, and one nothing names. The brace
	# pair is not decoration - six files in active use were reported as
	# orphans until expand_braces existed, and nothing would have caught that
	# coming back.
	mkdir -p -- "${root}/overlay/${category}/${pn}/files"
	local f
	#
	# Two more names pin the two ways a reference can be misread.
	# commented-only.conf is named ONLY on a line that is entirely a
	# comment: harvesting it credited a file nothing installs, so litter
	# stayed invisible. README.gentoo is named by NO line at all, and must
	# still be spared, because readme.gentoo-r1.eclass reads it straight out
	# of FILESDIR -- the two cases pull in opposite directions, so both are
	# asserted rather than one.
	for f in referenced.patch braced-one.conf braced-two.conf orphan.patch \
		commented-only.conf README.gentoo; do
		printf 'fixture file %s\n' "${f}" \
			>"${root}/overlay/${category}/${pn}/files/${f}"
	done
	cat >>"${root}/overlay/${category}/${pn}/${pf}.ebuild" <<-'EOF'
		inherit readme.gentoo-r1
		src_install() {
			eapply "${FILESDIR}"/referenced.patch
			doins "${FILESDIR}"/braced-{one,two}.conf
			# A reference with NO file behind it, for
			# check_missing_filesdir_refs. It must not disturb the
			# orphan count: a name nothing provides cannot suppress
			# anything, so A26 and A29 read the same fixture from
			# opposite ends.
			eapply "${FILESDIR}"/missing.patch
			# doins "${FILESDIR}"/commented-only.conf
			readme.gentoo_create_doc
		}
	EOF

	# A cache entry with nothing behind it, for check_cache_without_ebuild.
	# Placed in the SAME category as the real one on purpose: the check must
	# compare per file, and a version that merely noticed the category exists
	# would pass against a fixture that kept them apart.
	verdict_fixture_cache overlay >"${root}/overlay/metadata/md5-cache/${category}/ghost-9.9.9"
	verdict_fixture_cache overlay >"${root}/overlay/metadata/md5-cache/${category}/${pf}"
	verdict_fixture_cache gentoo  >"${root}/gentoo/metadata/md5-cache/${category}/${pf}"

	printf '  [SEAM] verdict fixture %s -> %s\n' \
		"${SELF_TEST_VERDICT_PKG}" "${root}/${category}"
}

# prepare_eclass_reader_scratch
# One package that inherits readme.gentoo-r1 and ships no README.gentoo.
#
# WHY IT IS A SEPARATE PACKAGE IN A SEPARATE CATEGORY. A29 pins that a
# ${FILESDIR} reference with no file is reported. The opposite mistake --
# check_missing_filesdir_refs consulting FILESDIR_REFS_ECLASS and so demanding a
# README.gentoo from every package that merely inherits the eclass -- could not
# be pinned against the verdict fixture at all: A26 needs README.gentoo PRESENT
# there to prove the sparing works, and this needs it ABSENT. One fixture cannot
# hold a file that is both.
#
# Its own category keeps every existing assertion untouched: they all run under
# SELF_TEST_VERDICT_FILTER and never see this one.
#
# It DOES name a real file. filesdir_refs must produce a non-empty
# FILESDIR_REFS or the check skips the package early and the assertion would be
# green for the wrong reason -- dev-lang/flutter escapes the real-tree version
# of this mistake for exactly that reason, so the fixture must not repeat it.
prepare_eclass_reader_scratch() {
	local root=${SELF_TEST_FIXTURE_ROOT}
	local category=${SELF_TEST_ECLASS_FILTER}
	local dir="${root}/overlay/${category}/reader"

	[[ -n ${root} ]] || return 0

	mkdir -p -- "${dir}/files" "${root}/overlay/metadata/md5-cache/${category}"
	printf 'fixture file\n' >"${dir}/files/real.patch"

	cat >"${dir}/reader-1.0.ebuild" <<-'EOF'
		EAPI=8
		inherit readme.gentoo-r1
		src_install() {
			eapply "${FILESDIR}"/real.patch
			readme.gentoo_create_doc
		}
	EOF

	printf '  [SEAM] eclass-reader fixture %s/reader -> %s\n' \
		"${category}" "${dir}"
}

# verdict_fixture_cache <side>
# One md5-cache entry for the verdict fixture. Every axis is identical on both
# sides except the three named above, so exactly three rows are emitted.
verdict_fixture_cache() {
	local side=$1

	cat <<-EOF
		DEFINED_PHASES=install
		DESCRIPTION=fixture for the three divergence verdicts
		EAPI=8
		HOMEPAGE=https://example.invalid/
		KEYWORDS=~amd64
		LICENSE=GPL-2
		SLOT=0
	EOF

	if [[ ${side} == overlay ]]; then
		printf 'DEPEND=dev-verdict/tagged-addition\n'
		printf 'IUSE=untagged-addition\n'
		printf 'REQUIRED_USE=single_valued? ( axis )\n'
	else
		printf 'RDEPEND=dev-verdict/only-in-gentoo\n'
	fi
	printf '_md5_=%s\n' "$(printf 'verdict-%s' "${side}" | md5sum | cut -d' ' -f1)"
}

# fixture_pass <filter> <reporter function>
# Run the real stages against one fixture package and let <reporter> read what
# they concluded.
#
# A SUBSHELL, not a second call into the stages. The assertions read the arrays
# of the CURRENT process - that is the harness's first rule, "read the pipeline,
# not the trees" - and a fixture needs those same arrays to hold the fixture's
# results rather than the sweep's. A subshell gets a copy of every global, so
# repointing the two roots and emptying the arrays inside it is invisible to the
# assertions measured against the real tree. Doing it in-process and restoring
# afterwards would be one forgotten array away from a silent wrong answer in
# some other assertion.
#
# The reporter runs INSIDE that subshell, which is why it is passed by name
# rather than returning data: it has to see the fixture's arrays through the
# same accessors every other assertion uses.
#
# Every array a stage appends to is emptied, including the ones a given reporter
# does not read: leaving one populated would let the sweep's contents leak into
# an answer about the fixture, which is the failure this design exists to stop.
fixture_pass() {
	local filter=$1 reporter=$2

	if [[ -z ${SELF_TEST_FIXTURE_ROOT} ]]; then
		printf '(fixture not built)'
		return 0
	fi

	(
		OVERLAY_ROOT="${SELF_TEST_FIXTURE_ROOT}/overlay"
		GENTOO_REPO="${SELF_TEST_FIXTURE_ROOT}/gentoo"

		# SCOPED TO ONE CATEGORY, always. Two fixtures share these trees and
		# they want opposite things - the stale one needs a scope whose ONLY
		# observation is the stale cache, the verdict one needs three
		# divergence rows. An unfiltered pass would hand each the other's.
		FILTER=${filter}

		PARITY_SHARED_PACKAGES=() PARITY_SCOPE_EBUILDS=() PARITY_EXCLUDED=()
		PARITY_BASELINES=() PARITY_BEHIND=() PARITY_MD5_COVERED=()
		PARITY_IDENTICAL=() PARITY_ROWS=() PARITY_ECLASS_DEFINITIONAL=()
		PARITY_METADATA_SUPPRESSED=() PARITY_FILES_SUPPRESSED=()
		PARITY_SLOT_SUPPRESSED=() PARITY_STALE_CACHE=()
		PARITY_MISSING_DIGEST=() PARITY_STALE_TAGS=()
		PARITY_ORPHAN_FILES=() PARITY_CACHE_NO_EBUILD=()
		PARITY_MISSING_FILES=()
		PARITY_EBUILD_PN=() PARITY_TAG_SOURCE=() PARITY_TAGGED_AXES=()
		MD5_FIELDS=() FILE_DIGESTS=() ECLASS_HASH=()

		build_package_sets >/dev/null || true
		select_baseline >/dev/null
		verify_md5_cache >/dev/null || true
		compare_axes >/dev/null
		compare_auxiliary_files >/dev/null
		assign_verdicts >/dev/null
		check_orphan_files >/dev/null
		check_cache_without_ebuild >/dev/null
		check_missing_filesdir_refs >/dev/null

		"${reporter}"
	)
}

# The reporters. Each is a plain function so it can be named on a fixture_pass
# call and still read the arrays the stages just filled.

report_stale_classification() {
	printf 'compared=%s row=%s stale=%s' \
		"$(in_md5_scope "${SELF_TEST_STALE_PKG}" "${SELF_TEST_STALE_PV}")" \
		"$(eclass_row_verdict "${SELF_TEST_STALE_PKG}" "${SELF_TEST_STALE_PV}")" \
		"$(stale_cache_for "${SELF_TEST_STALE_PKG}")"
}

report_stale_override() {
	printf 'definitional=%s local-in-stale=%s stale=%d' \
		"$(definitional_eclasses)" \
		"$(local_eclasses_in_stale)" \
		"${#PARITY_STALE_CACHE[@]}"
}

report_orphan_files() {
	local entry names

	if (( ${#PARITY_ORPHAN_FILES[@]} == 0 )); then
		printf 'packages=0 orphans=(none)'
		return 0
	fi
	entry=${PARITY_ORPHAN_FILES[0]}
	names=${entry##*$'\t'}
	printf 'packages=%d orphans=%s' "${#PARITY_ORPHAN_FILES[@]}" "${names}"
}

# ${FILESDIR} references matching no file. Named, for the same reason as every
# other reporter here: a count cannot tell a fix from a different breakage.
report_missing_filesdir_refs() {
	local entry names=""

	if (( ${#PARITY_MISSING_FILES[@]} == 0 )); then
		printf 'missing=0 names=(none)'
		return 0
	fi
	for entry in "${PARITY_MISSING_FILES[@]}"; do
		names+="${entry##*$'\t'} "
	done
	printf 'missing=%d names=%s' "${#PARITY_MISSING_FILES[@]}" "${names% }"
}

# md5-cache entries with no ebuild, NAMED rather than counted: a count is green
# for a check that found the wrong file, and the remediation here is deletion.
report_cache_without_ebuild() {
	local entry names=""

	if (( ${#PARITY_CACHE_NO_EBUILD[@]} == 0 )); then
		printf 'entries=0 names=(none)'
		return 0
	fi
	for entry in "${PARITY_CACHE_NO_EBUILD[@]}"; do
		names+="${entry##*$'\t'} "
	done
	printf 'entries=%d names=%s' "${#PARITY_CACHE_NO_EBUILD[@]}" "${names% }"
}

# The three verdicts a divergent ebuild can be given, read off one package that
# exhibits all three at once. See prepare_verdict_scratch for how each arises.
report_verdict_triple() {
	local pkg=${SELF_TEST_VERDICT_PKG} pv=${SELF_TEST_VERDICT_PV}

	printf 'behind=%s untagged-addition=%s tagged-addition=%s single-valued=%s package-level=%s' \
		"$(select_rows "${pkg}" "${pv}" RDEPEND '' verdict)" \
		"$(select_rows "${pkg}" "${pv}" IUSE '' verdict)" \
		"$(select_rows "${pkg}" "${pv}" DEPEND '' verdict)" \
		"$(select_rows "${pkg}" "${pv}" REQUIRED_USE '' verdict)" \
		"$(select_rows "${pkg}" '(package)' metadata.xml '' verdict)"
}

# self_test_pipeline
# Drives the real stages, in the sweep's order. write_reports is deliberately
# not called: the self-test proves the numbers, it does not publish them.
#
# check_preconditions is probed rather than enforced. --self-test must stay
# runnable with no ::gentoo checkout, but the twelve facts below are
# measurements of two real trees and cannot be confirmed without one. A missing
# tree therefore says so and skips the stages, leaving every measurement empty
# and failing. Staying silent would be worse: twelve reds that look like the
# script disagreeing with the numbers, when it never got to look.
self_test_pipeline() {
	if ! check_preconditions 2>/dev/null; then
		printf '  [NOTE] no usable ::gentoo tree at %s\n' "${GENTOO_REPO}"
		printf '         every measurement below reads empty and fails: that is a\n'
		printf '         missing precondition, not a disagreement with the numbers\n'
		return 0
	fi

	# The opposite of the sweep's rule, for the reason assert_eq gives: a stage
	# that fails must leave its arrays short and let the assertion that reads
	# them report it. Aborting here would hide the other ten reds, which is the
	# one thing this harness exists not to do.
	build_package_sets || true
	select_baseline
	verify_md5_cache || true
	compare_axes
	compare_auxiliary_files
	assign_verdicts
}

### the twelve assertions #############################################
#
# design.md's Testing Strategy table, executable. The numbers were measured by
# hand on 2026-08-05, re-measured on 2026-08-06, and four of them re-measured
# again later the same day after 05b58fec5 added three packages (see A01). A run
# that does not reproduce them is wrong, or the measurement is stale and gets
# RE-MEASURED and recorded - never loosened until it agrees.
#
# The overlay is bumped daily, so a scope count going stale is expected and is
# not a defect. What must never happen is a stale count being met by widening
# the assertion instead of explaining the delta.
#
# Each one increments ASSERT_TOTAL and appends to FAILURES on failure, so the
# verdict below stays as written:
#
#   assert_eq <id> <description> <expected> <actual>
#
# Two rules hold for all twelve:
#
#   READ THE PIPELINE, NOT THE TREES. Every observed value comes from what a
#   stage published. An assertion that counted the ebuilds itself would be
#   green with every stage deleted, which is worse than having no assertion.
#
#   NEVER PASS ON NOTHING. Where the expected value is 0, it is paired with a
#   denominator or with a signal known to exist, because "0 out of nothing" and
#   "0 out of 319" are otherwise the same string - and the first is the state
#   this script is in today. An assertion that goes green before the logic it
#   guards exists is a defect, not progress.
self_test_assertions() {
	local scratch
	scratch=$(mktemp -d "${TMPDIR:-/tmp}/gentoo-parity-selftest.XXXXXX")

	printf 'overlay  : %s\n' "${OVERLAY_ROOT}"
	printf '::gentoo : %s\n' "${GENTOO_REPO}"
	printf 'scratch  : %s\n' "${scratch}"
	printf '\npipeline\n'

	prepare_tag_scratch "${scratch}"
	prepare_stale_scratch "${scratch}"
	prepare_verdict_scratch
	prepare_eclass_reader_scratch
	self_test_pipeline

	printf '\nassertions\n'

	# --- what is being compared at all --------------------------------

	# RE-MEASURED 2026-08-06, from 232 / 319 / 82. The overlay gained three
	# packages that afternoon in 05b58fec5: sys-apps/fakeroot and
	# sys-apps/uutils-coreutils, both of which ::gentoo also carries, and
	# sys-apps/uutils-coreutils-bin, which it does not. So 232 + 2 = 234 shared,
	# 319 + 2 = 321 ebuilds and 82 + 1 = 83 overlay-only - every delta accounted
	# for by one commit, with 76 / 67 / 67 unmoved.
	#
	# Recorded rather than adjusted quietly, and never the other way round: an
	# assertion that disagrees with the tree is stale until the difference is
	# EXPLAINED, and only then re-measured. Loosening one to make it agree
	# retires the only thing that would notice the overlay moving under it.
	# RE-MEASURED 2026-09-05, from 234 / 321 / 76, and the delta is one event:
	# the KDE Plasma line left the overlay. Between bd598cb4d and HEAD the tree
	# lost 82 packages and gained 30; 72 of the 82 are kde-plasma/*, and 81 of
	# them were packages ::gentoo also carries. 12 of the 30 added are shared.
	#
	#     234 - 81 + 12 = 165, which is what stage 1 now publishes.
	#
	# The arithmetic closing exactly is the point: it says the count moved
	# because the TREE moved, not because a stage silently stopped publishing.
	# A01, A02, A03, A06, A07 and A20 all fall out of that single event, and
	# A08 and A11 lost their subjects to it (kwin and kdeplasma-addons were
	# both in the 82).
	# RE-MEASURED 2026-09-05 (second pass). Every one of A01-A07 moved by exactly
	# one, and it is the same one: sci-ml/ollama was removed as a stale duplicate
	# of ::gentoo's copy at the same PV. It was a shared package (A01), holding a
	# single ebuild (A02, A06, A07), and it sat at exact distance (A03, and so
	# the denominator of A04 and A05). One removal, seven counters, all -1.
	assert_eq A01 \
		'shared packages: the overlay packages ::gentoo also carries' \
		'163' "${#PARITY_SHARED_PACKAGES[@]}"

	# RE-MEASURED TWICE during story 008, and left where it started - which is
	# worth recording, because the second measurement is the one that says
	# what this count is really made of.
	#
	# Mid-story it read 322: a concurrent session in this repository had added
	# app-editors/zed-1.16.0_pre20260806-r1 while leaving the unrevised ebuild
	# in place, and eight divergence rows came with it. Minutes later the same
	# session removed the unrevised one - a same-day revision REPLACING its
	# predecessor rather than joining it - and the count returned to 321.
	#
	# So this assertion, and A06, A07 and A20 with it, will flap for anyone
	# running the guard against a working tree another session is bumping.
	# That is the tree moving, not a defect, and the answer is the one story
	# 007 set: re-measure and record the cause. Never widen it to a range so
	# that it stops noticing.
	assert_eq A02 \
		'ebuilds in scope: every overlay ebuild inside a shared package' \
		'250' "${#PARITY_SCOPE_EBUILDS[@]}"

	# Paired with its denominator: 0/0 and 321/321 must not read alike.
	assert_eq A07 \
		'md5-cache coverage: an entry exists on both sides for every ebuild in scope' \
		'250/250' "${#PARITY_MD5_COVERED[@]}/${#PARITY_SCOPE_EBUILDS[@]}"

	# --- what each ebuild is compared against -------------------------

	assert_eq A03 \
		'exact-distance ebuilds: ::gentoo carries the same PV' \
		'5' "$(baselines_at_distance exact)"

	# The live-ebuild trap, and the reason this one carries a denominator:
	# including 9999 in the version sort made a first pass report 34 packages
	# as behind ::gentoo when none are. Zero behind out of zero baselines
	# selected is the bug looking exactly like the fix.
	assert_eq A06 \
		'packages behind ::gentoo: none, once live ebuilds leave the version sort' \
		'behind=0 baselines=250' \
		"behind=${#PARITY_BEHIND[@]} baselines=${#PARITY_BASELINES[@]}"

	# --- what the comparison concluded --------------------------------

	# RE-MEASURED 2026-09-05, from 67, AND PAIRED WITH A DENOMINATOR because the
	# new value is zero. Only an exact-distance ebuild can be byte-identical, so
	# the 6 that A03 counts is the population this 0 is drawn from. Bare '0' was
	# not acceptable here: the header rule is that "0 of nothing" and "0 of 6"
	# must not render as the same string, and with the exact set down from 76 to
	# 6 this is exactly the case it was written for.
	#
	# Zero is expected rather than alarming. Every one of the 67 was an ebuild
	# the overlay carried unmodified at ::gentoo's PV, and 72 kde-plasma
	# packages - which is what most of them were - left the tree.
	assert_eq A04 \
		'byte-identical ebuilds: cmp against the exact baseline agrees' \
		'0/5' "${#PARITY_IDENTICAL[@]}/$(baselines_at_distance exact)"

	assert_eq A05 \
		'REDUNDANT verdicts: one per byte-identical ebuild, its axis rows suppressed' \
		'0/5' "$(verdict_count REDUNDANT)/$(baselines_at_distance exact)"

	# THE VERDICT RULE ITSELF, all three cases at once, against a fixture.
	#
	# assign_verdicts decides between them on ONE criterion - whether the
	# overlay's surplus on the axis is empty, and if not, whether a tag names
	# that axis:
	#
	#   behind             the overlay adds nothing, ::gentoo has more. Residue,
	#                      and the default is to catch up          -> ALIGN
	#   untagged addition  somebody wrote it into the overlay ebuild and no
	#                      reason is recorded                      -> UNDOCUMENTED
	#   tagged addition    the same, with a tag naming the axis    -> JUSTIFIED
	#
	# MEASURED AGAINST A FIXTURE SINCE 2026-09-06, and this one is a repin with
	# a history. A08 was kde-plasma/kwin's PYTHON_COMPAT lag until kwin left the
	# overlay; it was then media-gfx/freecad's REQUIRED_USE, which is a row the
	# parity remediation is actively working to CLOSE. Pinning a guard on a
	# divergence you intend to fix guarantees it goes red when the work succeeds
	# - the same defect the stale-cache fixture was built to end.
	#
	# IT ALSO FILLS A HOLE. Neither of those subjects covered UNDOCUMENTED, and
	# the tree has held zero of them since 2026-09-05: no assertion anywhere
	# proved the rule still fires, and "no package needs a decision" prints
	# exactly like "the rule stopped working". prepare_verdict_scratch builds one
	# package exhibiting all three, differing only in the criterion above.
	assert_eq A08 \
		'verdicts: the five ways assign_verdicts can decide, on one package' \
		'behind=ALIGN untagged-addition=UNDOCUMENTED tagged-addition=JUSTIFIED single-valued=ALIGN package-level=JUSTIFIED' \
		"$(fixture_pass "${SELF_TEST_VERDICT_FILTER}" report_verdict_triple)"

	# The one verdict that needs a tag, and the tag lives on the scratch copy
	# prepare_tag_scratch made. PATCHES is an ebuild-level axis on purpose: it
	# is where the tag can sit. The same divergence also shows up under the
	# file-level files/ axis, which by design carries no justification
	# mechanism at all (design.md, decided at the Phase 1 gate).
	assert_eq A09 \
		'spectacle-6.7.4 PATCHES is JUSTIFIED once a tag names that axis' \
		'JUSTIFIED' \
		"$(select_rows "${SELF_TEST_TAGGED_PKG}" "${SELF_TEST_TAGGED_PV}" PATCHES '' verdict)"

	# Both halves are needed. Zero false positives is trivially true when no
	# KEYWORDS row was ever emitted, so the assertion also demands the signal
	# the normalisation must NOT suppress.
	#
	# RE-PINNED 2026-09-05, from mesa to foldingathome. The mesa signal was
	# ~amd64-linux and ~x86-linux, and this session established that ::gentoo
	# has never carried either at ANY mesa version: they are a fossil, not a
	# divergence, and are due to be removed. Pinning an assertion to a keyword
	# that is known to be leaving is what made this fragile the first time.
	#
	# foldingathome is a better fixture than mesa was. Its -* arm64 is the only
	# other KEYWORDS row where the OVERLAY carries what ::gentoo does not - the
	# direction that survives ~ stripping - and it is already JUSTIFIED, i.e. a
	# recorded decision rather than an accident, where mesa is bumped daily.
	assert_eq A10 \
		'KEYWORDS: no row explainable by ~ alone, and foldingathome still reports its real one' \
		'false-positives=0 signal=KEYWORDS' \
		"false-positives=$(keywords_false_positives) signal=$(select_rows sci-biology/foldingathome '' KEYWORDS '' axis)"

	# ::gentoo inherits cargo and flag-o-matic at this PV and the overlay
	# inherits neither: the overlay ebuild predates an upstream refactor made
	# at the same version. Matched on cargo appearing in the row's values, so
	# the assertion holds whether the stage reports the full INHERIT set or
	# only the delta.
	# RE-PINNED 2026-09-05, from kdeplasma-addons to imagemagick. The original
	# subject left the overlay entirely - the package directory is gone - so
	# the assertion had no ebuild to detect anything on. What it guards is
	# unchanged: that an INHERIT the overlay lacks and ::gentoo carries still
	# produces a row. imagemagick is the same shape (::gentoo inherits
	# verify-sig, the overlay does not) and is ALIGN, i.e. a settled reading
	# rather than a pending decision that a later tag would silence.
	assert_eq A11 \
		'imagemagick INHERIT divergence is detected: ::gentoo has verify-sig, the overlay does not' \
		'INHERIT' \
		"$(select_rows media-gfx/imagemagick '' INHERIT verify-sig axis)"

	# --- what the guard does when it finds nothing --------------------

	# The state the guard exists to reward, and the one it used to die in. Its
	# commonest use is checking the single package just bumped; that scope holds
	# no divergence the moment remediation succeeds, and until this assertion
	# existed such a run exited non-zero on a fatal bad array subscript, having
	# written a report truncated at "### By axis". So the guard could never go
	# green - it reported failure precisely when the work was done.
	#
	# Both halves are asserted because either alone passes on the wrong thing: a
	# report can be complete after a non-zero exit, and an exit of 0 says
	# nothing about whether write_reports finished.
	assert_eq A12 \
		'a scope with no divergence exits 0 and still writes a complete report' \
		'exit=0 report=complete' \
		"$(zero_divergence_run "${scratch}")"

	# --- story 008: SLOT free of version artifacts --------------------
	#
	# Measured 2026-08-06 from parity-data.tsv, by hand and independently of
	# this script (.epic/stories/008-.../measurement.md). Ten of the sixteen
	# SLOT rows differ only because the two sides sit at different versions
	# and the package puts its version in the slot or the subslot. Six are
	# structural and must survive.
	#
	# findings.md called it 14 and 2. It was wrong in both directions,
	# because it looked only past the "/": it counted imath and glslang as
	# noise when their subslots are real, and missed lua, blender and
	# binutils, which put the version in the slot itself.

	# The outcome as a whole, pinned by NAME. A13 alone would go green for a
	# rule that suppressed ten WRONG rows if it happened to name the right
	# survivors - which is why the four below pin the shapes individually.
	# RE-MEASURED 2026-09-05. Still six rows, but three of the names turned
	# over: webkit-gtk and chromium left the structural set and nettle and
	# libqmi entered it. Neither the count nor the rule moved - the two that
	# left are at PVs whose slots ::gentoo now matches, and the two that
	# arrived diverged on a soname since. The count staying at six across that
	# churn is the assertion working, not coincidence.
	assert_eq A13 \
		'SLOT: only the six structural rows survive, each named' \
		'rows=6 packages=dev-libs/imath dev-libs/nettle dev-util/glslang net-libs/libqmi net-libs/nodejs' \
		"$(slot_survivors)"

	# THE ONE THAT MATTERS MOST, and the reason the component COUNT is
	# compared before derivability. The overlay drops nodejs's subslot
	# entirely, so a := dependency cannot rebuild on an ABI change - the most
	# valuable single finding the 007 sweep produced. "24" and "0/24" both
	# normalise to a placeholder-bearing form, so a rule that compares the
	# normalised forms without checking the count first calls them equal and
	# deletes the finding while looking like a success.
	#
	# Paired with a package whose shape it must NOT be confused with: same
	# axis, same kind of value, opposite answer.
	#
	# RE-PINNED 2026-09-07. That partner was dev-db/redis, whose 0/8.10 is
	# ver_cut 1-2 of its own PV. The package was REMOVED from the overlay that
	# day -- ::gentoo had caught up and then passed it -- so the probe lost its
	# subject and reported subject-missing. dev-libs/liborcus takes its place
	# because the shape is the same one: 0/0.21 against ::gentoo's 0/0.20, a
	# subslot that is nothing but the version.
	#
	# The skip is what made this legible rather than alarming: A14 printed SKIP
	# naming redis, not FAIL naming the SLOT stage, so the cause was the
	# removal and not the rule.
	# RE-MEASURED 2026-09-07: the surviving rows moved ALIGN -> JUSTIFIED when
	# the remediation tagged them. Nothing about the SLOT stage changed - what
	# these three assert is that the row SURVIVES rather than being folded away
	# as a version artifact, and "none" is still the value that would mean it
	# was. A16 already mixed the two verdicts for exactly this reason.
	assert_eq A14 \
		'SLOT: nodejs keeps its missing subslot where a version-only one is dropped' \
		'nodejs@24[compared=yes slot=JUSTIFIED] nodejs@26[compared=yes slot=JUSTIFIED] liborcus[compared=yes slot=none]' \
		"nodejs@24[$(slot_outcome net-libs/nodejs 24.20.0)] nodejs@26[$(slot_outcome net-libs/nodejs 26.8.1)] liborcus[$(slot_outcome dev-libs/liborcus 0.21.0)]"

	# The shape findings.md's rule walks straight past: the version is the
	# SLOT, not the subslot. Paired with the two slots that are not versions
	# at all - a release channel and a genuinely different API generation -
	# because a rule aggressive enough to fold 5.5 into 5.4 must still not
	# fold stable into unstable.
	# RE-PINNED 2026-09-05. chromium and webkit-gtk were the "stays" half, and
	# they stopped diverging: at today's PVs both slots match ::gentoo exactly,
	# so they now report slot=none for the honest reason - there is no row to
	# suppress - rather than because a rule folded them away. Keeping them would
	# have asserted a divergence that no longer exists.
	#
	# nettle takes their place. Its 0/9-7 against ::gentoo's 0/8-6 is a soname
	# pair, not a version pair, so it must survive - which is the property the
	# two departing subjects were there to pin.
	# RE-MEASURED 2026-09-06: the blender probe named 5.2.1 and the package was
	# revbumped to 5.2.1-r1 the same day (uninstallable PYTHON_COMPAT, three
	# dependency floors copied from upstream's bundled-library version list).
	# A probe that names a version stops finding its subject the moment that
	# version is revbumped, and reports compared=no, which reads like the SLOT
	# stage failing rather than the fixture moving. Pinning the exact PVR is
	# deliberate -- the assertion is about THIS package's subslot -- so the
	# maintenance cost is real and belongs here rather than in a looser probe.
	# RE-MEASURED 2026-09-07: the surviving rows moved ALIGN -> JUSTIFIED when
	# the remediation tagged them. Nothing about the SLOT stage changed - what
	# these three assert is that the row SURVIVES rather than being folded away
	# as a version artifact, and "none" is still the value that would mean it
	# was. A16 already mixed the two verdicts for exactly this reason.
	assert_eq A15 \
		'SLOT: a version in the slot itself goes; a soname stays' \
		'lua[compared=yes slot=none] blender[compared=yes slot=none] nettle[compared=yes slot=JUSTIFIED]' \
		"lua[$(slot_outcome dev-lang/lua 5.5.1)] blender[$(slot_outcome media-gfx/blender 5.2.1-r1)] nettle[$(slot_outcome dev-libs/nettle 4.0)]"

	# R1.2's revision case. ::gentoo carries binutils at PV 2.46.1-r1 and
	# its slot reads 2.46: derivability has to strip the -r1 and then accept
	# a component PREFIX, but only at a component boundary.
	#
	# Paired with the two subslots that merely LOOK like versions. imath's 30
	# and 29 are an ABI counter and glslang's 16.1 and 16.3 are a library
	# soname; neither derives from its own PV, and a rule that suppressed
	# them would hide that the overlay is BEHIND ::gentoo on glslang's
	# soname while ahead of it on the version.
	# RE-MEASURED 2026-09-05, AND NARROWED - the narrowing recorded here rather
	# than passed over, because it is a real loss of coverage.
	#
	# sys-devel/binutils and sys-libs/binutils-libs both left the overlay, and
	# they were the only subjects for the FIRST half of what this asserted: that
	# a -r1 in ::gentoo's PV does not defeat deriving its slot from it. Nothing
	# left in the tree has that shape - libqmi carries a revision but its 0/5.12
	# is a soname, which does not derive from 1.39.1 either way. So that half is
	# UNCOVERED until a package with it returns; it was not reworded into
	# something weaker that would look green.
	#
	# The second half kept its subjects and gained one. imath's 30/29 is an ABI
	# counter, glslang's 16.5/16.4 a soname, and libqmi's 5.12/5.11 a third
	# soname; none derives from its own PV, and all three must survive.
	# RE-MEASURED 2026-09-07: the surviving rows moved ALIGN -> JUSTIFIED when
	# the remediation tagged them. Nothing about the SLOT stage changed - what
	# these three assert is that the row SURVIVES rather than being folded away
	# as a version artifact, and "none" is still the value that would mean it
	# was. A16 already mixed the two verdicts for exactly this reason.
	# RE-PINNED 2026-09-07 (second time today): the snapshot moved
	# _p20260903 -> _p20260907. glslang is a dated snapshot, so this pin ages
	# out on every bump of it -- the cost that A15 records as deliberate for
	# exact-PVR probes, landing here roughly weekly.
	#
	# Both times the suite said SKIP naming glslang[subject-missing] rather
	# than FAIL naming the SLOT stage. The first time cost a scratch worktree
	# to diagnose, before the skip existed; this time it named itself.
	assert_eq A16 \
		'SLOT: an ABI counter and a soname are not versions, and all three survive' \
		'imath[compared=yes slot=JUSTIFIED] glslang[compared=yes slot=JUSTIFIED] libqmi[compared=yes slot=JUSTIFIED]' \
		"imath[$(slot_outcome dev-libs/imath 3.2.3)] glslang[$(slot_outcome dev-util/glslang 1.4.357.0_p20260907)] libqmi[$(slot_outcome net-libs/libqmi 1.39.1_pre20260816-r1)]"

	# R1.5. A suppression nobody can audit is indistinguishable from a
	# comparison that silently broke, and telling those two apart is the
	# entire value of this axis now.
	#
	# Carried with the surviving row count, because "0 recorded, 0 with a
	# reason" is exactly what a script that never suppressed anything also
	# reports.
	# RE-MEASURED 2026-09-05, from recorded=10 with-reason=10. Two of the ten
	# version-artifact rows stopped being suppressed because they stopped
	# existing: chromium and webkit-gtk now carry ::gentoo's slot outright (see
	# A15). The invariant this actually guards is untouched - every row that IS
	# suppressed still carries its reason, 8 of 8 - and the survivor count held
	# at 6 through the churn.
	assert_eq A17 \
		'SLOT: every suppressed row is recorded with a reason' \
		'recorded=7 with-reason=7 survivors=6' \
		"$(slot_suppression_record) survivors=$(slot_survivors_count)"

	# --- story 008: instrument error is not divergence ----------------

	# An _eclasses_ hash differs for an eclass the overlay does NOT ship. Both
	# trees resolved the same ::gentoo file, so the two hashes cannot describe
	# different content - only different moments. The overlay's md5-cache entry
	# was generated against an older ::gentoo eclass. It is the instrument
	# reporting itself, and left as a divergence row it is classified
	# UNDOCUMENTED, which asks a human to decide about a measurement error the
	# guard made.
	#
	# MEASURED AGAINST A FIXTURE SINCE 2026-09-06, and the history is the whole
	# argument for it. This assertion was pinned on dev-ruby/erb, which was the
	# tree's only stale entry when story 008 measured it. On 2026-09-05 a
	# remediation pass ran egencache, erb's hash caught up, and A18, A19 and A21
	# all went red having lost their subject - while the rule they guard was
	# working perfectly. The signal was gone, not the logic.
	#
	# So it is manufactured now. prepare_stale_scratch builds a two-tree pair
	# that exhibits both cases by construction; the three assertions read that
	# instead of whatever the tree happens to be carrying. A stale cache is a
	# transient state of a tree and can never be a durable subject.
	#
	# Read the whole line, not the last third. compared=yes says the pair
	# reached the comparison at all, row=none says no divergence row was
	# emitted, and stale=<eclass> says the observation was kept somewhere. Drop
	# either of the first two and a run that compared NOTHING reads identically.
	assert_eq A18 \
		'_eclasses_: a hash differing for an eclass the overlay lacks is a stale cache, not a divergence' \
		'compared=yes row=none stale=fixture-shared' \
		"$(fixture_pass "${SELF_TEST_STALE_FILTER}" report_stale_classification)"

	# THE CONVERSE, so the rule cannot be a blanket suppression of the axis. An
	# eclass the overlay SHIPS differs from ::gentoo's by construction - that is
	# the decision to ship a copy, recorded as definitional by story 007's R1.6.
	# Filing one as a stale cache would be calling a deliberate override a
	# measurement error, which is the failure mode that hides a real one.
	#
	# TWO SOURCES ON ONE LINE, each labelled, and both are needed.
	#
	# The real tree half is what actually matters: the overlay's three eclasses
	# must still be recorded as definitional, and no fixture can prove that
	# about them. If a fourth is added it belongs here, not in a widened rule.
	#
	# The fixture half is the one that needs manufacturing, because it is the
	# only way local-in-stale=0 means anything. Against the real tree today the
	# stale bucket is EMPTY, so "none of the overlay's eclasses is in it" is
	# true of a bucket with nothing in it at all - the "0 out of nothing" the
	# header forbids. The fixture puts exactly one entry in that bucket and
	# demands the local eclass not be the one, which is the claim being made.
	assert_eq A19 \
		'_eclasses_: an eclass the overlay ships stays an override, never a stale cache' \
		'real-tree=brave gstreamer-meson rpm | fixture: definitional=fixture-local local-in-stale=0 stale=1' \
		"real-tree=$(definitional_eclasses) | fixture: $(fixture_pass "${SELF_TEST_STALE_FILTER}" report_stale_override)"

	# R2.2, as arithmetic. 472 rows less the ten SLOT artifacts less the one
	# reclassified _eclasses_ row is 461, and the four verdicts must still
	# sum to it: "a section of their own, excluded from the row count" means
	# the observation left the total rather than becoming a fifth verdict.
	#
	# This is the assertion most sensitive to the flap A02 describes: a single
	# ebuild arriving mid-bump moved it by eight. When it goes red, check the
	# two subtractions before the total - the ten and the one are what this
	# story changed, and an ebuild that moves the total moves neither.
	# RE-MEASURED 2026-09-05, from rows=461 verdict-sum=461 stale=1.
	#
	# The row count follows the KDE Plasma removal like A01 does. What matters
	# is that the two halves still move together: 350 rows, 350 verdicts. That
	# equality is the invariant, and it is tested against a real population,
	# not against zero.
	#
	# stale went 1 -> 0 for a different reason, and it is NOT an invariant that
	# weakened: the tree simply holds no stale cache today, because last
	# session's remediation regenerated the md5-cache that was carrying the one
	# signal. This term is the real tree's count and stays that way - detection
	# is guarded by A18, A19 and A21, which measure a fixture precisely so that
	# a tree with nothing stale in it is a clean tree rather than a blind guard.
	# See the note on A18.
	#
	# RE-MEASURED AGAIN 2026-09-05, from 350, and this time the cause is the
	# remediation itself rather than the tree moving underneath: sci-ml/ollama
	# was removed as a stale duplicate of ::gentoo's, and three packages were
	# revbumped (gstreamer-editing-services, sentry-native, freecad), which
	# retires their old rows. The invariant is untouched - the two halves still
	# move together, 338 against 338.
	#
	# RE-MEASURED AGAIN 2026-09-06, from 338 to 268, and this is the largest
	# single drop the number has taken. It is entirely the files/ stage: 68
	# rows stopped being emitted when files/overlay-only was partitioned into a
	# suppression plus the new files/unreferenced axis, and files/gentoo-only
	# was suppressed whole. Both are recorded in PARITY_FILES_SUPPRESSED, so
	# nothing was dropped unaudited. The invariant is again untouched - what
	# this assertion guards is that the two halves move TOGETHER, and 268
	# against 268 is exactly as true as 338 against 338 was.
	#
	# RE-MEASURED SAME DAY, 268 -> 264, for two reasons that both belong to the
	# files/ work above. Two rows went because filesdir_refs was confusing PV
	# with PVR and reporting live patches as unreferenced (see the note there),
	# and two more because the files those rows named -- the only genuinely
	# dead ones -- were deleted from the tree.
	#
	# RE-MEASURED AGAIN, 264 -> 244, when metadata.xml got the same treatment
	# the files/ axes did: 20 of its 27 rows are a maintainer line that cannot
	# align or a USE flag description that follows its own side's IUSE. Both
	# are recorded in PARITY_METADATA_SUPPRESSED. The invariant holds again --
	# 244 against 244.
	#
	# RE-MEASURED 2026-09-06, 244 -> 245, and the delta is a single row that
	# came from the OTHER tree:
	#
	#     dev-util/vulkan-tools  PATCHES  (none) | vulkan-tools-1.4.357.0-libcxx-23.patch  ALIGN
	#
	# ::gentoo synced at 17:49 that day and added that patch to its 1.4.357.0,
	# which is the baseline the overlay's snapshot is compared against. No
	# bentoo commit is involved: diffing the 244-row report against a fresh
	# sweep shows every other line either unchanged or following a PV that was
	# bumped. Worth recording as its own kind of movement - the count drifts
	# when ::gentoo moves too, and a reader who only checks the overlay's log
	# will not find the cause there.
	#
	# The invariant is untouched: 245 against 245.
	#
	# RE-MEASURED 2026-09-06 (second pass), 245 -> 235, and this one is the
	# remediation itself rather than either tree moving. The gstreamer block was
	# audited package by package and 14 rows were closed:
	#
	#   -10  gst-plugins-base gained virtual/opengl, gst-python gained
	#        gst-plugins-bad, and gst-plugins-qt6 got the three deps the
	#        gstreamer-meson eclass used to put in its DEPEND back - three real
	#        lags, so the rows are gone rather than reclassified
	#    -4  gst-plugins-bad's missing !media-plugins/gst-plugins-va blocker
	#        turned out NOT to be a lag: ::gentoo removed that package and
	#        blocks leftovers, while bentoo still ships it and pulls it through
	#        PDEPEND. Tagged, so those four moved ALIGN -> JUSTIFIED and stay
	#        in the total
	#
	# EXPECT THIS ASSERTION TO MOVE ON EVERY REMEDIATION PASS. It pins the
	# absolute total, and closing a divergence is exactly what lowers it - the
	# number going down is the work succeeding. What must never move is the
	# equality of the two halves.
	#
	# RE-MEASURED 2026-09-06 (third pass), 235 -> 232, and it splits the same
	# way the gstreamer block did - two real lags fixed, two decisions recorded:
	#
	#    -3  libreoffice-l10n gained RPM_COMPRESS_TYPE=xz on both ebuilds, which
	#        widens BDEPEND back to ::gentoo's, and vulkan-tools got back the
	#        test? ( dev-cpp/gtest ) a pin rewrite had deleted
	#    +-0  lua's missing app-portage/elt-patches and foldingathome's missing
	#        dev-util/patchelf are both consequences of divergences ALREADY
	#        tagged on another axis - a dropped libtool inherit and a DEPEND to
	#        BDEPEND move. Tagged on the axis they surface on, so they moved
	#        ALIGN -> JUSTIFIED and stay in the total
	#
	# 232 against 232.
	#
	# RE-MEASURED 2026-09-06 (fourth pass), 232 -> 230, and the ratio inverted:
	# ten rows triaged, ONE was a lag.
	#
	#    -2  xdg-desktop-portal gained media-libs/gst-plugins-base:1.0, which
	#        upstream's meson.build requires unconditionally
	#    +-0  eight rows across crossover-bin, nodejs, opencv, imagemagick,
	#        minikube and xf86-video-qxl were decisions ALREADY explained in
	#        prose beside the code and only missing the machine-readable tag
	#
	# That ratio is the finding, and it is what the tag mechanism is for: the
	# deeper the remediation goes, the more of what is left is documentation
	# debt rather than drift. ALIGN is "no reason RECORDED", never "no reason".
	#
	# 230 against 230.
	#
	# RE-MEASURED 2026-09-07, 230 -> 225, and the five that left were all real
	# fixes rather than reclassifications: nvidia-cuda-toolkit got back a
	# pkg_info phase, vulkan-headers gained ~sparc, sane-backends and
	# linux-firmware were widened to the arch set ::gentoo keywords, and mesa's
	# HOMEPAGE was collapsed onto the one URL the other two redirect to. Six
	# more rows moved ALIGN -> JUSTIFIED in the same pass and stay in the total.
	#
	# KEYWORDS, HOMEPAGE and DEFINED_PHASES now hold no ALIGN row at all. What
	# is left is PATCHES, INHERIT, SLOT and IUSE.
	#
	# 225 against 225.
	#
	# RE-MEASURED 2026-09-07, 225 -> 224. One row left, and it is a fix:
	# sys-firmware/edk2 inherits multiprocessing again, which is what its
	# my_build needs for -n "$(get_makeopts_jobs)". Fourteen more rows moved
	# ALIGN -> JUSTIFIED in the same pass and stay in the total.
	#
	# INHERIT now holds no ALIGN row. PATCHES is the last axis that does.
	#
	# 224 against 224.
	#
	# RE-MEASURED 2026-09-07, 224 -> 222, and the two that left are the four
	# orphan patches deleted from net-im/telegram-desktop and net-libs/nodejs -
	# files no ebuild referenced, naming versions long gone from the tree. They
	# were the tree's only UNDOCUMENTED rows.
	#
	# THIS IS THE PASS WHERE ALIGN REACHED ZERO. All 222 rows are JUSTIFIED, so
	# a full sweep now exits 0 for the first time. That changes what this
	# assertion is worth watching for: until now a rising ALIGN count was
	# ordinary, and from here any ALIGN at all is a NEW divergence that arrived
	# since 2026-09-07 - either a bump that changed an axis, or ::gentoo moving
	# underneath. The sweep is finally usable as a gate.
	#
	# 222 against 222.
	assert_eq A20 \
		'the four verdicts still sum to the row total, with the stale cache outside both' \
		'rows=222 verdict-sum=222 stale=0' \
		"$(row_arithmetic)"

	# --- story 008: what a stale cache does to the exit code ----------

	# R2.4. A scope whose only observation is the stale cache must exit 0:
	# there is nothing for a human to decide, and a guard that fails on its
	# own measurement error is a guard nobody re-runs.
	#
	# Driven through the FIXTURE since 2026-09-06, for the reason A18 gives.
	# This is the one of the three that was already a subprocess, and it stays
	# one: what is under test is the whole path through write_reports to the
	# exit code, which an in-process run cannot exercise. The only change is
	# which overlay the subprocess starts in - the symlink prepare_stale_scratch
	# planted, rather than this file.
	#
	# rows=0 is only reachable because the fixture's two md5-cache entries agree
	# on every axis but _eclasses_. If a future edit gives them a second
	# difference this goes red with rows=1, which is the fixture drifting, not
	# the contract breaking - fix the fixture, never the expectation.
	assert_eq A21 \
		'a scope whose only observation is a stale cache exits 0 and still reports it' \
		'exit=0 rows=0 stale=present' \
		"$(stale_cache_run "${scratch}")"

	# --- 2026-09-04 audit: the two integrity checks -------------------

	# A22 exercises the extractor against the three SRC_URI shapes that
	# actually occur, because every false positive this check could produce
	# comes from mis-reading one of them: a USE-conditional whose parens must
	# not be read as files, an arrow whose TARGET is the distfile name rather
	# than the URL basename, and a plain URL.
	#
	# The arrow is the one worth a test of its own. Reading the basename of
	# the URL instead of the rename target would report a missing digest for
	# every renamed distfile in the overlay - which is most of the GitHub
	# ones - and a check that cries wolf on its first run is a check that gets
	# deleted.
	assert_eq A22 \
		'SRC_URI extractor: USE-conditional, rename arrow, and plain URL' \
		'gstreamer-1.28.6.tar.xz gstreamer-1.28.6.tar.xz.asc|renamed.tar.gz|plain.tar.gz' \
		"$(
			printf '%s' "$(src_uri_distfiles 'https://e.invalid/gstreamer-1.28.6.tar.xz verify-sig? ( https://e.invalid/gstreamer-1.28.6.tar.xz.asc )' | tr '\n' ' ' | sed 's/ $//')"
			printf '|%s' "$(src_uri_distfiles 'https://e.invalid/v1.tar.gz -> renamed.tar.gz')"
			printf '|%s' "$(src_uri_distfiles 'https://e.invalid/dir/plain.tar.gz')"
		)"

	# A23 is the rclone-1.75.0 shape, built from scratch under $TMPDIR: an
	# ebuild whose distfile has no DIST line, in a package whose Manifest
	# carries a DIST for a DIFFERENT version. That second half is what makes
	# the real defect invisible - the Manifest is not empty, it is merely not
	# about this ebuild - so a check that only asked "does a Manifest exist"
	# would pass it.
	#
	# Paired with a clean package in the same scratch tree, so "1" cannot be
	# reached by flagging everything.
	assert_eq A23 \
		'a distfile with no DIST line is caught; a package with one is not' \
		'missing=1 caught=broken-1.0.tar.gz' \
		"$(missing_digest_run "${scratch}")"

	# A24 locks the false positive the first sweep produced. A tag on a
	# same-series pair must stay silent, because stage 4 never compared its
	# axis; only an exact-distance pair carries the evidence to call a tag
	# stale. Both halves are asserted together, so a regression that silences
	# everything cannot pass either.
	assert_eq A24 \
		'a stale tag is reported at exact distance and NEVER at same-series' \
		'exact=stale same-series=silent' \
		"$(stale_tag_distance_run)"

	# --- 2026-09-07: the invariant the sweep finally has ---------------

	# ALIGN reached zero on 2026-09-07 and the sweep exits 0. This is the
	# assertion that keeps it there, and it is the one to read first when the
	# guard goes red: an ALIGN row means a divergence arrived with no reason
	# recorded, either from a bump here or from ::gentoo moving underneath.
	#
	# WHY THIS EXISTS BESIDE A20 RATHER THAN INSTEAD OF IT. A20 pins the
	# absolute row total, so it moves whenever the tree does - it was
	# re-measured five times in the two days this remediation took, and every
	# one of those was bookkeeping rather than a finding. This one does not
	# move: closing a divergence by tagging it leaves the row in place and the
	# count at zero, and only a NEW divergence disturbs it.
	#
	# THE DENOMINATOR IS DELIBERATELY NOT A NUMBER. "align=0" alone is what a
	# run that compared nothing also prints, so the header's rule demands a
	# denominator - but pinning "of 222" would import exactly the drift that
	# makes A20 expensive. Non-emptiness is the weakest claim that still
	# distinguishes "nothing diverges" from "nothing was examined", and it is
	# the one that survives a bump.
	assert_eq A25 \
		'no ALIGN survives: every divergence carries a reason, against a non-empty population' \
		'align=0 packages=(none) rows=non-empty' \
		"$(align_survivors) rows=$( (( ${#PARITY_ROWS[@]} )) && printf non-empty || printf EMPTY )"


	# check_orphan_files, both directions at once. The fixture's files/ holds
	# four names: one the ebuild eapply's, two it reaches through a brace
	# expansion, and one nothing mentions. Only the last may be reported.
	#
	# THE BRACE PAIR IS THE POINT, not padding. Before expand_braces existed
	# the check called flatpak-update.{service,timer}, rustdesk{,-link}.desktop
	# and {50-${PN},wrapper.in} orphans - six files in active use - and the
	# suggested remediation for an orphan is to delete it. A false positive
	# here is an invitation to break a build, so the case that produced it is
	# pinned rather than left to a future reader to rediscover.
	assert_eq A26 \
		'orphan files: braces expand, a commented reference does not count, an eclass-read name is spared' \
		'packages=1 orphans=commented-only.conf orphan.patch' \
		"$(fixture_pass "${SELF_TEST_VERDICT_FILTER}" report_orphan_files)"

	# --- 2026-09-07: the skip, and why it needs its own assertion ------
	#
	# Pinning an exact PVR is a DELIBERATE choice here -- A15 records the
	# reasoning -- and its price is that the subject disappears whenever that
	# ebuild is bumped, revbumped, or deleted by a concurrent session mid-bump.
	# Until now that printed FAIL, which claims the rule broke. It had already
	# taught one reader to dismiss a red as ambient, which is the failure mode
	# the whole suite exists to avoid.
	#
	# The danger of the fix is the opposite one: a skip that quietly becomes a
	# pass turns lost coverage into a green. So the two outcomes are asserted
	# TOGETHER against the same shape of mismatch -- only the marker differs --
	# because a regression that turned every mismatch into a skip would satisfy
	# either half alone.
	assert_eq_direct A27 \
		'an absent pinned subject SKIPs; every other mismatch still FAILs' \
		'absent[fail=0 skip=1] present[fail=1 skip=0]' \
		"$(skip_vs_fail_run)"

	# The fixture holds two cache entries in one category: the real ebuild's,
	# and ghost-9.9.9 with nothing behind it. BOTH directions matter -- naming
	# the ghost proves the check finds litter, and not naming the real one
	# proves it will never tell someone to delete a live entry, which is the
	# expensive mistake here.
	assert_eq A28 \
		'md5-cache: the entry with no ebuild is named, the entry with one is not' \
		'entries=1 names=ghost-9.9.9' \
		"$(fixture_pass "${SELF_TEST_VERDICT_FILTER}" report_cache_without_ebuild)"

	# The orphan check run backwards. Pinned separately from A26 even though
	# both read one fixture, because they fail independently: a change that
	# broke brace expansion would take A26 down while this stayed green.
	#
	# The opposite direction -- this check consulting FILESDIR_REFS_ECLASS, so
	# every package merely inheriting the eclass is asked for a README.gentoo
	# -- cannot be pinned HERE: the verdict fixture ships that file because
	# A26 needs it present. A30 holds that half against a fixture of its own.
	# The pair was split for that reason and not for tidiness.
	assert_eq A29 \
		'${FILESDIR} references: the one with no file is named, the ones with files are not' \
		'missing=1 names=missing.patch' \
		"$(fixture_pass "${SELF_TEST_VERDICT_FILTER}" report_missing_filesdir_refs)"

	# The half A29 cannot hold, now held -- see prepare_eclass_reader_scratch
	# for why it needed a package of its own. dev-eclassreader/reader inherits
	# readme.gentoo-r1 and ships no README.gentoo, which is NOT a defect: the
	# eclass only reads that file when DOC_CONTENTS is unset. If this check
	# ever consults FILESDIR_REFS_ECLASS, the synthesised README.gentoo*
	# pattern matches nothing here and this goes red.
	#
	# Green means "reported nothing", so it could also be green for a check
	# that examined no package at all -- which is why the fixture names a real
	# file it DOES reach. A29 covers the reporting half against the same code.
	assert_eq A30 \
		'a package inheriting readme.gentoo-r1 without the file is not a missing reference' \
		'missing=0 names=(none)' \
		"$(fixture_pass "${SELF_TEST_ECLASS_FILTER}" report_missing_filesdir_refs)"

	# A file name carrying an ERE metacharacter is matched as the literal it
	# is, while `*` still globs. A pure function, so no fixture: the literal
	# names are the subject. The decoy pins the escape itself -- unescaped,
	# `86+` would accept `866`, and a fix that merely made `+` optional
	# would still let it through.
	assert_eq A31 \
		'files/ names holding + ( $ are matched literally; * still globs' \
		'ref=39_memtest86+-r3 a(1).sh x$y.conf foo-1.2.patch orphan=39_memtest866-r3' \
		"$(split_by_reference '39_memtest86+-r3 39_memtest866-r3 a(1).sh x$y.conf foo-1.2.patch' \
			'39_memtest86+-r3 a(1).sh x$y.conf foo-*.patch'
			printf 'ref=%s orphan=%s' "${SPLIT_REFERENCED}" "${SPLIT_ORPHAN}")"

	# A command substitution inside a ${FILESDIR} path is a wildcard, like an
	# unknown ${VAR}. sys-kernel/bentoo-kernel-7.3.0 applies
	# "${FILESDIR}/$(ver_cut 1-2)-${p}": the reader used to stop at the space
	# and yield the pattern "$(ver_cut", so the sweep reported a [missing]
	# reference that DIES at install and an orphan patch -- both false, and the
	# pair turned a clean sweep red. The decoy pins that the pattern is not
	# simply "*": an unrelated file with no dash must stay unreferenced.
	assert_eq A32 \
		'a $(...) inside a ${FILESDIR} path globs, it does not cut the reference' \
		'refs=*-* ref=7.3-0002-fix.patch orphan=config' \
		"$(mkdir -p -- "${scratch}/a32/cat/pkg" &&
			printf '%s\n' 'EAPI=8' \
				'src_prepare() { eapply "${FILESDIR}/$(ver_cut 1-2)-${p}"; }' \
				>"${scratch}/a32/cat/pkg/pkg-7.3.0.ebuild" &&
			filesdir_refs "${scratch}/a32" cat/pkg &&
			split_by_reference '7.3-0002-fix.patch config' "${FILESDIR_REFS}" &&
			printf 'refs=%s ref=%s orphan=%s' "${FILESDIR_REFS}" \
				"${SPLIT_REFERENCED}" "${SPLIT_ORPHAN}")"

	# The opposite shape, from dev-python/conda: the reference sits INSIDE a
	# command substitution. A first fix for A32 globbed every $(...) before
	# reading, which swallowed ${FILESDIR} with it and reported conda's three
	# condarc.* files as orphans -- files the build needs.
	assert_eq A33 \
		'a ${FILESDIR} reference inside $(...) is still read' \
		'refs=condarc.user' \
		"$(mkdir -p -- "${scratch}/a33/cat/pkg" &&
			printf '%s\n' 'EAPI=8' \
				'src_install() { echo "$(cat "${FILESDIR}/condarc.user")" >x || die; }' \
				>"${scratch}/a33/cat/pkg/pkg-1.0.ebuild" &&
			filesdir_refs "${scratch}/a33" cat/pkg &&
			printf 'refs=%s' "${FILESDIR_REFS}")"

	# A path tested before use is optional, from media-video/pipewire:
	# [[ -d "${FILESDIR}"/${PV} ]] && eapply "${FILESDIR}"/${PV}. The sweep
	# reported it as a reference that DIES at install. The decoy pins the
	# other half: an UNTESTED missing path in the same package is still
	# named, so the fix cannot pass by silencing the whole package.
	assert_eq A34 \
		'a ${FILESDIR} path tested with -d before use is not a missing reference' \
		'missing=1 names=absent.patch' \
		"$(mkdir -p -- "${scratch}/a34/cat/pkg/files" &&
			printf '%s\n' 'EAPI=8' \
				'src_prepare() {' \
				'	[[ -d "${FILESDIR}"/${PV} ]] && eapply "${FILESDIR}"/${PV}' \
				'	eapply "${FILESDIR}"/absent.patch' \
				'}' >"${scratch}/a34/cat/pkg/pkg-1.0.ebuild" &&
			OVERLAY_ROOT="${scratch}/a34" FILTER=cat/pkg PARITY_MISSING_FILES=() &&
			check_missing_filesdir_refs >/dev/null &&
			report_missing_filesdir_refs)"

	rm -rf -- "${scratch}"
}

# Run assert_eq twice over the same mismatch, changing only whether the observed
# value carries the absent-subject marker, and report where each landed. A
# subshell per run: assert_eq appends to the very globals the suite is counting.
skip_vs_fail_run() {
	local absent present

	absent=$(
		ASSERT_TOTAL=0
		FAILURES=()
		SKIPPED=()
		assert_eq A27probe 'fixture' 'expected' 'glslang[subject-missing]' >/dev/null
		printf 'fail=%d skip=%d' "${#FAILURES[@]}" "${#SKIPPED[@]}"
	)
	present=$(
		ASSERT_TOTAL=0
		FAILURES=()
		SKIPPED=()
		assert_eq A27probe 'fixture' 'expected' 'glslang[compared=yes slot=none]' >/dev/null
		printf 'fail=%d skip=%d' "${#FAILURES[@]}" "${#SKIPPED[@]}"
	)
	printf 'absent[%s] present[%s]' "${absent}" "${present}"
}

# Run check_stale_tags twice over the same tagged axis, changing only the
# baseline distance, and report what each run concluded. A subshell per run: the
# check appends to globals the sweep also uses.
stale_tag_distance_run() {
	local exact same

	exact=$(
		PARITY_TAGGED_AXES=( ["cat/pkg-1.0|DEPEND"]=1 )
		PARITY_ROWS=()
		PARITY_BASELINES=( "cat/pkg-1.0"$'\t'"1.0"$'\t'"exact" )
		PARITY_STALE_TAGS=()
		check_stale_tags >/dev/null
		(( ${#PARITY_STALE_TAGS[@]} )) && printf 'stale' || printf 'silent'
	)
	same=$(
		PARITY_TAGGED_AXES=( ["cat/pkg-1.0|DEPEND"]=1 )
		PARITY_ROWS=()
		PARITY_BASELINES=( "cat/pkg-1.0"$'\t'"1.1"$'\t'"same-series" )
		PARITY_STALE_TAGS=()
		check_stale_tags >/dev/null
		(( ${#PARITY_STALE_TAGS[@]} )) && printf 'stale' || printf 'silent'
	)
	printf 'exact=%s same-series=%s' "${exact}" "${same}"
}

# Build a two-package tree under scratch - one broken, one clean - and report
# what check_manifest_digests found. A subshell, because the check appends to a
# global the real sweep also uses.
missing_digest_run() {
	local scratch=$1
	local root="${scratch}/digest-tree"

	mkdir -p "${root}/net-misc/broken" "${root}/net-misc/clean" \
		"${root}/metadata/md5-cache/net-misc"

	: >"${root}/net-misc/broken/broken-1.0.ebuild"
	# A DIST for a version that is NOT the one being built: the rclone shape.
	printf 'DIST broken-1.1.tar.gz 1 BLAKE2B ab SHA512 cd\n' >"${root}/net-misc/broken/Manifest"
	printf 'SRC_URI=https://e.invalid/v1.0.tar.gz -> broken-1.0.tar.gz\n' \
		>"${root}/metadata/md5-cache/net-misc/broken-1.0"

	: >"${root}/net-misc/clean/clean-2.0.ebuild"
	printf 'DIST clean-2.0.tar.gz 1 BLAKE2B ab SHA512 cd\n' >"${root}/net-misc/clean/Manifest"
	printf 'SRC_URI=https://e.invalid/clean-2.0.tar.gz\n' \
		>"${root}/metadata/md5-cache/net-misc/clean-2.0"

	(
		OVERLAY_ROOT="${root}"
		FILTER=""
		PARITY_MISSING_DIGEST=()
		check_manifest_digests >/dev/null
		printf 'missing=%d caught=%s' \
			"${#PARITY_MISSING_DIGEST[@]}" \
			"$(IFS=$'\t'; set -- ${PARITY_MISSING_DIGEST[0]-}; printf '%s' "${3-none}")"
	)
}

run_self_test() {
	self_test_assertions

	# A harness that ran nothing must not report success. "0 assertions, all
	# passed" is the single most misleading line a guard can print, and every
	# way of getting there - assertions not written yet, a phase that silently
	# returned early - is a defect worth an exit code.
	if (( ASSERT_TOTAL == 0 )); then
		printf 'the self-test ran no assertions, so it proved nothing\n' >&2
		return 1
	fi

	# Same reasoning as the zero-assertion guard above, one level in: a suite
	# where every subject has vanished is green about nothing.
	if (( ${#SKIPPED[@]} == ASSERT_TOTAL )); then
		printf 'every assertion skipped for a missing subject, so this proved nothing\n' >&2
		return 1
	fi

	local entry
	if (( ${#FAILURES[@]} == 0 )); then
		if (( ${#SKIPPED[@]} == 0 )); then
			printf '\n%d assertions, all passed\n' "${ASSERT_TOTAL}"
			return 0
		fi
		# Printed on the SUCCESS path too, and deliberately: a skip is the
		# one outcome that disappears if nobody prints it, and what
		# disappears with it is the knowledge that the rule went unchecked.
		printf '\n%d assertions, %d passed, %d SKIPPED (subject absent -- NOT covered):\n' \
			"${ASSERT_TOTAL}" "$(( ASSERT_TOTAL - ${#SKIPPED[@]} ))" "${#SKIPPED[@]}"
		for entry in "${SKIPPED[@]}"; do
			printf '  - %s\n' "${entry}"
		done
		return 0
	fi

	printf '\n%d assertions, %d FAILED:\n' "${ASSERT_TOTAL}" "${#FAILURES[@]}"
	for entry in "${FAILURES[@]}"; do
		printf '  - %s\n' "${entry}"
	done
	if (( ${#SKIPPED[@]} )); then
		printf '%d SKIPPED (subject absent -- NOT covered):\n' "${#SKIPPED[@]}"
		for entry in "${SKIPPED[@]}"; do
			printf '  - %s\n' "${entry}"
		done
	fi
	return 1
}

### run ##############################################################

main() {
	local rc=0

	parse_args "$@" || exit $?

	if (( SELF_TEST )); then
		run_self_test || rc=$?
		exit "${rc}"
	fi

	run_sweep || rc=$?
	exit "${rc}"
}

main "$@"
