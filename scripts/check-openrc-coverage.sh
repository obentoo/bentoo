#!/usr/bin/env bash
# Copyright 2026 Lucas C.S. and bentoo contributors
# SPDX-License-Identifier: MIT
#
# Report every package that installs a systemd unit without the matching
# OpenRC init script.
#
# WHAT IT IS FOR
#
# bentoo targets OpenRC boxes as much as systemd ones, but nothing in the tree
# enforces that. A package can install a .service and no init script, pass
# pkgcheck, merge cleanly, and leave the daemon simply unstartable on an OpenRC
# host - a gap that only surfaces when a user tries to run the thing. This
# script is the missing check. It classifies every package on one dimension -
# does it install a unit, and if so does it install the OpenRC counterpart at
# the SAME SCOPE - and names each gap.
#
# The criterion, stated once:
#
#   a SYSTEM unit (/usr/lib/systemd/system) pairs with /etc/init.d
#   a USER   unit (/usr/lib/systemd/user)   pairs with /etc/user/init.d
#
# The two scopes carry different severities. A missing system init script is a
# FAIL and drives the exit code: system init scripts are universal in this tree
# and their absence is a plain defect. A missing user-scope script is a WARN,
# printed and counted but not fatal: the user-scope pattern has exactly one
# precedent here (sys-apps/xdg-desktop-portal) and NONE in ::gentoo, so failing
# a build over it would be asserting a convention that does not yet exist.
#
# STRICTLY READ-ONLY
#
# It reads ebuild text and prints a report. It writes no file, creates no
# directory, touches no Manifest or metadata, and never runs git, portage or a
# build. A guard that edits what it measures is not a measurement.
#
# HOW IT CLASSIFIES
#
# By reading the highest-version ebuild of each package - comments stripped and
# elog/ewarn prose skipped, since both talk about these calls without making
# them - and looking for four things:
#
#   1. the install functions, matched as whole words: systemd_dounit,
#      systemd_newunit, systemd_douserunit, systemd_newuserunit,
#      systemd_install_serviced, newinitd, doinitd
#   2. the unit directory handed to a build system, where no install call ever
#      names the unit: systemd_get_systemunitdir, systemdsystemunitdir,
#      SYSTEMD_SERVICES_INSTALL_DIR, systemd-user-unit-dir,
#      systemd_get_userunitdir
#   3. a user-scope script installed as a plain file: exeinto into
#      /etc/user/init.d, then doexe/newexe
#   4. the reviewed allowlist below - a policy exclusion, printed with its
#      reason, never a silent filter
#
# Classification is on the DESTINATION PATH, never on a filename. A vendor
# payload dumped under /opt can carry a .service file (app-backup/duplicati-bin,
# media-sound/audacity-bin, mail-client/betterbird-bin all do) and it is inert
# there, because systemd does not read /opt. Matching "*.service" as a filename
# would count those, and would also count D-Bus activation files, which are not
# units at all (kde-plasma/kameleon-qmk-helper ships one).
#
# WHY EBUILD TEXT AND NOT metadata/md5-cache OR A BUILD
#
# md5-cache was evaluated as the index and rejected: the entry for a package
# that demonstrably installs a unit (metadata/md5-cache/www-misc/warsaw-2.21.5.1)
# carries INHERIT, DEFINED_PHASES, RESTRICT, SRC_URI, LICENSE and KEYWORDS, and
# no field records an installed unit or init script. Building all 318 packages
# and inspecting ${D} would be exact, and a guard that needs 318 builds is not
# a guard.
#
# WHAT THIS STILL MISSES - stated here rather than discovered later
#
#   * a unit that appears only after an upstream bump changes the payload, or
#     that a meson/cmake default starts installing on its own. Text cannot see
#     either; only a build can.
#   * anything installed by a helper sourced from files/.
#   * prose that is not on an elog/ewarn line. A heredoc body - readme.gentoo's
#     DOC_CONTENTS is the usual one - can name newinitd in running text and be
#     read as an install. Measured: no heredoc in this tree does, and every
#     occurrence of a detected token today is a real call.
#   * an init script installed as a plain file via `exeinto /etc/init.d` plus
#     doexe. No package in this tree uses that idiom (measured: zero), so no
#     detector is carried for it; the user-scope twin exists because
#     sys-apps/xdg-desktop-portal actually does it.
#   * the unit-side twin of the above: `insinto /usr/lib/systemd/system` (or
#     /usr/lib/systemd/user) plus doins/newins, bypassing the systemd_* helpers
#     entirely. Same false-negative shape, same measured justification - zero
#     users in this tree - but it fails in the DANGEROUS direction: a package
#     using it ships a unit the guard cannot see, so it reads as clean. The
#     exeinto twin above fails the safe way, by hiding an init script that
#     exists. Add a detector the day the first package uses it.
#   * USE flags. A unit installed under `if use systemd` counts as installed,
#     because the question is whether the package CAN put a unit on disk with
#     no OpenRC counterpart - not whether one particular profile does.
#   * eclasses that install services on the package's behalf. Only
#     apache-2.eclass and nginx.eclass do this in ::gentoo and bentoo inherits
#     neither, so this is a checked non-concern rather than an assumption.
#
# The guard narrows the window. It does not close it.
#
# USAGE
#
#   bash scripts/check-openrc-coverage.sh                  # whole overlay
#   bash scripts/check-openrc-coverage.sh sci-ml           # one category
#   bash scripts/check-openrc-coverage.sh sci-ml/lemonade  # one package
#   bash scripts/check-openrc-coverage.sh --self-test      # assertions only
#   bash scripts/check-openrc-coverage.sh -h
#
# A row is printed when the package carries a finding, or whenever a filter was
# given. An unfiltered run is a guard: its job is to name gaps, and 300-odd
# PASS/n-a rows would bury the handful that matter. A filter is a question about
# named packages, and the answer has to be printed even when it is PASS. The
# summary counts every package scanned either way, so nothing is invisible.
#
# Exit status:
#   0  every selected package classified, no system-scope gap. Warnings may be
#      present: a user-scope gap is reported without failing the run
#   1  at least one system-scope gap
#   2  a precondition or a usage error, i.e. NOTHING WAS COMPARED. The third
#      code is the important one: an empty report reads exactly like a clean
#      one, and that confusion is what it exists to prevent

set -euo pipefail

# Every glob below lists a package directory. An unmatched pattern must expand
# to nothing rather than to itself: a directory holding no .ebuild is precisely
# how a non-package is recognised, and the literal string "…/*.ebuild" would be
# counted as one ebuild instead of none.
shopt -s nullglob

### where things live ################################################

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
OVERLAY_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)

# Top-level directories that are part of the repository but hold no package.
# The structural rule below (a package is a directory holding at least one
# ebuild) already excludes them; naming them here makes the count of "scanned"
# honest and keeps metadata/md5-cache - which has one subdirectory per category
# and would otherwise be walked in full - out of the loop entirely.
NON_PACKAGE_TOPLEVEL=( metadata profiles scripts licenses eclass )

