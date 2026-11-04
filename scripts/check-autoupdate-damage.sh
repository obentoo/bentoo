#!/usr/bin/env bash
# Assert that the autoupdate applier did not rewrite more than it was asked to.
#
#     scripts/check-autoupdate-damage.sh [--staged] [--all]
#
# The applier does a textual pass over each record it bumps. Twice this month
# that pass reached past its target, and both times the damage was invisible at
# review: the file still parses, the ebuild still sources, pkgcheck stays clean,
# and the failure surfaces days later somewhere else entirely.
#
# CLASS 1 -- a deleted `enabled = false`.
#   Some records are pinned OFF on purpose. dev-libs/icu-compat and
#   media-libs/libjxl-compat exist only to carry an old ABI for
#   www-client/orion-bin, and both derive SLOT from the version. Bumping one
#   does not update it, it ERASES the slot orion-bin depends on. On 2026-08-12
#   (b165e5745) the applier deleted both lines; the symptom arrived 12 days
#   later as `there are no ebuilds to satisfy "dev-libs/icu-compat:77"`.
#   8dd837928 restored them and wrote the check down; the applier did it again
#   the same day.
#
#   Two different things wear `enabled = false`, and only one is a pin. A record
#   disabled because the package LEFT the overlay also carries
#   `disabled_by = "auto"` -- 95 of the 99 do. When such a package comes back,
#   clearing both lines is the documented, correct move, and counting the line
#   called that damage: on 2026-08-25 this check refused the commit re-adding
#   net-im/telegram-desktop, whose record had been auto-disabled when 7.0.9 was
#   dropped in 7cbe62f54. So it no longer counts; it pairs each cleared pin
#   against `disabled_by` and against the tree:
#
#     cleared, never had disabled_by  -> damage: a manual ABI pin, always
#     cleared, disabled_by kept       -> damage: half-cleared, the record probes
#                                       an upstream the overlay does not ship
#     both cleared, no ebuild staged  -> damage: re-enabled for a package that
#                                       did not actually come back
#     both cleared, ebuild present    -> the package returned; this is the point
#
#   The four manual pins carry no `disabled_by`, so the first rule covers them
#   exactly as the counting version did.
#
# CLASS 2 -- a 40-hex literal clobbered with EGIT_COMMIT.
#   app-editors/zed pins seven vendored git dependencies by commit, each a
#   different upstream. The applier rewrites every 40-hex string in the ebuild,
#   not just the EGIT_COMMIT= line, so all seven end up holding the zed commit.
#   Those values are the left-hand side of the sed that turns `git = {…rev=X}`
#   into `path = {…}`; with the wrong SHA the sed matches nothing, exits 0, and
#   the `|| die` never fires. cargo then needs the network in a sandbox that has
#   none. Five occurrences in six bumps.
#
#   The check is not zed-specific and must not become so: an ebuild references
#   its own commit as ${EGIT_COMMIT} everywhere after the assignment, so the
#   literal appearing twice is the signature of the damage, whatever the package.
#
# Exit: 0 clean · 1 damage found · 2 usage or environment problem.

set -euo pipefail

# Derived from this script's own location, not the caller's cwd: the checks
# belong to THIS repository, and resolving them against wherever the caller
# happens to stand would silently check something else and pass.
REPO="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
STAGED="no"
SCOPE="changed"
FOUND=0

usage() {
	printf 'usage: %s [--staged] [--all]\n' "${0##*/}" >&2
	exit 2
}

for arg in "$@"; do
	case "${arg}" in
	--staged) STAGED="yes" ;;
	--all) SCOPE="all" ;;
	-h | --help) usage ;;
	*)
		printf 'unknown option: %s\n' "${arg}" >&2
		usage
		;;
	esac
done

_diff() {
	if [[ "${STAGED}" == "yes" ]]; then
		git -C "${REPO}" diff --cached "$@"
	else
		git -C "${REPO}" diff "$@"
	fi
}

# _blob <path> — the content about to be committed, which is the index when
# --staged and the working tree otherwise. Reading the wrong one would let a
# hook pass on a file whose staged revision still carries the damage.
_blob() {
	local path="$1"
	if [[ "${STAGED}" == "yes" ]]; then
		git -C "${REPO}" show ":${path}" 2>/dev/null || true
	else
		cat "${REPO}/${path}" 2>/dev/null || true
	fi
}

# --- class 1 ---------------------------------------------------------------

