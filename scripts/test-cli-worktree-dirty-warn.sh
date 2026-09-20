#!/usr/bin/env bash
# AF-927. CC_WORKTREE=1's cleanup paths (`amux start`'s stale-worktree sweep,
# `amux stop`, `amux rm`) all `git worktree remove --force` with no check —
# the flag that overrides git's own refusal to drop a dirty worktree. This
# pins the new `warn_if_worktree_dirty` helper.
#
# EXTRACTED, NOT SOURCED. amux's own comment claims tests can `source amux`
# to reach helper functions without CLI side effects; that claim is currently
# false (filed separately, AF-927's own card) — the file's mandatory AMUX-3891
# shape (`exit "$?"` as the literal last-but-one line, so a live-edited,
# constantly-invoked CLI never resumes a read at a shifted offset) means
# sourcing still hits that unconditional exit and kills the sourcing shell.
# Pulling just the one function's text into an isolated script sidesteps that
# without touching either invariant.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/amux"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0
fail() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }
pass() { echo "  ok: $*"; }

awk '/^warn_if_worktree_dirty\(\) \{/,/^}$/' "$CLI" > "$TMP/fn.sh"
if [[ ! -s "$TMP/fn.sh" ]]; then
  fail "could not extract warn_if_worktree_dirty() from $CLI -- has it been renamed or removed?"
  echo "cli-worktree-dirty-warn suite: FAIL ($fails)" >&2
  exit "$fails"
fi
# The real CLI always has these defined (colors, possibly empty on a non-tty)
# by the time any function runs; the extracted function alone does not, and
# this test runs under `set -u`. Used inside the sourced fn.sh, invisible to
# a linter that only sees this file.
YELLOW=""
RESET=""
# shellcheck disable=SC2034
export YELLOW RESET
# shellcheck source=/dev/null
source "$TMP/fn.sh"

# ── fixture: a real repo with a real linked worktree ─────────────────────────
repo="$TMP/repo"
git init -q -b main "$repo"
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name t
echo hello > "$repo/f.txt"
git -C "$repo" add -A
git -C "$repo" -c core.hooksPath=/dev/null commit -qm seed

wt="$TMP/wt"
git -C "$repo" worktree add -q --detach "$wt" HEAD

# ── A: a clean worktree produces no warning ──────────────────────────────────
out="$(warn_if_worktree_dirty "$wt" 2>&1)"
if [[ -z "$out" ]]; then
  pass "A: clean worktree -> no output"
else
  fail "A: clean worktree produced output: $out"
fi

# ── B: a dirty worktree (uncommitted edit) warns and names the file ─────────
echo "uncommitted change" >> "$wt/f.txt"
out="$(warn_if_worktree_dirty "$wt" 2>&1)"
if [[ -n "$out" ]] && [[ "$out" == *"f.txt"* ]]; then
  pass "B: dirty (tracked) worktree warns and names f.txt"
else
  fail "B: expected a warning naming f.txt, got: $out"
fi
git -C "$wt" checkout -- f.txt

# ── C: an untracked file also warns (git status --porcelain sees it too) ────
echo "scratch" > "$wt/untracked.txt"
out="$(warn_if_worktree_dirty "$wt" 2>&1)"
if [[ -n "$out" ]] && [[ "$out" == *"untracked.txt"* ]]; then
  pass "C: untracked file in the worktree also triggers the warning"
else
  fail "C: expected a warning naming untracked.txt, got: $out"
fi
rm -f "$wt/untracked.txt"

# ── D: a path that is not a worktree at all is a silent no-op, not an error ──
if out="$(warn_if_worktree_dirty "$TMP/does-not-exist" 2>&1)"; then
  if [[ -z "$out" ]]; then
    pass "D: nonexistent path -> silent no-op"
  else
    fail "D: nonexistent path produced output: $out"
  fi
else
  fail "D: nonexistent path exited non-zero, should be a quiet no-op"
fi

# ── E: every force-remove call site in the real CLI actually calls the guard,
# so E fails the day a new cleanup path is added without wiring it in, or an
# existing one is refactored and the call dropped silently.
# Excludes comment lines (`^[[:space:]]*#`) so a docstring mentioning either
# phrase -- like this very file's own source-guard comment a few lines above
# the first real call site -- cannot inflate either count.
force_remove_lines=$(grep -vE '^[[:space:]]*#' "$CLI" | grep -c 'worktree remove --force')
guarded_lines=$(grep -vE '^[[:space:]]*#' "$CLI" | grep -c 'warn_if_worktree_dirty')
# guarded_lines includes the function's own def + call sites, so it must be
# strictly more than the number of force-remove sites (>= sites + 1 def).
if [[ "$guarded_lines" -gt "$force_remove_lines" ]]; then
  pass "E: every force-remove call site ($force_remove_lines) has a matching warn_if_worktree_dirty call ($guarded_lines total incl. the definition)"
else
  fail "E: $force_remove_lines force-remove call site(s) but only $guarded_lines warn_if_worktree_dirty reference(s) (incl. definition) -- a call site is unguarded"
fi

git -C "$repo" worktree remove --force "$wt" 2>/dev/null || true

if [[ "$fails" -eq 0 ]]; then
  echo "cli-worktree-dirty-warn suite: PASS"
else
  echo "cli-worktree-dirty-warn suite: FAIL ($fails)" >&2
fi
exit "$fails"