### the reviewed allowlist ###########################################
#
# A POLICY exclusion, and only that. It is never a place to put a package the
# classifier finds hard: an entry here suppresses a real finding forever, so
# each one is a decision someone made and signed, recorded with the reasoning
# that justified it.
#
# The counter-example is worth keeping in view. net-misc/rustdesk-bin LOOKS
# like a candidate - it does `cp -a etc usr "${ED}"/` and its payload contains
# a .service file - and it is not one. That .service sits at
# usr/share/rustdesk/files/systemd/, where systemd never looks, and the unit
# that really gets installed goes through an explicit systemd_dounit that pass 1
# already catches. Allowlisting it would suppress a package the classifier
# handles correctly AND make its genuine gap permanently unreportable.
declare -A ALLOWLIST=(
	[sys-apps/flatpak]=$'its units are a Type=oneshot updater plus a timer, not a daemon: there\nis nothing to supervise, and an init script wrapping a one-shot would\nshow up as crashed in rc-status. The two files are byte-identical to\n::gentoo\'s. The honest OpenRC analogue is a cron.daily drop-in, which\nwould add a virtual/cron dependency to a package that has none.'
	[sys-power/upower]=$'its unit is D-Bus activated, not supervised: upower.service is\nType=dbus with BusName=org.freedesktop.UPower, and the package installs\n/usr/share/dbus-1/system-services/org.freedesktop.UPower.service. The\nactivating process is dbus-daemon, which OpenRC systems run too, so the\ndaemon already starts on demand there -- with no init script and no\nsystemd. Adding one would not close a gap, it would open a second start\npath racing the bus activation for the same well-known name.\nThe ebuild is byte-identical to ::gentoo\'s upower-1.91.3 (bentoo mirrors\nit one release ahead), and ::gentoo ships no init script either, so there\nis no downstream decision here to correct.'
	[dev-util/sysprof]=$'its unit is D-Bus activated, not supervised: sysprof3.service is\nType=dbus with BusName=org.gnome.Sysprof3, and the package installs the\nmatching org.gnome.Sysprof3.service system bus activation file. dbus-daemon\nstarts sysprofd on demand on OpenRC too, so an init script would only add a\nsecond start path racing the bus activation, as with sys-power/upower.\nGNOME 51 mirror (2026-10-03); ::gentoo ships no init script either.'
	[dev-util/sysprof-capture]=$'a false positive of the classifier: the ebuild passes\n-Dsystemdunitdir only because meson.build reads the option, but it also\npasses -Dsysprofd=none, so no unit is built or installed -- the unit lives in\ndev-util/sysprof, which is allowlisted above for its own reason.'
	[app-accessibility/at-spi2-core]=$'its user unit is D-Bus activated: at-spi-dbus-bus.service is\nType=dbus with BusName=org.a11y.Bus, and the package installs the\norg.a11y.Bus session bus activation file. The session bus starts it on demand\nunder OpenRC; a user init script would race that activation.\nGNOME 51 mirror (2026-10-03); ::gentoo ships none either.'
	[gnome-base/gvfs]=$'every user unit is D-Bus activated: gvfs-daemon, gvfs-metadata and\nthe five volume monitors are all Type=dbus with a BusName, each paired with an\norg.gtk.vfs.*.service session bus activation file the package installs. The\nsession bus starts them on demand under OpenRC.\nGNOME 51 mirror (2026-10-03); ::gentoo ships none either.'
	[gnome-base/gnome-session]=$'its user units are the systemd flavour of the GNOME session\nitself (gnome-session-manager@, -monitor, -signal-init, -restart-dbus). The\nOpenRC flavour is a separate package by design: gnome-base/gnome-session-openrc\n(the session leader plus its user-scope OpenRC scripts), which this ebuild\nRDEPENDs on under !systemd. The counterpart exists; it lives one package over.'
	[gnome-base/gdm]=$'its system unit is covered by gui-libs/display-manager-init, which\nthis ebuild RDEPENDs on unconditionally (bentoo addition, 2026-10-03):\nDISPLAYMANAGER=gdm in /etc/conf.d/display-manager plus rc-update add\ndisplay-manager starts gdm under OpenRC. KNOWN GAP, kept visible here on\npurpose: the user unit gnome-headless-session@.service (remote headless login,\nsee net-misc/gnome-remote-desktop) has no OpenRC equivalent.'
	[app-admin/system-config-printer]=$'its unit is a udev-triggered template, not a daemon:\nconfigure-printer@.service runs udev-configure-printer add once per plugged\nUSB printer, started through SYSTEMD_WANTS in 70-printers.rules. An init\nscript cannot stand in for a per-device template. Without systemd the add\ntrigger does not fire (the remove rule uses RUN and still works), exactly as\nin ::gentoo; closing that would take an extra udev rule, not an init script.\nCarried only as a python3_15 mirror (2026-11-04).'
	[sys-auth/polkit]=$'its unit is D-Bus activated, not supervised: polkit.service has\nBusName=org.freedesktop.PolicyKit1, and the package installs\n/usr/share/dbus-1/system-services/org.freedesktop.PolicyKit1.service with\nExec=/usr/lib/polkit-1/polkitd. dbus-daemon starts polkitd on demand on\nOpenRC too, so an init script would only race the bus activation, as for\nupower. Carried as a python3_15 copy, bumped past ::gentoo to 128 on 2026-11-04.'
	[media-video/pipewire]=$'its system unit is built only with USE=system-service, which\n::gentoo ties to systemd (REQUIRED_USE system-service? ( systemd )): the\nsystem-wide mode cannot be selected without systemd at all. The normal\nper-user mode is covered by its /etc/user/init.d scripts, which the\nclassifier sees. Carried only as a python3_15 mirror (2026-11-04).'
	[media-video/wireplumber]=$'its system unit is built only with USE=system-service, which\n::gentoo ties to systemd (REQUIRED_USE system-service? ( systemd )), exactly\nas for pipewire. The per-user session manager is covered by its\n/etc/user/init.d script. Carried only as a python3_15 mirror (2026-11-04).'
	[net-wireless/bluez]=$'its user unit is D-Bus activated: obex.service is Type=dbus with\nBusName=org.bluez.obex, and the package installs the org.bluez.obex session\nbus activation file, so the session bus starts obexd on demand without\nsystemd. The system daemon has its init script. Carried only as a python3_15\nmirror (2026-11-04).'
)

### command line #####################################################

SELF_TEST=0
FILTER=""

usage() {
	printf 'Usage: check-openrc-coverage.sh [--self-test] [<category>|<category>/<package>]\n'
	printf '\n'
	printf 'Classify every package on the service dimension: a systemd unit with no\n'
	printf 'OpenRC init script at the same scope. System-scope gaps FAIL (exit 1),\n'
	printf 'user-scope gaps WARN (exit unchanged).\n'
	printf '\n'
	printf 'Exit: 0 no system gap - 1 a system gap - 2 nothing was compared\n'
}