# _records <before|after> — one `name<TAB>enabled_false<TAB>has_disabled_by` line
# per record. A grep would be shorter and wrong: `comments = """ … """` is free
# text, and a block quoting a record header or an `enabled = false` line would
# be read as one. The scanner tracks the fence and ignores what is inside it.
_records() {
	local content
	if [[ "$1" == "before" ]]; then
		content="$(git -C "${REPO}" show 'HEAD:.autoupdate/packages.toml' 2>/dev/null || true)"
	else
		content="$(_blob .autoupdate/packages.toml)"
	fi
	printf '%s\n' "${content}" | awk '
		function fences(s,   n) { n = 0; while (match(s, /"""/)) { n++; s = substr(s, RSTART + 3) } return n }
		!inblk {
			if ($0 ~ /^\[".*"\]$/) { rec = substr($0, 3, length($0) - 4); order[++k] = rec; en[rec] = 0; db[rec] = 0 }
			else if (rec != "" && $0 ~ /^enabled[ \t]*=[ \t]*false[ \t]*$/) en[rec] = 1
			else if (rec != "" && $0 ~ /^disabled_by[ \t]*=/) db[rec] = 1
		}
		{ if (fences($0) % 2) inblk = !inblk }
		END { for (i = 1; i <= k; i++) printf "%s\t%d\t%d\n", order[i], en[order[i]], db[order[i]] }
	'
}

# Reads the index under --staged, the tree otherwise — the same revision _blob
# reads. A package returning in THIS commit is only in the index.
_has_ebuild() {
	# A record key may carry an "@label" (dev-build/automake@1.19): the label
	# names a series inside the package, never a directory, so strip it.
	local cp=${1%%@*}
	if [[ "${STAGED}" == "yes" ]]; then
		[[ -n "$(git -C "${REPO}" ls-files --cached -- "${cp}/*.ebuild")" ]]
	else
		compgen -G "${REPO}/${cp}/*.ebuild" >/dev/null
	fi
}

# The backticks below quote field names for a human reader; single quotes are
# what keeps them literal, so SC2016 is the intended state, not a warning.
# shellcheck disable=SC2016
check_enabled_false() {
	local -A was_off=() had_by=()
	local rec en db bad=0 ok=0

	while IFS=$'\t' read -r rec en db; do
		[[ -n "${rec}" ]] || continue
		((en)) && { was_off["${rec}"]=1; had_by["${rec}"]="${db}"; }
	done < <(_records before)

	while IFS=$'\t' read -r rec en db; do
		[[ -n "${rec}" && -n "${was_off[${rec}]:-}" ]] || continue
		((en == 0)) || continue

		if [[ "${had_by[${rec}]}" == "0" ]]; then
			printf 'FAIL  packages.toml: %s lost `enabled = false` and never had `disabled_by`\n' "${rec}"
			printf '        that pin is manual and permanent: the record carries an old ABI\n'
			printf '        another package depends on, and re-enabling it erases that SLOT.\n'
			printf '        Restore with: git checkout -- .autoupdate/packages.toml\n'
			bad=1
		elif ((db)); then
			printf 'FAIL  packages.toml: %s lost `enabled = false` but kept `disabled_by`\n' "${rec}"
			printf '        the two are written and cleared together; half-cleared, the record\n'
			printf '        probes an upstream the overlay does not ship.\n'
			bad=1
		elif ! _has_ebuild "${rec}"; then
			printf 'FAIL  packages.toml: %s was re-enabled but ships no ebuild\n' "${rec}"
			printf '        `disabled_by = "auto"` is cleared when the package comes BACK; with\n'
			printf '        no ebuild the probe files pendings for something absent.\n'
			bad=1
		else
			((++ok))
		fi
	done < <(_records after)

	if ((bad)); then
		FOUND=1
		return 0
	fi
	if ((ok)); then
		printf 'ok    packages.toml: %s record(s) re-enabled, each with an ebuild back in tree\n' "${ok}"
	else
		printf 'ok    packages.toml: no pinned record was re-enabled\n'
	fi
}

# --- class 2 ---------------------------------------------------------------

# ACMR, not ACM: every applier bump lands as a RENAME (foo-1.2.ebuild ->
# foo-1.3.ebuild, similarity 96-100%), so a filter without R prints "ebuilds:
# none in scope" on exactly the commits this check exists for -- a silent pass,
# not a clean one. Observed on the 2026-08-24 bump: ten renamed ebuilds, none
# examined.
_ebuild_list() {
	if [[ "${SCOPE}" == "all" ]]; then
		git -C "${REPO}" ls-files '*.ebuild'
	else
		_diff --name-only --diff-filter=ACMR -- '*.ebuild'
	fi
}

check_commit_literals() {
	local -a ebuilds=()
	mapfile -t ebuilds < <(_ebuild_list)
	if ((${#ebuilds[@]} == 0)); then
		printf 'ok    ebuilds: none in scope\n'
		return 0
	fi

	local path content commit count bad=0
	for path in "${ebuilds[@]}"; do
		content="$(_blob "${path}")"
		[[ -n "${content}" ]] || continue
		commit="$(printf '%s' "${content}" | sed -n 's/^EGIT_COMMIT="\([0-9a-f]\{40\}\)".*/\1/p' | head -n 1)"
		[[ -n "${commit}" ]] || continue
		count="$(printf '%s' "${content}" | grep -c "${commit}" || true)"
		((count > 1)) || continue
		printf 'FAIL  %s: EGIT_COMMIT literal appears %s times, expected 1\n' "${path}" "${count}"
		printf '%s' "${content}" | grep -n "${commit}" | grep -v '^[0-9]*:EGIT_COMMIT=' |
			sed 's/^/        /' | head -n 12
		printf '        re-derive those from GIT_CRATES, not from EGIT_COMMIT\n'
		bad=1
	done

	if ((bad == 0)); then
		printf 'ok    ebuilds: %s checked, no clobbered commit literal\n' "${#ebuilds[@]}"
		return 0
	fi
	FOUND=1
}

# --- main ------------------------------------------------------------------

check_enabled_false
check_commit_literals

if ((FOUND == 0)); then
	exit 0
fi
printf '\nautoupdate damage found — see the lines marked FAIL\n'
exit 1
