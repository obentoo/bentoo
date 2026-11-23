#!/usr/bin/env bash
# Refuse a commit carrying autoupdate damage or a broken profile composition.
#
# Thin on purpose: the checks live in scripts/check-autoupdate-damage.sh and
# scripts/check-profile-matrix.sh, which are versioned and reviewable. This
# file is not — .git/hooks is per-clone — so it must hold no logic worth
# reading.
#
# Install in a fresh clone with:
#   ln -sf ../../scripts/pre-commit-hook.sh .git/hooks/pre-commit
#
# Bypass, when you genuinely mean it: git commit --no-verify

set -euo pipefail
top=$(git rev-parse --show-toplevel)
worst=0

# Each check runs and its status is kept; the worst one blocks the commit.
# (No `exec`: it would replace this shell and nothing after it would run.)
rc=0
"$top/scripts/check-autoupdate-damage.sh" --staged || rc=$?
if ((rc > worst)); then worst=$rc; fi

# The profile matrix only when a path it judges is staged: every other commit
# stays as fast as before. A failing git must block, never read as "nothing
# staged".
if ! staged=$(git -C "$top" diff --cached --no-renames --name-only -- \
	profiles/ layers/ metadata/layout.conf); then
	printf 'pre-commit: git diff --cached failed\n' >&2
	exit 2
fi
if [ -n "$staged" ]; then
	rc=0
	"$top/scripts/check-profile-matrix.sh" --staged || rc=$?
	if ((rc > worst)); then worst=$rc; fi
fi

# The registry's own lint, only when packages.toml is staged. bentoo#104
# committed a field-order error that only a later `--lint --fix` caught.
# Without bentoolkit on PATH the check is reported as skipped, never as passed.
if ! registry=$(git -C "$top" diff --cached --no-renames --name-only -- \
	.autoupdate/packages.toml); then
	printf 'pre-commit: git diff --cached failed\n' >&2
	exit 2
fi
if [ -n "$registry" ]; then
	if command -v bentoo >/dev/null 2>&1; then
		rc=0
		bentoo overlay autoupdate --lint --overlay "$top" || rc=1
		if ((rc > worst)); then worst=$rc; fi
	else
		printf 'pre-commit: SKIP registry lint: bentoo (app-portage/bentoolkit) is not on PATH\n' >&2
	fi
fi

exit "$worst"
