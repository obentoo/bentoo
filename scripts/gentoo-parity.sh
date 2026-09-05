#!/usr/bin/env bash
# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
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

# highest_version <version>...
# The greatest of the versions given, by sort -V.
#
# KNOWN GAP, stated where it is used rather than discovered later: sort -V is
# GNU version sort, not Gentoo's ver_test. They disagree on suffixed versions -
# Gentoo orders 1.0_rc1 BELOW 1.0, sort -V puts it above. Measured 2026-08-06:
# three shared packages carry a suffixed ::gentoo version and in none of them
# does the disagreement change the version picked, so the sweep is unaffected
# today. design.md specifies sort -V; a package where it starts to matter shows
# up as a baseline that looks wrong for a reason this comment explains.
highest_version() {
	printf '%s\n' "$@" | sort -V | tail -n1
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

	printf '%s\n' "${versions[@]}" | sort -V | tr '\n' ' '
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
	local overlay_top gentoo_top
	local -A candidates=() overlay_versions=()
	local -a pool=() in_series=() overlay_pool=()
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
PARITY_UNJUSTIFIABLE_AXES=(
	'metadata.xml'
	'files/overlay-only'
	'files/gentoo-only'
	'files/content'
)
PARITY_UNJUSTIFIABLE_NOTE='no justification mechanism on this axis: the difference is in a file that holds no ebuild code, so it cannot carry a # BENTOO-DIVERGENCE: tag. Rows here are ALIGN because no reason COULD be recorded, not because none was found - and they are never promoted to UNDOCUMENTED or JUSTIFIED.'

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

# Sub-task 4.1. metadata.xml, for every shared package.
#
# R4.1 says every shared package, and an absent file is therefore a finding and
# not a licence to skip: a package with a metadata.xml on one side only has
# nothing to diff, which is the loudest divergence there is rather than the
# quietest. Measured 2026-08-06: all 232 have one on both sides, so the branch
# below is empty today and says so in the count rather than being left out.
compare_metadata_xml() {
	local key overlay_file gentoo_file overlay_text overlay_state gentoo_state
	local diverged=0 incomplete=0

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
		summarise_diff "${overlay_file}" "${gentoo_file}"
		parity_row "${key}" "${PACKAGE_ROW_PV}" "${PACKAGE_ROW_PV}" \
			"${PACKAGE_ROW_DISTANCE}" 'metadata.xml' \
			"${DIFF_ONLY_OVERLAY}" "${DIFF_ONLY_GENTOO}"
	done

	printf '  [metadata] %d of %d shared package(s) diverge on metadata.xml; %d examined without one on a side\n' \
		"${diverged}" "${#PARITY_SHARED_PACKAGES[@]}" "${incomplete}"
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

		if [[ -n ${only_overlay} ]]; then
			read -r -a surplus <<<"${only_overlay}"
			n_overlay=$(( n_overlay + ${#surplus[@]} ))
			parity_row "${key}" "${PACKAGE_ROW_PV}" "${PACKAGE_ROW_PV}" \
				"${PACKAGE_ROW_DISTANCE}" 'files/overlay-only' \
				"${only_overlay}" ''
		fi
		if [[ -n ${only_gentoo} ]]; then
			read -r -a surplus <<<"${only_gentoo}"
			n_gentoo=$(( n_gentoo + ${#surplus[@]} ))
			parity_row "${key}" "${PACKAGE_ROW_PV}" "${PACKAGE_ROW_PV}" \
				"${PACKAGE_ROW_DISTANCE}" 'files/gentoo-only' \
				'' "${only_gentoo}"
		fi
		if [[ -n ${content_overlay} ]]; then
			parity_row "${key}" "${PACKAGE_ROW_PV}" "${PACKAGE_ROW_PV}" \
				"${PACKAGE_ROW_DISTANCE}" 'files/content' \
				"${content_overlay% }" "${content_gentoo% }"
		fi
	done

	printf '  [files]    %d package(s) with a files/ directory on some side: %d file(s) overlay-only, %d ::gentoo-only, %d same name and different content\n' \
		"${packages}" "${n_overlay}" "${n_gentoo}" "${n_content}"
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
	local line axis

	resolve_overlay_ebuild "${entry}" "${pn}"
	if [[ ! -f ${OVERLAY_EBUILD} ]]; then
		return 0
	fi

	while IFS= read -r line; do
		if [[ ${line} =~ ^[[:space:]]*#[[:space:]]*BENTOO-DIVERGENCE:[[:space:]]*([^[:space:]]+) ]]; then
			axis=${BASH_REMATCH[1]}
			PARITY_TAGGED_AXES["${entry}|${axis}"]=1
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
	check_stale_tags
	write_reports

	# The verdict lands here: non-zero when any package needs action.
	sweep_exit_code
}

### self-test ########################################################
#
# Everything --self-test writes: one copy of one ebuild, under $TMPDIR, removed
# again before it returns. No report, and nothing anywhere near either package
# tree - see prepare_tag_scratch for why the copy has to exist at all.

ASSERT_TOTAL=0
FAILURES=()

# The one ebuild A09 needs a tag on. Pinned rather than discovered: the
# assertion is about a specific hand-inspected divergence, so a version that
# moved on is a stale assertion to re-measure, not a lookup to make dynamic.
SELF_TEST_TAGGED_PKG='kde-plasma/spectacle'
SELF_TEST_TAGGED_PV='6.7.4'

# The filter A12 drives a whole sweep through. Pinned for the same reason: it
# names a category the overlay shares with ::gentoo and diverges from on
# nothing, which is the state a run has to survive and used not to.
#
# If a bump ever gives app-dicts a divergence this assertion goes red as a stale
# measurement - repin it on another clean category, never loosen it to accept a
# non-zero exit. A guard that cannot go green once remediation succeeds is a
# guard nobody re-runs.
SELF_TEST_CLEAN_FILTER='app-dicts'

# The scope A21 drives a whole sweep through, for story 008's R2.4. Pinned for
# the same reason as the two above: dev-ruby/erb is the tree's ONLY stale
# md5-cache entry (measured 2026-08-06, story 008's Task 1), so it is the one
# filter that produces a scope whose only observation is a stale cache and whose
# divergence row count is zero. That is the exact state R2.4 is about - the run
# must exit 0 having still reported something.
#
# If erb is ever regenerated with egencache the assertion goes red as a stale
# measurement: repin it on whichever entry is stale then, or retire it with the
# reason recorded. Never loosen it to accept a non-zero exit.
SELF_TEST_STALE_FILTER='dev-ruby/erb'

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
	local verdict

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

	GENTOO_REPO="${GENTOO_REPO}" PARITY_REPORT_DIR="${dir}" \
		bash -- "${BASH_SOURCE[0]}" "${SELF_TEST_STALE_FILTER}" \
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
	assert_eq A01 \
		'shared packages: the overlay packages ::gentoo also carries' \
		'234' "${#PARITY_SHARED_PACKAGES[@]}"

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
		'321' "${#PARITY_SCOPE_EBUILDS[@]}"

	# Paired with its denominator: 0/0 and 321/321 must not read alike.
	assert_eq A07 \
		'md5-cache coverage: an entry exists on both sides for every ebuild in scope' \
		'321/321' "${#PARITY_MD5_COVERED[@]}/${#PARITY_SCOPE_EBUILDS[@]}"

	# --- what each ebuild is compared against -------------------------

	assert_eq A03 \
		'exact-distance ebuilds: ::gentoo carries the same PV' \
		'76' "$(baselines_at_distance exact)"

	# The live-ebuild trap, and the reason this one carries a denominator:
	# including 9999 in the version sort made a first pass report 34 packages
	# as behind ::gentoo when none are. Zero behind out of zero baselines
	# selected is the bug looking exactly like the fix.
	assert_eq A06 \
		'packages behind ::gentoo: none, once live ebuilds leave the version sort' \
		'behind=0 baselines=321' \
		"behind=${#PARITY_BEHIND[@]} baselines=${#PARITY_BASELINES[@]}"

	# --- what the comparison concluded --------------------------------

	assert_eq A04 \
		'byte-identical ebuilds: cmp against the exact baseline agrees' \
		'67' "${#PARITY_IDENTICAL[@]}"

	assert_eq A05 \
		'REDUNDANT verdicts: one per byte-identical ebuild, its axis rows suppressed' \
		'67' "$(verdict_count REDUNDANT)"

	# PYTHON_COMPAT never reaches md5-cache under that name - python-any-r1
	# expands it into the BDEPEND any-of block - so at kwin-6.7.4 the only
	# trace is dev-lang/python:3.15, which ::gentoo requires and the overlay
	# does not (verified 2026-08-06; it is the ONLY md5-cache difference the
	# two copies have). Matched on the value rather than on an axis name so
	# the assertion survives whichever axis sub-task 3.3 files it under.
	assert_eq A08 \
		'kwin-6.7.4 PYTHON_COMPAT drift is ALIGN: the overlay is behind, not customised' \
		'ALIGN' "$(select_rows kde-plasma/kwin 6.7.4 '' dev-lang/python verdict)"

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
	# the normalisation must NOT suppress: mesa keeps ~amd64-linux and
	# ~x86-linux, which ::gentoo does not carry, and that survives ~ stripping
	# (verified 2026-08-06). No PV is pinned - mesa is bumped daily here.
	assert_eq A10 \
		'KEYWORDS: no row explainable by ~ alone, and mesa still reports its real one' \
		'false-positives=0 mesa-signal=KEYWORDS' \
		"false-positives=$(keywords_false_positives) mesa-signal=$(select_rows media-libs/mesa '' KEYWORDS '' axis)"

	# ::gentoo inherits cargo and flag-o-matic at this PV and the overlay
	# inherits neither: the overlay ebuild predates an upstream refactor made
	# at the same version. Matched on cargo appearing in the row's values, so
	# the assertion holds whether the stage reports the full INHERIT set or
	# only the delta.
	assert_eq A11 \
		'kdeplasma-addons-6.7.4 INHERIT divergence is detected: ::gentoo has cargo and flag-o-matic, the overlay neither' \
		'INHERIT' \
		"$(select_rows kde-plasma/kdeplasma-addons 6.7.4 INHERIT cargo axis)"

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
	assert_eq A13 \
		'SLOT: only the six structural rows survive, each named' \
		'rows=6 packages=dev-libs/imath dev-util/glslang net-libs/nodejs net-libs/webkit-gtk www-client/chromium' \
		"$(slot_survivors)"

	# THE ONE THAT MATTERS MOST, and the reason the component COUNT is
	# compared before derivability. The overlay drops nodejs's subslot
	# entirely, so a := dependency cannot rebuild on an ABI change - the most
	# valuable single finding the 007 sweep produced. "24" and "0/24" both
	# normalise to a placeholder-bearing form, so a rule that compares the
	# normalised forms without checking the count first calls them equal and
	# deletes the finding while looking like a success.
	#
	# Paired with redis, whose shape it must NOT be confused with: same axis,
	# same kind of value, opposite answer.
	assert_eq A14 \
		'SLOT: nodejs keeps its missing subslot where redis loses its version-only one' \
		'nodejs@24[compared=yes slot=ALIGN] nodejs@26[compared=yes slot=ALIGN] redis[compared=yes slot=none]' \
		"nodejs@24[$(slot_outcome net-libs/nodejs 24.19.0)] nodejs@26[$(slot_outcome net-libs/nodejs 26.7.0)] redis[$(slot_outcome dev-db/redis 8.10.0)]"

	# The shape findings.md's rule walks straight past: the version is the
	# SLOT, not the subslot. Paired with the two slots that are not versions
	# at all - a release channel and a genuinely different API generation -
	# because a rule aggressive enough to fold 5.5 into 5.4 must still not
	# fold stable into unstable.
	assert_eq A15 \
		'SLOT: a version in the slot itself goes; a named slot and a different slot stay' \
		'lua[compared=yes slot=none] blender[compared=yes slot=none] chromium[compared=yes slot=ALIGN] webkit-gtk[compared=yes slot=ALIGN]' \
		"lua[$(slot_outcome dev-lang/lua 5.5.1)] blender[$(slot_outcome media-gfx/blender 5.2.0)] chromium[$(slot_outcome www-client/chromium 151.0.7922.71)] webkit-gtk[$(slot_outcome net-libs/webkit-gtk 2.52.5-r411)]"

	# R1.2's revision case. ::gentoo carries binutils at PV 2.46.1-r1 and
	# its slot reads 2.46: derivability has to strip the -r1 and then accept
	# a component PREFIX, but only at a component boundary.
	#
	# Paired with the two subslots that merely LOOK like versions. imath's 30
	# and 29 are an ABI counter and glslang's 16.1 and 16.3 are a library
	# soname; neither derives from its own PV, and a rule that suppressed
	# them would hide that the overlay is BEHIND ::gentoo on glslang's
	# soname while ahead of it on the version.
	assert_eq A16 \
		'SLOT: a revision in the PV does not defeat derivability, and an ABI counter is not a version' \
		'binutils[compared=yes slot=none] binutils-libs[compared=yes slot=none] imath[compared=yes slot=ALIGN] glslang[compared=yes slot=ALIGN]' \
		"binutils[$(slot_outcome sys-devel/binutils 2.47)] binutils-libs[$(slot_outcome sys-libs/binutils-libs 2.47)] imath[$(slot_outcome dev-libs/imath 3.2.2)] glslang[$(slot_outcome dev-util/glslang 1.4.357.0_p20260806)]"

	# R1.5. A suppression nobody can audit is indistinguishable from a
	# comparison that silently broke, and telling those two apart is the
	# entire value of this axis now.
	#
	# Carried with the surviving row count, because "0 recorded, 0 with a
	# reason" is exactly what a script that never suppressed anything also
	# reports.
	assert_eq A17 \
		'SLOT: every suppressed row is recorded with a reason' \
		'recorded=10 with-reason=10 survivors=6' \
		"$(slot_suppression_record) survivors=$(slot_survivors_count)"

	# --- story 008: instrument error is not divergence ----------------

	# dev-ruby/erb reports a differing ruby-fakegem hash, and the overlay's
	# eclass/ holds no ruby-fakegem at all - there is no overlay copy that
	# COULD differ. The overlay's md5-cache entry was generated against an
	# older ::gentoo eclass. It is the instrument reporting itself, and it is
	# classified UNDOCUMENTED today, which asks a human to decide about a
	# measurement error.
	assert_eq A18 \
		'_eclasses_: erb is reported as a stale cache, not as a divergence' \
		'compared=yes row=none stale=ruby-fakegem' \
		"compared=$(in_md5_scope dev-ruby/erb 6.0.7) row=$(eclass_row_verdict dev-ruby/erb 6.0.7) stale=$(stale_cache_for dev-ruby/erb)"

	# THE CONVERSE, so the rule cannot be a blanket suppression of the axis.
	# The overlay ships three eclasses of its own; those are deliberate
	# overrides, recorded as definitionally divergent by story 007's R1.6,
	# and not one of them may be filed as a stale cache. Calling an override
	# a measurement error is the failure mode that would hide a real one.
	assert_eq A19 \
		'_eclasses_: an eclass the overlay ships stays an override, never a stale cache' \
		'definitional=brave gstreamer-meson rpm local-in-stale=0 stale=1' \
		"definitional=$(definitional_eclasses) local-in-stale=$(local_eclasses_in_stale) stale=${#PARITY_STALE_CACHE[@]}"

	# R2.2, as arithmetic. 472 rows less the ten SLOT artifacts less the one
	# reclassified _eclasses_ row is 461, and the four verdicts must still
	# sum to it: "a section of their own, excluded from the row count" means
	# the observation left the total rather than becoming a fifth verdict.
	#
	# This is the assertion most sensitive to the flap A02 describes: a single
	# ebuild arriving mid-bump moved it by eight. When it goes red, check the
	# two subtractions before the total - the ten and the one are what this
	# story changed, and an ebuild that moves the total moves neither.
	assert_eq A20 \
		'the four verdicts still sum to the row total, with the stale cache outside both' \
		'rows=461 verdict-sum=461 stale=1' \
		"$(row_arithmetic)"

	# --- story 008: what a stale cache does to the exit code ----------

	# R2.4. A scope whose only observation is the stale cache must exit 0:
	# there is nothing for a human to decide, and a guard that fails on its
	# own measurement error is a guard nobody re-runs. Today erb is
	# UNDOCUMENTED, so this scope exits 1.
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
	// stale. Both halves are asserted together, so a regression that silences
	# everything cannot pass either.
	assert_eq A24 \
		'a stale tag is reported at exact distance and NEVER at same-series' \
		'exact=stale same-series=silent' \
		"$(stale_tag_distance_run)"

	rm -rf -- "${scratch}"
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

	if (( ${#FAILURES[@]} == 0 )); then
		printf '\n%d assertions, all passed\n' "${ASSERT_TOTAL}"
		return 0
	fi

	printf '\n%d assertions, %d FAILED:\n' "${ASSERT_TOTAL}" "${#FAILURES[@]}"
	local failure
	for failure in "${FAILURES[@]}"; do
		printf '  - %s\n' "${failure}"
	done
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
