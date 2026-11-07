#!/usr/bin/env bats
# bats file_tags=integration,resolution,cooldown
#
# Integration -- bentoo story 003 (autoupdate cooldown), sub-task 6.1.
# Requirements: R9.2, R9.3.
#
# Contract (design.md "bentoo overlay side"): `--staged` skips resolution
# when the only staged path under profiles/, layers/ or metadata/layout.conf
# is profiles/package.mask AND every changed line of it lies inside the
# managed block; it prints `skip: only the cooldown block changed`. Any other
# change resolves as today (profiles/package.mask is repo-wide: every layer,
# ~49 s measured).
#
# Every test works on scratch_repo (a private git copy of the working tree);
# the checkout is never staged. setup() enables an empty block in the
# scratch baseline, as the enablement commit (6.3) will.
#
# Hostile halves: the skip must not swallow a line that sits ONE line outside
# either marker, nor a change to a marker itself, nor another profile path
# staged in the same commit; and the converse -- differently shaped commits
# that ARE block-only (two hunks; the real bump commit with an ebuild and the
# unmask list) -- must still skip. Each "resolves" test first proves the skip
# fires on its block-only half, so a script that never skips cannot pass it.
#
# Every test name contains "cooldown" so `bats --filter cooldown` selects it.

load lib

SKIP_MSG='only the cooldown block changed'
MASK=profiles/package.mask

setup() {
  need_portage
  scratch_repo
  cat >>"$R/$MASK" <<'EOF'

# Autoupdate cooldown (story 003): bumps land masked for 7 days.
# BEGIN bentoo-cooldown format=1 days=7
# Managed by `bentoo overlay autoupdate`. Edit with `bentoo overlay cooldown`, never by hand.
# cooldown since=2026-11-01T00:00:00Z origin=autoupdate
=app-misc/cooldown-probe-a-1.0
# END bentoo-cooldown
EOF
  git -C "$R" add -- "$MASK"
  _git_commit -qm "enable the cooldown block"
}

# add_entry ATOM -- a new entry, inserted right before the END marker.
add_entry() {
  local f=$R/$MASK tmp
  tmp=$(mktemp -p "$BATS_TEST_TMPDIR")
  awk -v atom="$1" '
    /^# END bentoo-cooldown$/ {
      print "# cooldown since=2026-11-07T07:10:00Z origin=autoupdate"
      print "=" atom
    }
    { print }
  ' "$f" >"$tmp"
  mv -- "$tmp" "$f"
}

# drop_entry ATOM -- remove ATOM and the comment line above it.
drop_entry() {
  local f=$R/$MASK tmp
  tmp=$(mktemp -p "$BATS_TEST_TMPDIR")
  awk -v atom="=$1" '
    { line[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        if (line[i + 1] == atom) { i++; continue }
        print line[i]
      }
    }
  ' "$f" >"$tmp"
  mv -- "$tmp" "$f"
}

# insert_after PATTERN TEXT / insert_before PATTERN TEXT -- a line adjacent
# to a marker, i.e. one line OUTSIDE the block.
insert_after() {
  local f=$R/$MASK tmp
  tmp=$(mktemp -p "$BATS_TEST_TMPDIR")
  awk -v pat="$1" -v text="$2" '{ print } $0 ~ pat { print text }' "$f" >"$tmp"
  mv -- "$tmp" "$f"
}
insert_before() {
  local f=$R/$MASK tmp
  tmp=$(mktemp -p "$BATS_TEST_TMPDIR")
  awk -v pat="$1" -v text="$2" '$0 ~ pat { print text } { print }' "$f" >"$tmp"
  mv -- "$tmp" "$f"
}

stage_mask() { git -C "$R" add -- "$MASK"; }

# expect_skip -- the last run_staged skipped resolution, said why, quickly.
expect_skip() {
  status_is 0
  [[ $output == *"$SKIP_MSG"* ]] || {
    _dump "a block-only change did not skip resolution"
    return 1
  }
}

# expect_resolved -- the last run_staged resolved (exit 0) and did NOT skip.
expect_resolved() {
  [[ $output != *"$SKIP_MSG"* ]] || {
    _dump "the skip swallowed a change outside the cooldown block"
    return 1
  }
  status_is 0
}

# block_only_then -- stage a block-only change, prove it skips; the caller
# then adds the hostile change on top.
block_only_then() {
  add_entry app-misc/cooldown-probe-b-1.0
  stage_mask
  run_staged
  expect_skip
}

# --- R9.2: block-only changes skip ------------------------------------------

@test "cooldown R9.2 a staged change confined to the block skips resolution in under 10 s and says why" {
  add_entry app-misc/cooldown-probe-b-1.0
  stage_mask
  local t0=$SECONDS
  run_staged
  local took=$((SECONDS - t0))
  expect_skip
  [ "$took" -lt 10 ] || {
    echo "the skip took ${took}s; the point of it is not to resolve" >&2
    false
  }
  assert_tmp_clean
  # read-only against the tree it checks
  [ "$(git -C "$R" status --porcelain)" = "M  $MASK" ] || {
    git -C "$R" status --porcelain >&2
    false
  }
}

@test "cooldown R9.2 a lift plus an add (two hunks inside the block) still skips" {
  add_entry app-misc/cooldown-probe-b-1.0
  stage_mask
  _git_commit -qm "two entries"
  drop_entry app-misc/cooldown-probe-a-1.0
  add_entry app-misc/cooldown-probe-c-2.0
  stage_mask
  run_staged
  expect_skip
}

@test "cooldown R9.2 the real bump commit shape (new ebuild + unmask list + block) still skips" {
  local eb dir name
  eb=$(cd "$R" && git ls-files '*.ebuild' | head -n1)
  [ -n "$eb" ]
  dir=${eb%/*}
  name=${dir##*/}
  cp -- "$R/$eb" "$R/$dir/$name-99999.ebuild"
  mkdir -p "$R/.autoupdate"
  printf '# managed by bentoo overlay autoupdate\n=%s-99999\n' "${dir}" >"$R/.autoupdate/cooldown.unmask"
  add_entry "$dir-99999"
  git -C "$R" add -- "$MASK" "$dir/$name-99999.ebuild" .autoupdate/cooldown.unmask
  run_staged
  expect_skip
}

# --- R9.3: anything outside the block resolves as today ---------------------

# bats test_tags=slow
@test "cooldown R9.3 a line added right after END, with a block change, resolves (slow)" {
  block_only_then
  insert_after '^# END bentoo-cooldown$' '=app-misc/cooldown-probe-outside-1.0'
  stage_mask
  run_staged
  expect_resolved
}

# bats test_tags=slow
@test "cooldown R9.3 a line added right before BEGIN, with a block change, resolves (slow)" {
  block_only_then
  insert_before '^# BEGIN bentoo-cooldown' '=app-misc/cooldown-probe-outside-1.0'
  stage_mask
  run_staged
  expect_resolved
}

# bats test_tags=slow
@test "cooldown R9.3 removing the END marker is not a block-only change and resolves (slow)" {
  block_only_then
  sed -i '/^# END bentoo-cooldown$/d' "$R/$MASK"
  stage_mask
  run_staged
  expect_resolved
}

# bats test_tags=slow
@test "cooldown R9.3 another profile path staged beside a block-only change resolves (slow)" {
  block_only_then
  local f=profiles/features/games/package.use
  [ -f "$R/$f" ]
  printf '# probe: staged comment\n' >>"$R/$f"
  git -C "$R" add -- "$f"
  run_staged
  expect_resolved
}
