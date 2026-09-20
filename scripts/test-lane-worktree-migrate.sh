#!/bin/bash
# AF-336. lane-worktree-migrate.sh, exercised against a fully synthetic fixture
# — a temp repo standing in for a lane's shared checkout, with a fake `origin`
# remote (a bare temp repo) — never the real amux checkout or a real
# ~/.amux/sessions/*.env file. AMUX_SESSIONS_DIR points the script at a temp
# dir for the whole run.
set -euo pipefail

SRC_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$SRC_REPO/scripts/lane-worktree-migrate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

ok()   { printf '  ok   %s\n' "$*"; }
bad()  { printf '  FAIL %s\n' "$*" >&2; fail=1; }

# ── shared fixture: a bare "origin" and a clone standing in for a lane's ────
# shared checkout, plus a fake AMUX_SESSIONS_DIR so the script never touches
# a real lane's env file.
bare="$TMP/origin.git"
git init -q --bare -b main "$bare"
seed="$TMP/seed"
git init -q -b main "$seed"
git -C "$seed" config user.email t@example.com
git -C "$seed" config user.name  t
echo "hello" > "$seed/README.md"
mkdir -p "$seed/pkg"
echo "fn main() {}" > "$seed/pkg/main.rs"
git -C "$seed" add -A
git -C "$seed" -c core.hooksPath=/dev/null commit -qm seed
git -C "$seed" push -q "$bare" main

sessions_dir="$TMP/sessions"
mkdir -p "$sessions_dir"
export AMUX_SESSIONS_DIR="$sessions_dir"

new_lane_fixture() {
  # $1 = lane name, $2 = shared checkout dir to create for it
  local lane="$1" shared="$2"
  git clone -q "$bare" "$shared"
  git -C "$shared" config user.email t@example.com
  git -C "$shared" config user.name  t
  printf 'CC_DIR="%s"\n' "$shared" > "$sessions_dir/$lane.env"
}

# ── CASE A: happy path -- one tracked edit + one untracked file, both claimed ─
lane_a="lane-a"
shared_a="$TMP/shared-a"
new_lane_fixture "$lane_a" "$shared_a"
echo "changed" >> "$shared_a/pkg/main.rs"
echo "scratch" > "$shared_a/notes.txt"

dest_a="$TMP/dest-a"
out="$(bash "$SCRIPT" "$lane_a" --claim "pkg/main.rs,notes.txt" --dest "$dest_a" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
  bad "A: migration exited $rc"
  printf '%s\n' "$out" | sed 's/^/       /' >&2
else
  ok "A: migration exited 0"
fi
if [ -d "$dest_a/.git" ] || [ -f "$dest_a/.git" ]; then
  ok "A: destination worktree exists"
else
  bad "A: no worktree at $dest_a"
fi
a_dirty="$(git -C "$dest_a" status --porcelain --untracked-files=all 2>/dev/null | awk '{print $2}' | sort | tr '\n' ' ')"
if [ "$a_dirty" = "notes.txt pkg/main.rs " ]; then
  ok "A: new worktree's dirty set is exactly the claim: $a_dirty"
else
  bad "A: new worktree dirty set is '$a_dirty', expected 'notes.txt pkg/main.rs '"
fi
if grep -q "^changed$" "$dest_a/pkg/main.rs" 2>/dev/null; then
  ok "A: tracked edit content carried over"
else
  bad "A: tracked edit content missing in new worktree"
fi
if [ -f "$dest_a/notes.txt" ] && grep -q "^scratch$" "$dest_a/notes.txt"; then
  ok "A: untracked file content carried over"
else
  bad "A: untracked file missing/wrong in new worktree"
fi
# The original must be UNTOUCHED — this is the whole safety property.
orig_dirty_a="$(git -C "$shared_a" status --porcelain --untracked-files=all | sort)"
if printf '%s\n' "$orig_dirty_a" | grep -q "pkg/main.rs" && printf '%s\n' "$orig_dirty_a" | grep -q "notes.txt"; then
  ok "A: original shared checkout still carries both claimed paths (nothing deleted)"
else
  bad "A: original shared checkout lost a claimed path: $orig_dirty_a"
fi

# ── CASE B: an UNCLAIMED dirty path must refuse the whole run ────────────────
# THE LOAD-BEARING CASE. This is the incident class the script exists to
# prevent: a peer's in-flight file sitting in the same shared checkout.
lane_b="lane-b"
shared_b="$TMP/shared-b"
new_lane_fixture "$lane_b" "$shared_b"
echo "mine" >> "$shared_b/pkg/main.rs"
echo "not mine, a peer's WIP" > "$shared_b/README.md"  # left UNCLAIMED on purpose

