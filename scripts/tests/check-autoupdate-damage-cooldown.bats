#!/usr/bin/env bats
# bats file_tags=cooldown
#
# Integration -- bentoo story 003 (autoupdate cooldown), sub-task 6.2.
# Requirement: R9.5 -- `check-autoupdate-damage.sh --staged` passes a commit
# that changes only the cooldown block (and its unmask list).
#
# The script is run from a private git repository holding a copy of it and a
# small synthetic registry, so the checkout is never staged and the verdict
# does not depend on the live packages.toml.
#
# Hostile half first: a cooldown-shaped commit that ALSO carries real damage
# (a manual `enabled = false` pin cleared) must still FAIL -- an allowance for
# the block must never hide the damage the script exists to catch. Then the
# benign shapes: a block-only commit, and the real bump commit (new ebuild,
# pin moved, block entry, unmask list).
#
# Every test name contains "cooldown" so `bats --filter cooldown` selects it.

bats_require_minimum_version 1.5.0

TREE=${BENTOO_TREE:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)}

setup() {
  R=$BATS_TEST_TMPDIR/repo
  mkdir -p "$R/scripts" "$R/profiles" "$R/.autoupdate" "$R/app-misc/cdmg-foo"
  cp -- "$TREE/scripts/check-autoupdate-damage.sh" "$R/scripts/"
  cat >"$R/.autoupdate/packages.toml" <<'EOF'
["app-misc/cdmg-foo"]
url = "https://example.org/foo/releases"
parser = "regex"
pattern = 'v([0-9.]+)'
version = "1.0"

["dev-libs/cdmg-abi-compat"]
enabled = false
url = "https://example.org/abi/releases"
parser = "regex"
pattern = 'v([0-9.]+)'
EOF
  cat >"$R/profiles/package.mask" <<'EOF'
# hand mask
=media-libs/sdl3-3.4.20

# BEGIN bentoo-cooldown format=1 days=7
# Managed by `bentoo overlay autoupdate`. Edit with `bentoo overlay cooldown`, never by hand.
# END bentoo-cooldown
EOF
  printf 'EAPI=8\nSLOT="0"\nKEYWORDS="~amd64"\n' >"$R/app-misc/cdmg-foo/cdmg-foo-1.0.ebuild"
  git -C "$R" init -q
  git -C "$R" add -A
  git -C "$R" -c user.name=bats -c user.email=bats@localhost -c commit.gpgsign=false \
    -c core.hooksPath=/dev/null commit --no-verify -qm baseline
}

# cooldown_bump -- stage the real autoupdate bump commit: new ebuild, pin
# moved, block entry, unmask list.
cooldown_bump() {
  cp -- "$R/app-misc/cdmg-foo/cdmg-foo-1.0.ebuild" "$R/app-misc/cdmg-foo/cdmg-foo-1.1.ebuild"
  sed -i 's/^version = "1.0"$/version = "1.1"/' "$R/.autoupdate/packages.toml"
  block_entry app-misc/cdmg-foo-1.1
  printf '# managed by bentoo overlay autoupdate\n=app-misc/cdmg-foo-1.1\n' >"$R/.autoupdate/cooldown.unmask"
  git -C "$R" add -- app-misc/cdmg-foo/cdmg-foo-1.1.ebuild .autoupdate/packages.toml \
    profiles/package.mask .autoupdate/cooldown.unmask
}

block_entry() {
  sed -i "/^# END bentoo-cooldown\$/i # cooldown since=2026-11-07T07:10:00Z origin=autoupdate\\n=$1" "$R/profiles/package.mask"
}

run_damage() {
  run bash "$R/scripts/check-autoupdate-damage.sh" --staged
}

@test "cooldown R9.5 a cooldown commit that also clears a manual pin still fails" {
  cooldown_bump
  sed -i '/^\["dev-libs\/cdmg-abi-compat"\]$/,/^$/{/^enabled = false$/d}' "$R/.autoupdate/packages.toml"
  git -C "$R" add -- .autoupdate/packages.toml
  run_damage
  [ "$status" -eq 1 ] || {
    printf 'status %s, want 1\n%s\n' "$status" "$output" >&2
    false
  }
  [[ $output == *"cdmg-abi-compat"* ]]
}

@test "cooldown R9.5 a block-only commit with its unmask list passes" {
  block_entry app-misc/cdmg-foo-1.0
  printf '# managed by bentoo overlay autoupdate\n=app-misc/cdmg-foo-1.0\n' >"$R/.autoupdate/cooldown.unmask"
  git -C "$R" add -- profiles/package.mask .autoupdate/cooldown.unmask
  run_damage
  [ "$status" -eq 0 ] || {
    printf 'status %s, want 0\n%s\n' "$status" "$output" >&2
    false
  }
}

@test "cooldown R9.5 the real bump commit (ebuild + pin + block + unmask list) passes" {
  cooldown_bump
  run_damage
  [ "$status" -eq 0 ] || {
    printf 'status %s, want 0\n%s\n' "$status" "$output" >&2
    false
  }
}

@test "cooldown R9.5 a lift commit (block entry removed, unmask emptied) passes" {
  cooldown_bump
  git -C "$R" -c user.name=bats -c user.email=bats@localhost -c commit.gpgsign=false \
    -c core.hooksPath=/dev/null commit --no-verify -qm bump
  sed -i '/^# cooldown since=2026-11-07T07:10:00Z origin=autoupdate$/d; /^=app-misc\/cdmg-foo-1.1$/d' "$R/profiles/package.mask"
  printf '# managed by bentoo overlay autoupdate\n' >"$R/.autoupdate/cooldown.unmask"
  git -C "$R" rm -q -- app-misc/cdmg-foo/cdmg-foo-1.0.ebuild
  git -C "$R" add -- profiles/package.mask .autoupdate/cooldown.unmask
  run_damage
  [ "$status" -eq 0 ] || {
    printf 'status %s, want 0\n%s\n' "$status" "$output" >&2
    false
  }
}