# validate_filter <argument>
# A filter is either <category> or <category>/<package>. Shape is checked here;
# whether it matches anything is the enumeration stage's business. Both checks
# matter for the same reason: a filter that quietly selects nothing produces an
# empty report, and an empty report reads exactly like a clean one.
validate_filter() {
	local filter=$1
	local atom='[A-Za-z0-9][A-Za-z0-9+_.-]*'

	if [[ ${filter} =~ ^${atom}(/${atom})?$ ]]; then
		return 0
	fi

	printf 'not a category or a category/package: %s\n' "${filter}" >&2
	printf 'expected <category> (sci-ml) or <category>/<package> (sci-ml/lemonade)\n' >&2
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

# Anything that would make the sweep compare nothing while still printing a
# clean-looking report. Each one exits 2, never 0.
check_preconditions() {
	local tool

	# A directory that exists but is not a package tree would classify every
	# package as absent and report a spotless overlay having read nothing.
	if [[ ! -f ${OVERLAY_ROOT}/profiles/repo_name ]]; then
		printf 'precondition failed: %s has no profiles/repo_name, so it is not a package tree\n' \
			"${OVERLAY_ROOT}" >&2
		return 2
	fi

	# awk does the comment stripping and sort -V picks the highest version.
	# Without either, every package would classify as carrying no unit - the
	# silent-pass shape this whole script exists to prevent.
	for tool in awk sort; do
		if ! command -v "${tool}" >/dev/null 2>&1; then
			printf 'precondition failed: required tool not found in PATH: %s\n' \
				"${tool}" >&2
			return 2
		fi
	done
}

### reading an ebuild ################################################

# strip_comments <path>
# The ebuild's text with every comment removed, one output line per input line
# so line numbers still refer to the real file.
#
# A comment starts at the first "#" that begins a word: at the start of the
# line, or immediately after whitespace. Nothing else is one. That distinction
# is load-bearing in both directions:
#
#   * ${var#prefix} carries a "#" that is NOT a comment. Cutting there would
#     delete whatever install call shares the line - a false negative, the
#     dangerous direction.
#   * a commented-out `#systemd_dounit foo` must not count as an install - a
#     false positive, which is how a guard loses its reader's trust.
strip_comments() {
	awk '
		{
			if ($0 ~ /^[ \t]*#/) { print ""; next }
			# match() finds the leftmost whitespace-then-# pair, which is the
			# first comment opener. RSTART is the whitespace itself, kept so
			# the preceding token still ends on a separator.
			if (match($0, /[ \t]#/)) { print substr($0, 1, RSTART); next }
			print
		}
	' "$1"
}

### the four detection passes ########################################
#
# Pass 1 matches WHOLE WORDS. A substring test is wrong here and would be wrong
# quietly: `grep -E 'systemd_dounit|newinitd'` misses doinitd (www-misc/warsaw),
# misses systemd_newuserunit (mail-mta/proton-mail-bridge), misses the whole
# build-system class of pass 2, and would have declared this overlay
# four-fifths clean. The boundaries also keep systemd_reenable, systemctl and
# any similarly-named future helper from standing in for an install call.
RE_SYS_UNIT_FN='(^|[^[:alnum:]_])(systemd_dounit|systemd_newunit|systemd_install_serviced)([^[:alnum:]_]|$)'
RE_USER_UNIT_FN='(^|[^[:alnum:]_])(systemd_douserunit|systemd_newuserunit)([^[:alnum:]_]|$)'
RE_INITD_FN='(^|[^[:alnum:]_])(newinitd|doinitd)([^[:alnum:]_]|$)'
RE_EXE_FN='(^|[^[:alnum:]_])(doexe|newexe)([^[:alnum:]_]|$)'
RE_EXEINTO='(^|[^[:alnum:]_])exeinto[[:space:]]+([^[:space:];]+)'

# A line whose first word is one of Gentoo's message functions is PROSE. It
# installs nothing, and its text routinely names the very calls this script
# looks for - `elog "on OpenRC, add one with newinitd foo"` is advice, not an
# init script. Word boundaries alone do not catch that: `newinitd` inside an
# elog IS a whole word, and counting it turns a package that ships a unit and
# no init script into a PASS. That is a false NEGATIVE, the direction that
# matters, and it was reproduced against a fixture before this filter existed.
#
# Measured against the tree: no ebuild in bentoo currently has any detected
# token on a message line, so this filter changes no verdict today. It exists
# so the first one that does is not silently absolved.
#
# `die` is here for the same reason and is safe: `newinitd x || die` starts
# with newinitd, not with die, and so is still read.
RE_MESSAGE_FN='^[[:space:]]*(elog|einfo|einfon|ewarn|eqawarn|eerror|ebegin|eend|ewend|die)([[:space:]]|$)'

# Pass 2 tokens are matched as plain substrings on purpose. They arrive spelled
# `-Dsystemdsystemunitdir=…` and `-DSYSTEMD_SERVICES_INSTALL_DIR="…"`, glued to
# the option prefix, so a word boundary in front would never match.
SYS_UNITDIR_TOKENS=( systemd_get_systemunitdir systemdsystemunitdir SYSTEMD_SERVICES_INSTALL_DIR )
USER_UNITDIR_TOKENS=( systemd-user-unit-dir systemd_get_userunitdir )

# Evidence for the four axes of the package being classified. Each holds
# "<line>: <what matched>" or the empty string. Evidence rather than a boolean
# because a FAIL has to name what it saw: "installs a unit" with no line number
# is an accusation, not a finding.
CLS_SYS_UNIT=""
CLS_USER_UNIT=""
CLS_SYS_INITD=""
CLS_USER_INITD=""

# classify_ebuild <path>
# Fill the four CLS_* variables from one ebuild.
classify_ebuild() {
	local path=$1
	local line token dest
	local lineno=0
	local exe_dest_scope=""

	CLS_SYS_UNIT=""
	CLS_USER_UNIT=""
	CLS_SYS_INITD=""
	CLS_USER_INITD=""

	while IFS= read -r line; do
		lineno=$(( lineno + 1 ))
		[[ -n ${line} ]] || continue

		# Prose first: an elog/ewarn line is advice about these calls, never
		# one of them. See RE_MESSAGE_FN.
		if [[ ${line} =~ ${RE_MESSAGE_FN} ]]; then
			continue
		fi

		# --- pass 1: install functions, whole words ------------------
		if [[ -z ${CLS_SYS_UNIT} && ${line} =~ ${RE_SYS_UNIT_FN} ]]; then
			CLS_SYS_UNIT="${lineno}: ${BASH_REMATCH[2]}"
		fi
		if [[ -z ${CLS_USER_UNIT} && ${line} =~ ${RE_USER_UNIT_FN} ]]; then
			CLS_USER_UNIT="${lineno}: ${BASH_REMATCH[2]}"
		fi
		if [[ -z ${CLS_SYS_INITD} && ${line} =~ ${RE_INITD_FN} ]]; then
			CLS_SYS_INITD="${lineno}: ${BASH_REMATCH[2]}"
		fi

		# --- pass 2: a unit directory handed to a build system -------
		# The unit is written by meson/cmake from this argument and no install
		# call ever names it, so pass 1 cannot see it. Three packages in this
		# tree are only visible here: net-misc/networkmanager,
		# net-misc/modemmanager and, at user scope,
		# sys-apps/xdg-desktop-portal.
		if [[ -z ${CLS_SYS_UNIT} ]]; then
			for token in "${SYS_UNITDIR_TOKENS[@]}"; do
				if [[ ${line} == *"${token}"* ]]; then
					CLS_SYS_UNIT="${lineno}: ${token}"
					break
				fi
			done
		fi
		if [[ -z ${CLS_USER_UNIT} ]]; then
			for token in "${USER_UNITDIR_TOKENS[@]}"; do
				if [[ ${line} == *"${token}"* ]]; then
					CLS_USER_UNIT="${lineno}: ${token}"
					break
				fi
			done
		fi

		# --- pass 3: a user-scope script installed as a plain file ----
		# exeinto sets the destination and doexe/newexe write into it, so the
		# scope lives on the exeinto line and the install on a later one. Track
		# the destination and classify on IT: this is the "destination path,
		# never a filename" rule applied to the OpenRC side.
		if [[ ${line} =~ ${RE_EXEINTO} ]]; then
			dest=${BASH_REMATCH[2]}
			dest=${dest//\"/}
			dest=${dest//\'/}
			if [[ ${dest} == *etc/user/init.d* ]]; then
				exe_dest_scope="user"
			else
				exe_dest_scope=""
			fi
		elif [[ -z ${CLS_USER_INITD} && ${exe_dest_scope} == "user" && ${line} =~ ${RE_EXE_FN} ]]; then
			CLS_USER_INITD="${lineno}: exeinto /etc/user/init.d + ${BASH_REMATCH[2]}"
		fi
	done < <(strip_comments "${path}")
}

### version selection ################################################

# version_sort_key <version>
# A version rewritten so `sort -V` orders it the way Gentoo does.
#
# GNU sort -V gives "~" a special rank: it sorts before everything, including
# the empty string. That is exactly the relation Gentoo gives its pre-release
# suffixes (1.15.0_pre < 1.15.0), which a raw sort -V gets backwards because
# "1.15.0" is a prefix of "1.15.0_pre". _p and -r go the other way and only
# need to stop being treated as letters.
#
# _pre is rewritten before _p, or _pre would become .pre and lose its rank.
version_sort_key() {
	local v=$1
	v=${v//_alpha/\~a}
	v=${v//_beta/\~b}
	v=${v//_pre/\~c}
	v=${v//_rc/\~d}
	v=${v//_p/.p}
	v=${v//-r/.r}
	printf '%s' "${v}"
}

# highest_version_ebuild <package-dir>
# The one ebuild that speaks for the package.
#
# R3.11: classify once per PACKAGE, not once per ebuild. Two packages here keep
# two versions on purpose - app-editors/zed-bin and app-office/libreoffice each
# carry a stable and a _pre - and a per-ebuild sweep reports both of them twice.
#
# Deliberately the shell glob plus sort -V rather than `ls | sort`: parsing ls
# is against this repo's shell conventions and shellcheck flags it (SC2012).
# The sort is the same sort.
highest_version_ebuild() {
	local dir=$1
	local pn=${dir##*/}
	local f base ver
	local -a ebuilds=( "${dir}"/*.ebuild )
	local -a keyed=()

	(( ${#ebuilds[@]} )) || return 1

	if (( ${#ebuilds[@]} == 1 )); then
		printf '%s' "${ebuilds[0]}"
		return 0
	fi

	for f in "${ebuilds[@]}"; do
		base=${f##*/}
		base=${base%.ebuild}
		ver=${base#"${pn}-"}
		keyed+=( "$(version_sort_key "${ver}")"$'\t'"${f}" )
	done

	# LC_ALL=C because this host is localised (pt_BR) and a collation rule that
	# reorders punctuation would pick a different "highest" version on one
	# machine than on another. A guard whose answer depends on $LANG is not a
	# guard. Byte order is the same everywhere; sort -V's numeric runs are the
	# part that has to be right, and they are locale-independent.
	printf '%s\n' "${keyed[@]}" | LC_ALL=C sort -t$'\t' -k1,1 -V | tail -n 1 | cut -f2-
}

### selection ########################################################

# filter_selects <category/pn>
# An empty filter selects everything, a filter with no slash names a whole
# category, one with a slash names a single package. Shape was already checked.
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

### the sweep ########################################################

# Rows are records: key, system verdict, user verdict, ebuild basename, then
# the four evidence fields. Collected rather than printed as they are produced
# so the rows, the allowlist and the summary can each get their own section
# while the tree is still walked exactly once.
#
# The separator is US (0x1f) and NOT a tab, for a reason that bites silently:
# tab is an IFS whitespace character, so `IFS=$'\t' read` collapses a run of
# tabs into one delimiter and drops leading and trailing ones. Four of the
# eight fields are routinely empty - a package with no user unit has no user
# evidence - and with tabs those empties vanish and every later field shifts
# left by one, so a WARN row would print its verdict against the wrong
# evidence. A non-whitespace separator delimits exactly once per occurrence.
# 0x1f cannot occur in ebuild text.
readonly FS=$'\x1f'

REPORT_ROWS=()
ALLOW_ROWS=()

SCANNED=0          # packages classified
UNIT_PACKAGES=0    # of those, packages installing a unit at either scope
FINDING_ROWS=0     # packages carrying at least one finding
SYS_FAIL=0         # findings: system-scope gaps
USER_WARN=0        # findings: user-scope gaps
SYS_PASS=0
USER_PASS=0
NO_EBUILD_DIRS=0   # package-shaped directories holding no ebuild

# sweep
# Walk the overlay, classify, fill the arrays and the counters. Returns 2 when
# nothing was classified, and never earlier than the end of the walk: stopping
# at the first finding hides the other ten (R3.5).
sweep() {
	local pkg_dir category pn key ebuild
	local sys user matched=0

	for pkg_dir in "${OVERLAY_ROOT}"/*/*/; do
		pkg_dir=${pkg_dir%/}
		pn=${pkg_dir##*/}
		category=${pkg_dir%/*}
		category=${category##*/}
		key="${category}/${pn}"

		# metadata/md5-cache and metadata/news match the */*/ glob and hold
		# hundreds of subdirectories between them. Skipping the known
		# non-package top levels by name is a shortcut, not the rule; the rule
		# is the ebuild test below.
		if [[ " ${NON_PACKAGE_TOPLEVEL[*]} " == *" ${category} "* ]]; then
			continue
		fi

		if ! filter_selects "${key}"; then
			continue
		fi

		# The definition of "package": a directory holding at least one ebuild.
		# A directory that looks like one and holds none (app-emulation/qemu is
		# in this state today, keeping only files/ and metadata.xml) is counted
		# and reported rather than passed over in silence - there is nothing to
		# classify there, and that is a fact about the tree, not a clean result.
		ebuild=$(highest_version_ebuild "${pkg_dir}") || {
			NO_EBUILD_DIRS=$(( NO_EBUILD_DIRS + 1 ))
			continue
		}

		matched=$(( matched + 1 ))
		SCANNED=$(( SCANNED + 1 ))

		classify_ebuild "${ebuild}"

		if [[ -z ${CLS_SYS_UNIT} ]]; then
			sys="n/a"
		elif [[ -n ${CLS_SYS_INITD} ]]; then
			sys="PASS"
		else
			sys="FAIL"
		fi

		if [[ -z ${CLS_USER_UNIT} ]]; then
			user="n/a"
		elif [[ -n ${CLS_USER_INITD} ]]; then
			user="PASS"
		else
			user="WARN"
		fi

		if [[ ${sys} != "n/a" || ${user} != "n/a" ]]; then
			UNIT_PACKAGES=$(( UNIT_PACKAGES + 1 ))
		fi

		local record
		record="${key}${FS}${sys}${FS}${user}${FS}${ebuild##*/}${FS}"
		record+="${CLS_SYS_UNIT}${FS}${CLS_USER_UNIT}${FS}"
		record+="${CLS_SYS_INITD}${FS}${CLS_USER_INITD}"

		# R3.4: an allowlisted package is classified first and excluded second,
		# and the report prints the verdict it WOULD have carried next to the
		# reason it does not count. An exclusion nobody can see is a blind spot
		# wearing a decision's clothes.
		if [[ -n ${ALLOWLIST[${key}]+set} ]]; then
			ALLOW_ROWS+=( "${record}" )
			continue
		fi

		[[ ${sys} == "PASS" ]] && SYS_PASS=$(( SYS_PASS + 1 ))
		[[ ${user} == "PASS" ]] && USER_PASS=$(( USER_PASS + 1 ))

		# Rows count packages, findings count findings, and the two differ:
		# sci-ml/lemonade-bin fails on both axes and is ONE row carrying TWO.
		local findings=0
		if [[ ${sys} == "FAIL" ]]; then
			SYS_FAIL=$(( SYS_FAIL + 1 ))
			findings=$(( findings + 1 ))
		fi
		if [[ ${user} == "WARN" ]]; then
			USER_WARN=$(( USER_WARN + 1 ))
			findings=$(( findings + 1 ))
		fi
		if (( findings > 0 )); then
			FINDING_ROWS=$(( FINDING_ROWS + 1 ))
		fi

		# Printed when it says something, or whenever the caller asked about
		# named packages. See the USAGE note in the header.
		if (( findings > 0 )) || [[ -n ${FILTER} ]]; then
			REPORT_ROWS+=( "${record}" )
		fi
	done

	if (( matched == 0 )); then
		if [[ -n ${FILTER} ]]; then
			printf 'filter %s matched no package under %s\n' \
				"${FILTER}" "${OVERLAY_ROOT}" >&2
		else
			printf 'no directory under %s holds an ebuild\n' "${OVERLAY_ROOT}" >&2
		fi
		printf 'nothing was classified, and an empty report reads exactly like a\n' >&2
		printf 'clean one\n' >&2
		return 2
	fi
}

### the report #######################################################

print_row() { # <record>
	local key sys user file su uu si ui

	IFS=${FS} read -r key sys user file su uu si ui <<<"$1"

	printf '%-38s  system=%-4s  user=%s\n' "${key}" "${sys}" "${user}"

	case ${sys} in
	FAIL)
		printf '    system unit installed at %s:%s\n' "${file}" "${su}"
		printf '    MISSING: an OpenRC init script in /etc/init.d (newinitd or doinitd)\n'
		;;
	PASS)
		printf '    system unit %s:%s, init script %s:%s\n' \
			"${file}" "${su}" "${file}" "${si}"
		;;
	esac

	case ${user} in
	WARN)
		printf '    user unit installed at %s:%s\n' "${file}" "${uu}"
		printf '    MISSING: a user-scope OpenRC script in /etc/user/init.d\n'
		printf '             (exeinto /etc/user/init.d, then newexe or doexe)\n'
		;;
	PASS)
		printf '    user unit %s:%s, user init script %s:%s\n' \
			"${file}" "${uu}" "${file}" "${ui}"
		;;
	esac
}

print_allow_row() { # <record>
	local key sys user file su uu si ui reason_line
	local lead='    reason: '

	IFS=${FS} read -r key sys user file su uu si ui <<<"$1"

	printf '%-38s  system=%-4s  user=%-4s  -> EXCLUDED\n' "${key}" "${sys}" "${user}"
	[[ -n ${su} ]] && printf '    system unit at %s:%s\n' "${file}" "${su}"
	[[ -n ${uu} ]] && printf '    user unit at %s:%s\n' "${file}" "${uu}"
	while IFS= read -r reason_line; do
		printf '%s%s\n' "${lead}" "${reason_line}"
		lead='            '
	done <<<"${ALLOWLIST[${key}]}"
}

print_report() {
	local record

	printf 'openrc-coverage  %s\n' "${OVERLAY_ROOT}"
	printf 'scope            %s\n' "${FILTER:-whole overlay}"
	printf '\n'

	printf '== Rows  (system gap = FAIL and drives the exit code; user gap = WARN and does not)\n\n'
	if (( ${#REPORT_ROWS[@]} == 0 )); then
		printf '(none)\n'
	else
		for record in "${REPORT_ROWS[@]}"; do
			print_row "${record}"
		done
	fi
	printf '\n'

	printf '== Allowlisted by policy  (classified, then excluded - never silently dropped)\n\n'
	if (( ${#ALLOW_ROWS[@]} == 0 )); then
		printf '(none)\n'
	else
		for record in "${ALLOW_ROWS[@]}"; do
			print_allow_row "${record}"
		done
	fi
	printf '\n'

	printf '== Summary\n\n'
	printf '  packages classified          %4d\n' "${SCANNED}"
	printf '    installing a unit          %4d\n' "${UNIT_PACKAGES}"
	printf '    system scope PASS          %4d\n' "${SYS_PASS}"
	printf '    user scope PASS            %4d\n' "${USER_PASS}"
	if (( NO_EBUILD_DIRS > 0 )); then
		printf '  directories with no ebuild   %4d  (nothing to classify)\n' "${NO_EBUILD_DIRS}"
	fi
	printf '  allowlisted                  %4d\n' "${#ALLOW_ROWS[@]}"
	printf '\n'
	# Rows and findings are different numbers and both are printed, because a
	# package can fail on both axes at once. Collapsing them would either list
	# such a package twice or lose its second finding.
	printf '  rows with a finding          %4d\n' "${FINDING_ROWS}"
	printf '  findings                     %4d   (%d system FAIL, %d user WARN)\n' \
		"$(( SYS_FAIL + USER_WARN ))" "${SYS_FAIL}" "${USER_WARN}"
	if (( FINDING_ROWS != SYS_FAIL + USER_WARN )); then
		printf '  %d row(s) carry more than one finding: a package can miss both scopes\n' \
			"$(( SYS_FAIL + USER_WARN - FINDING_ROWS ))"
	fi
	printf '\n'

	if (( SYS_FAIL > 0 )); then
		printf 'RESULT  FAIL  %d system-scope gap(s)' "${SYS_FAIL}"
		(( USER_WARN > 0 )) && printf ', %d user-scope warning(s)' "${USER_WARN}"
		printf '\n'
		return 1
	fi

	if (( USER_WARN > 0 )); then
		printf 'RESULT  PASS  no system-scope gap; %d user-scope warning(s) reported\n' \
			"${USER_WARN}"
		return 0
	fi

	printf 'RESULT  PASS  no gap in %d classified package(s)\n' "${SCANNED}"
	return 0
}

### self test ########################################################
#
# design.md's Testing Strategy, executable: numbered assertions with PINNED
# expected values, each pin carrying a comment saying what to do when it goes
# stale. This is what proves the classifier is right - above all on the classes
# that fail SILENTLY, where a wrong answer still prints a plausible row and
# nobody looks twice:
#
#   * the init script or unit that arrives in the UPSTREAM PAYLOAD instead of
#     from FILESDIR - www-misc/warsaw has no files/ directory at all (A01)
#   * the unit a build system writes from a directory argument, with no install
#     call ever naming it - net-misc/networkmanager, sys-apps/xdg-desktop-portal
#     (A02, A03)
#   * the .service file that is inert because of WHERE it lands, not what it is
#     called - app-backup/duplicati-bin (A04)
#   * the package that installs an init script and no unit, whose verdict is
#     character-for-character identical to a package that installs neither -
#     sci-ml/lemonade (A05)
#
# Two rules hold for every assertion below. Both are borrowed from
# scripts/gentoo-parity.sh, which learned them the hard way:
#
#   READ THE CLASSIFIER, NOT THE TREE. Every observed value comes from a real
#   sweep() over the real overlay, or from a real subprocess run of this script.
#   An assertion that grepped the ebuild itself would stay green with the whole
#   classifier deleted, which is worse than having no assertion at all.
#
#   NEVER PASS ON NOTHING. Every package pin leads with rows=1, so a package
#   that was renamed or dropped reads as rows=0 rather than silently comparing
#   two empty strings. And every verdict pin carries the EVIDENCE beside it,
#   because "system=n/a user=n/a" is what a package installing nothing prints
#   AND what sci-ml/lemonade - an init script and no unit - prints. The verdicts
#   are identical; only the evidence separates them.
#
# The overlay is bumped daily, so a pin going stale is expected and is not a
# defect. What must never happen is a stale pin met by WIDENING the assertion
# instead of explaining the delta. Five pins below are expected to move during
# this story and say so; a pin that moves without its comment predicting it is a
# regression, and that is the rule Task 5.1 applies.
#
# Measured against the tree on 2026-08-07.

ASSERT_TOTAL=0
FAILURES=()

# This script by absolute path. Three assertions re-invoke it as a subprocess
# and one of them copies it; both break if BASH_SOURCE is whatever relative path
# the caller happened to type.
SELF_TEST_SCRIPT="${SCRIPT_DIR}/${BASH_SOURCE[0]##*/}"

# The filter A13 drives a whole run through. Deliberately unspellable as a real
# category: an absent filter has to STAY absent for the assertion to mean
# anything, and a plausible name (net-misc/foo) is one `git add` away from
# existing and turning the assertion green for the wrong reason.
SELF_TEST_ABSENT_FILTER='zz-no-such-category/zz-no-such-package'

# Everything --self-test writes: one copy of this script and the captured output
# of three subprocess runs, all under $TMPDIR. Nothing anywhere near the overlay
# - the guard is read-only with respect to the tree it measures, and a self-test
# that edited an ebuild to exercise a branch would break that in the one place
# nobody reviews.
SELF_TEST_SCRATCH=""

# Removed on the way out whatever happens. `set -e` means an unexpected non-zero
# leaves the harness early, and a scratch directory removed only on the happy
# path is a scratch directory that accumulates.
cleanup_scratch() {
	if [[ -n ${SELF_TEST_SCRATCH} && -d ${SELF_TEST_SCRATCH} ]]; then
		rm -rf -- "${SELF_TEST_SCRATCH}"
	fi
	return 0
}

# q <value>
# Render a value for a report line: newlines flattened, empty made visible. A
# line that prints nothing is least readable exactly when the observed value IS
# the empty string, which is the commonest way for a pin to go wrong.
q() {
	local s=${1//$'\n'/ \\n }
	printf '%s' "${s:-(empty)}"
}

# assert_eq <id> <description> <expected> <actual>
# Never aborts. The value of this harness is the whole picture of what the
# classifier gets right and wrong; stopping at the first red hides the other
# thirteen. It is the same rule R3.5 puts on the sweep itself.
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

### querying the classifier ###########################################

# sweep_reset
# Put the sweep's accumulators back to their starting values, so the next
# sweep_one measures one package rather than that package plus every package
# measured before it.
sweep_reset() {
	REPORT_ROWS=()
	ALLOW_ROWS=()
	SCANNED=0
	UNIT_PACKAGES=0
	FINDING_ROWS=0
	SYS_FAIL=0
	USER_WARN=0
	SYS_PASS=0
	USER_PASS=0
	NO_EBUILD_DIRS=0
}

# sweep_one <category/pn>
# Run the REAL sweep scoped to one package, leaving its record in REPORT_ROWS.
#
# In-process on purpose: what is under test here is the classifier, and a
# subprocess would add a fork per assertion while proving nothing extra. The
# exit code is dropped because it is asserted separately and end to end
# (A12/A13/A14); what this helper publishes is the row.
#
# stderr goes to /dev/null so that a pin naming a package which no longer exists
# reports as rows=0 - one red line - instead of a paragraph of sweep prose
# interleaved with the assertion output.
sweep_one() {
	FILTER=$1
	sweep_reset
	sweep 2>/dev/null || true
}

# evidence_token <evidence field>
# The detector that fired, with its line number dropped, or "-" for none.
#
# The line number is deliberately NOT pinned. It moves on any bump that adds a
# line above the install call, which would put eleven assertions red over a
# change that altered no behaviour. The TOKEN is the thing under test: it is the
# whole difference between "the unit came from an install call" and "the unit
# came from a directory handed to meson", and between an init script that came
# from FILESDIR and one that came from the upstream payload.
evidence_token() {
	local e=${1#*: }
	printf '%s' "${e:--}"
}

# pkg_state <category/pn>
# Everything the classifier decided about one package, on one line:
#
#   rows=<n> system=<verdict> user=<verdict> \
#   sys-unit=<token> sys-initd=<token> user-unit=<token> user-initd=<token>
#
# rows= comes first so a package that vanished from the tree goes red on a fact
# rather than on two empty strings that happen to differ. An allowlisted package
# also reads rows=0, because the sweep files it under ALLOW_ROWS - correct, and
# worth knowing if one is ever added here.
pkg_state() {
	local key sys user file su uu si ui

	sweep_one "$1"

	if (( ${#REPORT_ROWS[@]} != 1 )); then
		printf 'rows=%d' "${#REPORT_ROWS[@]}"
		return 0
	fi

	IFS=${FS} read -r key sys user file su uu si ui <<<"${REPORT_ROWS[0]}"

	printf 'rows=1 system=%s user=%s sys-unit=%s sys-initd=%s user-unit=%s user-initd=%s' \
		"${sys}" "${user}" \
		"$(evidence_token "${su}")" "$(evidence_token "${si}")" \
		"$(evidence_token "${uu}")" "$(evidence_token "${ui}")"
}

# pkg_selection <category/pn>
# How many rows the package produced, and which ebuild spoke for it. The only
# helper that publishes a VERSION, because R3.11 is precisely the question of
# which of several versions gets picked - and the answer has to be wrong-able.
pkg_selection() {
	local key sys user file rest

	sweep_one "$1"

	if (( ${#REPORT_ROWS[@]} != 1 )); then
		printf 'rows=%d ebuild=-' "${#REPORT_ROWS[@]}"
		return 0
	fi

	IFS=${FS} read -r key sys user file rest <<<"${REPORT_ROWS[0]}"
	printf 'rows=1 ebuild=%s' "${file}"
}

### driving whole runs ################################################
#
# These three are SUBPROCESSES and have to be. What they assert is the exit CODE
# of a complete invocation, and a function called in this shell has no exit code
# of its own to observe - main() is the unit under test, not sweep(). They are
# also the only three assertions that exercise the script end to end.

# full_run <scratch dir>
# A whole unfiltered sweep, reported as
# "exit=<rc> rows=<n> findings=<n> allowlisted=<n>".
#
# All four parts are needed. exit=1 alone says a gap was found but not how many,
# and R3.5 is exactly the claim that the sweep keeps going instead of stopping
# at the first. rows and findings are different numbers on purpose -
# sci-ml/lemonade-bin is one row carrying two - so pinning either alone lets the
# other drift. allowlisted is here because a finding can always be made to
# disappear by ALLOWLISTING it, and a finding count that can be met by
# suppression is not a count.
full_run() {
	local out="${1}/full-run.txt"
	local rc=0 rows findings allowed

	bash -- "${SELF_TEST_SCRIPT}" >"${out}" 2>&1 || rc=$?

	rows=$(awk '/^  rows with a finding/ { print $NF }' "${out}")
	findings=$(awk '/^  findings / { print $2 }' "${out}")
	allowed=$(awk '/^  allowlisted/ { print $NF }' "${out}")

	printf 'exit=%d rows=%s findings=%s allowlisted=%s' \
		"${rc}" "${rows:--}" "${findings:--}" "${allowed:--}"
}

# no_match_run <scratch dir>
# A filter that selects nothing, reported as "exit=<rc> explained=<yes|no>".
#
# R3.8. Both halves are needed and the second one is the point: exit 2 with a
# silent stdout is still a run whose report is empty, and the sentence "filter X
# matched no package" is the only thing that separates an empty report from a
# clean one. An assertion on the code alone would stay green the day someone
# drops the explanation.
no_match_run() {
	local out="${1}/no-match.txt"
	local rc=0 explained=no

	bash -- "${SELF_TEST_SCRIPT}" "${SELF_TEST_ABSENT_FILTER}" >"${out}" 2>&1 || rc=$?

	if grep -qF -- 'matched no package under' "${out}"; then
		explained=yes
	fi

	printf 'exit=%d explained=%s' "${rc}" "${explained}"
}

# absent_root_run <scratch dir>
# The script run from somewhere that is not a package tree, reported as
# "exit=<rc> explained=<yes|no>".
#
# R3.3, and the only assertion that needs a fixture. OVERLAY_ROOT is derived
# from the script's own location, so the way to hand it a missing overlay is to
# put a COPY of the script where nothing sits beside it - no profiles/repo_name,
# no categories. The copy lives under $TMPDIR and dies with the scratch
# directory; the real tree is only ever read.
#
# This is the failure mode with no symptom of its own. A root with no packages
# in it classifies nothing, finds no gap, and would print RESULT PASS over an
# empty set - the exact confusion exit 2 exists to prevent. Only the
# precondition catches it, and only this assertion proves the precondition is
# still there.
#
# "Missing" and not "unreadable": chmod 000 is the other half of R3.3's wording
# and it is not testable here, because a self-test run as root would sail
# through it and report a green that means nothing.
absent_root_run() {
	local scratch=$1
	local root="${scratch}/not-a-package-tree"
	local copy="${root}/scripts/${SELF_TEST_SCRIPT##*/}"
	local out="${scratch}/absent-root.txt"
	local rc=0 explained=no

	mkdir -p -- "${root}/scripts"
	cp -- "${SELF_TEST_SCRIPT}" "${copy}"

	bash -- "${copy}" >"${out}" 2>&1 || rc=$?

	if grep -qF -- 'has no profiles/repo_name' "${out}"; then
		explained=yes
	fi

	printf 'exit=%d explained=%s' "${rc}" "${explained}"
}

### the fourteen assertions ###########################################

self_test_assertions() {
	SELF_TEST_SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/openrc-coverage-selftest.XXXXXX")
	trap cleanup_scratch EXIT

	printf 'openrc-coverage  --self-test\n'
	printf 'overlay          %s\n' "${OVERLAY_ROOT}"
	printf 'scratch          %s\n' "${SELF_TEST_SCRATCH}"
	printf '\n'

	# Probed, not enforced. Every pin below is a measurement of this overlay and
	# cannot be confirmed without it, so a broken root has to SAY so: fourteen
	# reds otherwise look like the classifier disagreeing with the numbers, when
	# in fact it never got to read anything.
	if ! check_preconditions 2>/dev/null; then
		printf '  [NOTE] %s is not a usable package tree\n' "${OVERLAY_ROOT}"
		printf '         every package pin below reads rows=0 and fails: that is a\n'
		printf '         missing precondition, not a disagreement with the numbers\n'
		printf '\n'
	fi

	printf 'assertions\n'

	# --- the classes that fail silently -------------------------------

	# R3.6, the payload class. www-misc/warsaw has NO files/ directory at all:
	# both halves of the pair arrive inside the upstream tarball and are
	# installed straight out of it, `systemd_dounit lib/systemd/system/
	# warsaw.service` and `doinitd etc/init.d/warsaw`. A classifier that looked
	# for an init script under FILESDIR - which is where every other package in
	# this tree keeps one - would call warsaw a FAIL and send someone to write a
	# script that already ships.
	#
	# WHEN IT GOES STALE: read the new ebuild before touching the pin. If a bump
	# drops either file from the payload this is a REAL finding, not a stale
	# measurement - the package genuinely lost half its pair. If upstream merely
	# moves the script into FILESDIR, repin sys-initd on newinitd and record
	# that the payload class then has no example left in this tree, which makes
	# the whole class untested rather than fixed.
	assert_eq A01 \
		'www-misc/warsaw: unit AND init script recognised from the upstream payload (R3.6)' \
		'rows=1 system=PASS user=n/a sys-unit=systemd_dounit sys-initd=doinitd user-unit=- user-initd=-' \
		"$(pkg_state www-misc/warsaw)"

	# R3.10, the build-system class. No install call in networkmanager's ebuild
	# ever names a .service: meson is handed a unit directory and writes the
	# units itself, so the only textual trace is the argument. Pass 1 cannot see
	# this package at all, and a guard without pass 2 would report the tree
	# four-fifths clean.
	#
	# WHEN IT GOES STALE: if the token changes (upstream renaming the meson
	# option, or the ebuild switching to systemd_dounit) repin it on whatever
	# the new evidence says AND check SYS_UNITDIR_TOKENS still covers the
	# spelling. A rename that nobody adds to that list turns this package
	# silently into system=n/a, which reads exactly like a package with no unit.
	#
	# SUBJECT MOVED ON 2026-09-18. The original subject was
	# net-misc/networkmanager, dropped from the overlay in commit 8b6bda20c;
	# the assertion then failed with rows=0 and had been failing since, which
	# is the worst reading available - a vanished subject says nothing about
	# the rule, so a red here meant "something", not "R3.10 regressed".
	# net-misc/modemmanager replaces it: same upstream family, same meson
	# unit-dir idiom, a single ebuild, and it produces exactly the token pair
	# below. Note the expected value pins TOKENS and not a version, so a
	# snapshot bump of modemmanager does not touch this pin.
	assert_eq A02 \
		'net-misc/modemmanager: unit seen through the meson unit-dir argument, initd through newinitd (R3.10)' \
		'rows=1 system=PASS user=n/a sys-unit=systemd_get_systemunitdir sys-initd=newinitd user-unit=- user-initd=-' \
		"$(pkg_state net-misc/modemmanager)"

	# R3.9, the user-scope pair, and the only one in the tree. The unit comes
	# from a meson argument and the OpenRC side is not an init-script helper at
	# all - it is `exeinto /etc/user/init.d` followed by newexe, two lines apart,
	# which means the SCOPE lives on one line and the install on another. This
	# is the single package that proves the two are correlated rather than
	# counted separately.
	#
	# WHEN IT GOES STALE: if xdg-desktop-portal stops shipping the user script,
	# this class loses its only example. Do not delete the assertion - repin it
	# on whichever package carries the pattern then (sci-ml/lemonade-bin after
	# Task 3.1, mail-mta/proton-mail-bridge after Task 3.2), or the exeinto
	# detector becomes untested code.
	assert_eq A03 \
		'sys-apps/xdg-desktop-portal: user unit paired with an exeinto /etc/user/init.d script (R3.9)' \
		'rows=1 system=n/a user=PASS sys-unit=- sys-initd=- user-unit=systemd-user-unit-dir user-initd=exeinto /etc/user/init.d + newexe' \
		"$(pkg_state sys-apps/xdg-desktop-portal)"

	# R3.12, classification on the DESTINATION PATH. duplicati-bin's payload
	# contains a .service file, and it is inert: it lands under /opt, where
	# systemd never looks. Matching "*.service" as a filename would count it and
	# invent a gap in a package that has none - and would do the same to
	# media-sound/audacity-bin and mail-client/betterbird-bin.
	#
	# This pin's expected value is all dashes, which is the weakest kind of
	# assertion, so read it together with A05: the two differ in exactly one
	# field, and that field is the whole of what "classify on the destination"
	# buys. Neither one means much alone.
	#
	# WHEN IT GOES STALE: if this ever reads system=FAIL, a filename matcher has
	# crept back in - fix the detector, never the pin. If duplicati-bin starts
	# installing a real unit, the row becomes a genuine finding and the pin
	# moves to another /opt package carrying a .service.
	assert_eq A04 \
		'app-backup/duplicati-bin: a .service under /opt is not a unit (R3.12)' \
		'rows=1 system=n/a user=n/a sys-unit=- sys-initd=- user-unit=- user-initd=-' \
		"$(pkg_state app-backup/duplicati-bin)"

	# The one-directional criterion, made visible. sci-ml/lemonade installs an
	# init script and NO unit, so its verdict is n/a and not PASS: the question
	# the guard asks is "a unit without its counterpart", and a package with no
	# unit has nothing to answer. That is correct and it is also indistinguishable
	# from A04 on the verdicts alone - both print system=n/a user=n/a. Only
	# sys-initd=newinitd separates "installs an init script" from "installs
	# nothing", which is why the evidence is pinned and not just the verdict.
	#
	# WHEN IT GOES STALE: if lemonade ever gains a unit this flips to PASS
	# (evidence unchanged) and that is the package improving, not a defect -
	# repin. If sys-initd ever reads "-" while the ebuild still has a newinitd,
	# the detector broke, and it broke in the silent direction.
	assert_eq A05 \
		'sci-ml/lemonade: an init script and no unit is n/a, not PASS - and not the same as installing nothing' \
		'rows=1 system=n/a user=n/a sys-unit=- sys-initd=newinitd user-unit=- user-initd=-' \
		"$(pkg_state sci-ml/lemonade)"

	# R3.11, one row per PACKAGE. app-editors/zed-bin deliberately keeps two
	# ebuilds side by side - a stable and a _pre - and a per-EBUILD sweep reports
	# it twice. The version is pinned as well as the count because picking the
	# wrong one of the two still yields exactly one row: only the basename shows
	# that _pre outranks 1.14.2, which a raw `sort -V` gets backwards (it ranks
	# "1.15.0_pre" above "1.15.0"). version_sort_key exists for that, and this
	# is the only assertion that can catch it regressing.
	#
	# WHEN IT GOES STALE: expected, and often - zed-bin is bumped weekly and the
	# _pre becomes a release. Repin on the new highest version. Before doing so,
	# confirm the newly-expected basename really IS the higher of the two by
	# Gentoo's ordering; a pin updated by copying the observed value is a pin
	# that would have accepted the wrong answer.
	#
	# REPINNED 2026-09-18, 1.15.0_pre -> 1.21.0_pre, the tree now holding
	# zed-bin-1.20.2 (stable) beside zed-bin-1.21.0_pre. The check the comment
	# above demands was actually run rather than assumed, because eyeballing
	# "_pre" is exactly how this pin would get repinned onto the wrong answer:
	#
	#   >>> from portage.versions import vercmp
	#   >>> vercmp('1.21.0_pre', '1.20.2')
	#   1
	#
	# i.e. the _pre really is the higher of the two here, and for the ordinary
	# reason (1.21 > 1.20) rather than through the _pre suffix. That makes this
	# a WEAKER instance of R3.11 than the one it replaces: when the two differ
	# only in the suffix (1.15.0_pre vs 1.15.0) a raw `sort -V` gets it
	# backwards and only version_sort_key saves it, whereas here even a naive
	# sort lands on the right file. Restore the strong form on the next bump
	# where the stable catches up to the _pre's base version.
	#
	# REPINNED 2026-11-05, 1.21.0_pre -> 1.28.0_pre (zed-bin-1.27.0 beside
	# zed-bin-1.28.0_pre); vercmp('1.28.0_pre', '1.27.0') == 1 was run, not
	# assumed. Still the weak form: the bases differ (1.28 > 1.27).
	assert_eq A06 \
		'app-editors/zed-bin: two ebuilds, one row, and the _pre outranks the release (R3.11)' \
		'rows=1 ebuild=zed-bin-1.28.0_pre.ebuild' \
		"$(pkg_selection app-editors/zed-bin)"

	# --- the five pins this story MOVED (all six predicted below) -----
	#
	# Each pin here fired red at the end of story 010 and was repinned to the
	# value its own PIN-ABOUT-TO-MOVE comment had predicted, character for
	# character. The comments are kept: they are what distinguishes a pin that
	# moved because the tree was fixed from one moved to match whatever the
	# script happened to print.

	# The dual-verdict format itself: ONE row carrying TWO findings.
	# sci-ml/lemonade-bin is the only package in the tree missing both scopes at
	# once, so it is the only one that can catch a report which collapses rows
	# into findings - a collapse that would either list it twice or lose its
	# second finding entirely.
	#
	# PIN ABOUT TO MOVE, by design. Tasks 2.3 and 3.1 add the system and the
	# user script, after which the observed value becomes
	#   rows=1 system=PASS user=PASS sys-unit=systemd_dounit sys-initd=newinitd
	#   user-unit=systemd_douserunit user-initd=exeinto /etc/user/init.d + newexe
	# and the pin is UPDATED to exactly that, this comment kept. Any OTHER move
	# - a detector that stopped firing, a verdict that changed with no ebuild
	# changing - is a regression. Task 5.1 tells the two apart by whether this
	# comment predicted it.
	assert_eq A07 \
		'sci-ml/lemonade-bin: one row carrying TWO scope verdicts - the dual-verdict format' \
		'rows=1 system=PASS user=PASS sys-unit=systemd_dounit sys-initd=newinitd user-unit=systemd_douserunit user-initd=exeinto /etc/user/init.d + newexe' \
		"$(pkg_state sci-ml/lemonade-bin)"

	# PIN ABOUT TO MOVE: Task 2.1 adds the init scripts, after which this reads
	# system=PASS with sys-initd=newinitd. Nothing else about the row changes.
	#
	# CAUTION for whoever repins it: system=PASS here does NOT prove R1.1. The
	# guard asks whether ntpd-rs has AN init script, not whether it has the TWO
	# its two daemons need - a single newinitd flips the verdict. R1.1 is proven
	# by Task 2.1's own build assertion and by nothing here.
	assert_eq A08 \
		'net-misc/ntpd-rs: the system unit is paired with an init script' \
		'rows=1 system=PASS user=n/a sys-unit=systemd_dounit sys-initd=newinitd user-unit=- user-initd=-' \
		"$(pkg_state net-misc/ntpd-rs)"

	# PIN ABOUT TO MOVE: Task 2.2 adds the init script, after which system=PASS
	# with sys-initd=newinitd.
	assert_eq A09 \
		'net-misc/rustdesk: the system unit is paired with an init script' \
		'rows=1 system=PASS user=n/a sys-unit=systemd_dounit sys-initd=newinitd user-unit=- user-initd=-' \
		"$(pkg_state net-misc/rustdesk)"

	# PIN ABOUT TO MOVE: Task 2.2 covers this package too, with the same script
	# as its source sibling - after which system=PASS, sys-initd=newinitd.
	#
	# Worth keeping separate from A09 rather than folding into it. rustdesk-bin
	# is the package the allowlist comment holds up as the counter-example: its
	# payload carries a .service under usr/share/rustdesk/files/systemd/ that
	# does NOT count, while the unit it really installs goes through an explicit
	# systemd_dounit that DOES. sys-unit=systemd_dounit is the assertion that
	# the classifier saw the second one and not the first.
	assert_eq A10 \
		'net-misc/rustdesk-bin: the installed unit counts, the one buried in the payload does not' \
		'rows=1 system=PASS user=n/a sys-unit=systemd_dounit sys-initd=newinitd user-unit=- user-initd=-' \
		"$(pkg_state net-misc/rustdesk-bin)"

	# R3.9's severity half: a user-scope gap is a WARN and leaves the exit code
	# alone. This package is the reason the exit contract has that asymmetry -
	# the user-scope pattern has one precedent in this tree and none in
	# ::gentoo, so failing a build over it would assert a convention that does
	# not exist yet. A12 pins the other half: this WARN is counted among the six
	# findings and the run still exits 1 only because of the four FAILs.
	#
	# PIN ABOUT TO MOVE: Task 3.2 adds the user-scope script on a revbump, after
	# which user=PASS and user-initd=exeinto /etc/user/init.d + newexe.
	assert_eq A11 \
		'mail-mta/proton-mail-bridge: the user unit is paired with a user-scope script' \
		'rows=1 system=n/a user=PASS sys-unit=- sys-initd=- user-unit=systemd_newuserunit user-initd=exeinto /etc/user/init.d + newexe' \
		"$(pkg_state mail-mta/proton-mail-bridge)"

	# --- what a whole run does ----------------------------------------

	# R3.5: the sweep does not stop at the first gap. Five rows and six findings
	# is the whole tree's current state (Task 1.3's Red evidence), and the two
	# numbers differ because A07's package carries two findings on one row.
	#
	# PIN ABOUT TO MOVE: once Tasks 2 and 3 land, this becomes
	# exit=0 rows=0 findings=0 allowlisted=1 - and allowlisted MUST still be 1.
	# A remediation that reached zero findings by growing the allowlist has
	# hidden the gaps rather than closed them, and that is the one way this
	# assertion can be met dishonestly.
	#
	# THE PIN MOVED TO 2 ON 2026-09-18, and this is the audit trail the warning
	# above demands, because growing the allowlist is the suspect move by
	# default. sys-power/upower-1.91.4 arrived (commit 43e3f0617) and turned
	# this red. It was allowlisted, NOT given an init script, on evidence taken
	# from the installed image rather than from ebuild text:
	#
	#   $ qfile /usr/lib/systemd/system/upower.service
	#   sys-power/upower: /usr/lib/systemd/system/upower.service
	#   $ qfile /usr/share/dbus-1/system-services/org.freedesktop.UPower.service
	#   sys-power/upower: /usr/share/dbus-1/system-services/org.freedesktop.UPower.service
	#   $ grep -E '^(Type|BusName)=' /usr/lib/systemd/system/upower.service
	#   Type=dbus
	#   BusName=org.freedesktop.UPower
	#
	# The one package installs both the unit and the D-Bus activation file, and
	# the unit is Type=dbus - so even under systemd the daemon is started by bus
	# activation, not by supervision. dbus-daemon does the identical thing on
	# OpenRC from the identical file. The daemon is therefore ALREADY startable
	# without systemd, which is the whole of what this guard exists to demand;
	# an init script would add a second start path racing the bus for the same
	# well-known name. No gap was hidden, because there was none to hide.
	#
	# Why the allowlist and not the classifier: the classifier reads ebuilds,
	# and nothing in upower's ebuild names the activation file - upstream's
	# meson install does. Teaching the classifier this class would mean reading
	# the built image, which it deliberately does not do.
	#
	# The standard for the NEXT entry is unchanged: prove from the image that
	# the unit is not a supervised daemon. "The classifier finds it hard" and
	# "the init script is inconvenient" remain non-reasons, and a pin moving to
	# 3 without this kind of block underneath it should be treated as the
	# dishonest case the warning above describes.
	#
	# WHEN IT GOES STALE OTHERWISE: a new package landing with a unit and no
	# init script makes this red. That is the guard WORKING, not a bad pin -
	# fix the package, then repin. Never widen it.
	# COVERAGE LOST WHEN THIS PIN MOVED, stated so nobody rediscovers it as a
	# surprise: while the expected value was 5 rows / 6 findings, A12 was also
	# the proof of R3.5 -- that a run keeps classifying past the first gap. A
	# clean tree cannot demonstrate that, so R3.5 is now covered only by the
	# code path, not by an assertion. Restoring it means asserting against a
	# synthetic multi-gap fixture rather than against the live overlay; that is
	# a deliberate follow-up, not something to fake by keeping a red pin.
	#
	# THE PIN MOVED TO 8 ALLOWLISTED + 1 WARN ON 2026-10-03, with the GNOME 51
	# mirror (49 packages taken over from ::gentoo, all previously out of this
	# guard's reach). Six entries were added, each with its reason in ALLOWLIST:
	# sysprof, at-spi2-core and gvfs (Type=dbus units paired with D-Bus
	# activation files -- the upower class), sysprof-capture (classifier false
	# positive: -Dsysprofd=none builds no unit), gnome-session (its OpenRC
	# counterpart is the separate gnome-session-openrc, an RDEPEND) and gdm
	# (display-manager-init, made an unconditional RDEPEND in the same change).
	#
	# THE EVIDENCE IS WEAKER THAN THE STANDARD ABOVE, and that is stated here
	# rather than hidden: it was read from the unit and .service.in files in the
	# release TARBALLS (Type=, BusName=, the paired activation file), not from
	# an installed image. The image could not be produced: these packages need
	# glib >= 2.89, which an unprivileged host cannot merge underneath them.
	# Re-verify with qfile on the first machine that merges the stack.
	#
	# The one finding left is REAL and deliberately not allowlisted:
	# net-misc/gnome-remote-desktop's user unit (the RDP server) has no D-Bus
	# activation file and no OpenRC script. gdm's headless-session user unit is
	# the same gap, recorded in gdm's ALLOWLIST text because the allowlist is
	# per package. Both are WARN (user scope), so the exit code stays 0.
	#
	# 13 since 2026-11-04: system-config-printer, polkit, pipewire, wireplumber
	# and bluez, all carried as python3_15 mirrors (reasons in their entries).
	assert_eq A12 \
		'a run with no system-scope gap exits 0 and prints the allowlist (was R3.5)' \
		'exit=0 rows=1 findings=1 allowlisted=13' \
		"$(full_run "${SELF_TEST_SCRATCH}")"

	# --- exit 2: nothing was compared ---------------------------------
	#
	# The two below are the only assertions in this story that observe exit 2,
	# and it is the code design.md calls the important one: an empty report reads
	# exactly like a clean one, so every path that compares NOTHING has to be
	# louder than a path that compared everything and found nothing wrong.

	# R3.8. A typo in a category name must not come back as a spotless overlay.
	#
	# WHEN IT GOES STALE: if this ever reads exit=0, someone made the empty
	# selection succeed - that is the defect, not the pin. If explained=no, the
	# code is right and the sentence that makes it actionable was dropped.
	assert_eq A13 \
		'a filter matching no package exits 2 and says so (R3.8)' \
		'exit=2 explained=yes' \
		"$(no_match_run "${SELF_TEST_SCRATCH}")"

	# R3.3. The same failure from the other end: not an empty selection but an
	# empty tree. Exercised on a COPY of this script under $TMPDIR, because
	# OVERLAY_ROOT is derived from the script's location and there is no other
	# way to give it a root without touching the real one.
	#
	# WHEN IT GOES STALE: exit=0 here means the precondition was removed or its
	# marker file changed name, and the guard will happily report RESULT PASS
	# over a tree it never read. Repin on the new marker; do not delete the
	# check.
	assert_eq A14 \
		'a root that is not a package tree exits 2 and says so (R3.3)' \
		'exit=2 explained=yes' \
		"$(absent_root_run "${SELF_TEST_SCRATCH}")"
}

# self_test
# The harness verdict. Exits 0 only when every assertion passed AND at least one
# ran: "0 assertions, all passed" is the single most misleading line a guard can
# print, and every way of reaching it - assertions not written yet, a helper that
# returned early - is a defect worth an exit code.
self_test() {
	local failure

	self_test_assertions

	if (( ASSERT_TOTAL == 0 )); then
		printf '\nthe self-test ran no assertions, so it proved nothing\n' >&2
		return 1
	fi

	if (( ${#FAILURES[@]} == 0 )); then
		printf '\n%d assertions, all passed\n' "${ASSERT_TOTAL}"
		return 0
	fi

	printf '\n%d assertions, %d FAILED:\n' "${ASSERT_TOTAL}" "${#FAILURES[@]}"
	for failure in "${FAILURES[@]}"; do
		printf '  - %s\n' "${failure}"
	done
	return 1
}

### main #############################################################

main() {
	local rc=0

	parse_args "$@" || rc=$?
	if (( rc != 0 )); then
		return 2
	fi

	if (( SELF_TEST )); then
		self_test
		return $?
	fi

	check_preconditions || return 2

	sweep || return 2

	print_report || return 1
	return 0
}

main "$@"