dest_b="$TMP/dest-b"
if out_b="$(bash "$SCRIPT" "$lane_b" --claim "pkg/main.rs" --dest "$dest_b" 2>&1)"; then
  bad "B: migration SUCCEEDED with an unclaimed dirty path present — this is the incident class"
  printf '%s\n' "$out_b" | sed 's/^/       /' >&2
else
  if printf '%s' "$out_b" | grep -q "REFUSED"; then
    ok "B: migration refused with an unclaimed dirty path present"
  else
    bad "B: migration failed but not with REFUSED — wrong failure mode"
  fi
  if printf '%s' "$out_b" | grep -q "README.md"; then
    ok "B: refusal names the unclaimed path"
  else
    bad "B: refusal did not name README.md"
  fi
fi
if [ -e "$dest_b" ]; then
  bad "B: a destination worktree was created despite the refusal"
else
  ok "B: no destination worktree was created"
fi
# The peer's file must be untouched, and the claiming lane's OWN diff must
# ALSO still be sitting there -- a refusal must not roll anything back either.
if grep -q "^mine$" "$shared_b/pkg/main.rs" 2>/dev/null && [ -f "$shared_b/README.md" ]; then
  ok "B: both the claimed and unclaimed paths survive the refusal untouched"
else
  bad "B: the refusal path mutated the shared checkout"
fi

# ── CASE C: --dry-run touches nothing ────────────────────────────────────────
lane_c="lane-c"
shared_c="$TMP/shared-c"
new_lane_fixture "$lane_c" "$shared_c"
echo "dry" >> "$shared_c/pkg/main.rs"
dest_c="$TMP/dest-c"
bash "$SCRIPT" "$lane_c" --claim "pkg/main.rs" --dest "$dest_c" --dry-run >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && [ ! -e "$dest_c" ]; then
  ok "C: --dry-run exits 0 and creates nothing"
else
  bad "C: --dry-run rc=$rc, dest exists=$([ -e "$dest_c" ] && echo yes || echo no)"
fi

# ── CASE D: PRE-FIX behaviour (no --claim check at all) -- the discriminating
# control, same shape as test-install-hooks-worktree.sh's case B.
#
# The snapshot step only ever touches paths named in --claim, so removing the
# check does not make it SWEEP the peer's file into the new worktree (it
# structurally cannot: README.md is never in claimed_clean). What the check
# actually buys is the LOUD REFUSAL itself: without it, a caller who ran
# --claim naming only SOME of what is dirty gets a silent rc=0 with no
# indication that a peer's (or their own forgotten) file was left sitting in
# the shared checkout unaccounted for. That is the real hazard — a migration
# that LOOKS complete and is not — so D asserts the pre-fix path succeeds
# with no mention of the unclaimed file anywhere in its output.
sed '/# ── refuse to guess whose dirt is whose/,/^note "every dirty path/c\
note "PRE-FIX: claim check removed"' "$SCRIPT" > "$TMP/prefix.sh"
if grep -q 'PRE-FIX: claim check removed' "$TMP/prefix.sh" && ! grep -q 'REFUSED: %s has dirty paths not named' "$TMP/prefix.sh"; then
  lane_d="lane-d"
  shared_d="$TMP/shared-d"
  new_lane_fixture "$lane_d" "$shared_d"
  echo "mine" >> "$shared_d/pkg/main.rs"
  echo "a peer's WIP" > "$shared_d/README.md"
  dest_d="$TMP/dest-d"
  if out_d="$(bash "$TMP/prefix.sh" "$lane_d" --claim "pkg/main.rs" --dest "$dest_d" 2>&1)"; then
    if printf '%s' "$out_d" | grep -q "README.md"; then
      bad "D: pre-fix path mentioned the unclaimed file anyway — D proves nothing about the check's value"
    else
      ok "D: pre-fix path (no claim check) succeeds SILENTLY while README.md sits unclaimed and unmentioned -- case B's refusal is what surfaces this, not incidental"
    fi
  else
    bad "D: pre-fix path failed outright rather than silently succeeding -- inconclusive, but not the defect this pins"
  fi
else
  bad "D: mutation did not apply as expected — D proves nothing, fix the sed"
fi

# ── CASE E: --acknowledge-unclaimed, naming the unclaimed path EXACTLY, ─────
# proceeds -- the honest escape hatch, not a silent one.
lane_e="lane-e"
shared_e="$TMP/shared-e"
new_lane_fixture "$lane_e" "$shared_e"
echo "mine" >> "$shared_e/pkg/main.rs"
echo "a peer's WIP, acknowledged not mine" > "$shared_e/README.md"
dest_e="$TMP/dest-e"
if out_e="$(bash "$SCRIPT" "$lane_e" --claim "pkg/main.rs" --acknowledge-unclaimed "README.md" --dest "$dest_e" 2>&1)"; then
  ok "E: migration with a matching --acknowledge-unclaimed succeeds"
else
  bad "E: migration refused despite an exact --acknowledge-unclaimed match"
  printf '%s\n' "$out_e" | sed 's/^/       /' >&2
fi
e_dirty="$(git -C "$dest_e" status --porcelain --untracked-files=all 2>/dev/null | awk '{print $2}' | sort | tr '\n' ' ')"
if [ "$e_dirty" = "pkg/main.rs " ]; then
  ok "E: new worktree carries ONLY the claimed path, not the acknowledged one"
else
  bad "E: new worktree dirty set is '$e_dirty', expected only 'pkg/main.rs '"
fi
if [ -f "$shared_e/README.md" ] && grep -q "acknowledged not mine" "$shared_e/README.md"; then
  ok "E: the acknowledged (not-mine) file is untouched in the original checkout"
else
  bad "E: the acknowledged file was modified or removed from the original checkout"
fi

# ── CASE F: --acknowledge-unclaimed naming the WRONG path still refuses -----
# proves it is not a blanket "shut up and proceed" flag.
lane_f="lane-f"
shared_f="$TMP/shared-f"
new_lane_fixture "$lane_f" "$shared_f"
echo "mine" >> "$shared_f/pkg/main.rs"
echo "a peer's WIP" > "$shared_f/README.md"
dest_f="$TMP/dest-f"
if out_f="$(bash "$SCRIPT" "$lane_f" --claim "pkg/main.rs" --acknowledge-unclaimed "some/other/path.txt" --dest "$dest_f" 2>&1)"; then
  bad "F: migration succeeded despite --acknowledge-unclaimed naming the WRONG path"
else
  if printf '%s' "$out_f" | grep -q "REFUSED" && printf '%s' "$out_f" | grep -q "README.md"; then
    ok "F: a mismatched --acknowledge-unclaimed still refuses and names the real unclaimed file"
  else
    bad "F: refused, but not with the expected REFUSED/README.md shape"
  fi
fi
if [ -e "$dest_f" ]; then
  bad "F: a destination worktree was created despite the refusal"
else
  ok "F: no destination worktree created"
fi

# ── CASE G: EMPTY --claim on a tree already clean for this lane ─────────────
# The documented common case ("omit entirely when the tree is already clean")
# and the one path none of A-F exercised. bash 3.2 + `set -u` treats a
# zero-element array specially: `"${arr[@]}"` is an unbound-variable error,
# and the naive fix `"${arr[@]:-}"` is WORSE inside a `for` loop -- it does
# not avoid the crash by iterating zero times, it iterates ONCE with an empty
# string, which downstream (`git status -- ""`) is "fatal: empty string is
# not a valid pathspec". Caught live piloting this on a real lane with
# nothing of its own to claim. The fix is the double-expansion idiom already
# used elsewhere in this repo (scripts/reap-amux-debris.sh) --
# `${arr[@]+"${arr[@]}"}` -- which is what this case pins.
lane_g="lane-g"
shared_g="$TMP/shared-g"
new_lane_fixture "$lane_g" "$shared_g"
# tree is clean: no edits, nothing untracked.
dest_g="$TMP/dest-g"
if out_g="$(bash "$SCRIPT" "$lane_g" --dest "$dest_g" 2>&1)"; then
  ok "G: empty --claim on a clean tree exits 0"
else
  bad "G: empty --claim on a clean tree failed"
  printf '%s\n' "$out_g" | sed 's/^/       /' >&2
fi
g_dirty="$(git -C "$dest_g" status --porcelain --untracked-files=all 2>/dev/null | wc -l | tr -d ' ')"
if [ "$g_dirty" = "0" ]; then
  ok "G: new worktree is clean, nothing phantom-claimed"
else
  bad "G: new worktree has $g_dirty unexpected dirty path(s)"
fi

[ "$fail" -eq 0 ] && echo "lane-worktree-migrate suite: PASS" || echo "lane-worktree-migrate suite: FAIL" >&2
exit "$fail"
