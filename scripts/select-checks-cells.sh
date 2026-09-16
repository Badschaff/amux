#!/usr/bin/env bash
# Which of checks.yml's test cells cover the files you are about to push.
#
# `.github/workflows/checks.yml` invokes ~93 `scripts/test-*.sh|.py` cells and
# `scripts/git-hooks/pre-push` invokes none of them: that hook is a
# cross-session push-safety guard, not a correctness gate. So GitHub is the only
# thing that runs them, 1-2h later. Five `CI red: checks` cards in four days
# (AMUX-4460, 4492, 4586, 4687, 4714) are that gap (AMUX-4716).
#
# THIS NEVER SAYS "ALL CLEAR", and that is the whole design. A selector over
# path references has recall well under 1, so a clean-looking verdict from it
# would be worse than no gate. Every run prints how many cells it could not
# reach, beside what it ran.
#
# SELECTION, measured 2026-09-16 over the 93 cells checks.yml actually invokes
# (comment lines excluded; counting them gave 94 and a false FAIL, see below):
#   58  name a repo path  (scripts/, crates/, .github/, e2e/)
#   42  invoke the `amux` CLI
#   17  do neither and are unreachable by any path signal
#   => 76/93 reachable, 82%
# A changed-path-to-test-NAME rule would have been worse and is why this matches
# on references instead: edef6523 changed `scripts/test-contended.sh`, whose
# covering cell is `scripts/test-test-receipt.sh`, a name that does not match.
# The reference does: that cell greps the literal path out of the file it tests.
#
# The 16 can declare themselves with a `# SUBJECT: <path>` line, which this
# reads. That is the second mechanism the selector cannot replace.
#
# Usage:
#   scripts/select-checks-cells.sh                 # vs origin/main
#   scripts/select-checks-cells.sh --base <ref>
#   scripts/select-checks-cells.sh --run           # run what was selected
#   scripts/select-checks-cells.sh --files a b c   # explicit paths
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

BASE=origin/main
RUN=0
FILES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE=$2; shift 2 ;;
    --run) RUN=1; shift ;;
    # Collects until the NEXT flag rather than the end of the line. It used to
    # take "$*" and break, which silently swallowed a trailing --run and made
    # the tool print a selection and then quietly not run it. A flag that is
    # accepted and ignored is worse than one that is rejected.
    --files) shift
             while [ $# -gt 0 ]; do
               case "$1" in --*) break ;; esac
               FILES="$FILES $1"; shift
             done ;;
    -h|--help) sed -n '1,33p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

WF=.github/workflows/checks.yml
[ -f "$WF" ] || { echo "no $WF" >&2; exit 2; }

# The population is what the WORKFLOW invokes, not what is on disk. Measured:
# 104 test scripts exist, 93 are invoked. Selecting from disk would report cells
# CI never runs, which reads as coverage that does not exist.
# COMMENT LINES ARE NOT INVOCATIONS. Dropping this filter counted
# `scripts/test-target-clause.sh` as a cell because the AF-346 comment block
# names it twice, and that harness is in scripts/fixtures/harness-wired-baseline.txt
# as deliberately unwired ("every cell compiles for real, so wiring it adds
# minutes to every lane's push"). The selector then ran it and reported a FAIL
# for something CI does not run, which is a false alarm from a tool whose entire
# job is not overstating what it covered.
CELLS=$(grep -v '^[[:space:]]*#' "$WF" | grep -oE 'scripts/test-[A-Za-z0-9_.-]+\.(sh|py)' | sort -u)
N_CELLS=$(printf '%s\n' "$CELLS" | grep -c .)

if [ -z "$FILES" ]; then
  FILES=$(git diff --name-only "$BASE"...HEAD 2>/dev/null)
fi
# Counted as WORDS, not lines. `--files a b c` builds one space-separated
# string while `git diff --name-only` yields one path per line, so a line count
# reported "changed files: 1" for three paths. A count that misreports its own
# input is the defect this tool exists to avoid in its own output.
N_FILES=$(printf '%s\n' $FILES | grep -c .)

# Cells no signal can reach, counted every run so the verdict carries its own
# recall rather than leaving the reader to assume it is 1.
blind=0; blind_list=""
for c in $CELLS; do
  [ -f "$c" ] || continue
  grep -qE '(scripts|crates|\.github|e2e)/[A-Za-z0-9_./-]+' "$c" 2>/dev/null && continue
  grep -qE '(^|[^a-zA-Z_./-])amux[ "]|AMUX_BIN|\$\(amux ' "$c" 2>/dev/null && continue
  grep -q '^# SUBJECT:' "$c" 2>/dev/null && continue
  blind=$((blind+1)); blind_list="$blind_list $c"
done

selected=""
for c in $CELLS; do
  [ -f "$c" ] || continue
  hit=""
  for f in $FILES; do
    [ -n "$f" ] || continue
    # -F: a path is a literal, and `.` in it must not act as a wildcard.
    if grep -qF -- "$f" "$c" 2>/dev/null; then hit=1; break; fi
    # A changed `amux` CLI selects every cell that invokes it.
    if [ "$f" = "amux" ] && grep -qE '(^|[^a-zA-Z_./-])amux[ "]|AMUX_BIN' "$c" 2>/dev/null; then hit=1; break; fi
    # A declared subject, for the cells no reference reaches.
    if grep -q "^# SUBJECT:.*$f" "$c" 2>/dev/null; then hit=1; break; fi
  done
  [ -n "$hit" ] && selected="$selected $c"
done
N_SEL=$(printf '%s\n' $selected | grep -c .)

echo "changed files:  $N_FILES (vs $BASE)"
echo "cells invoked by checks.yml: $N_CELLS"
echo "selected:       $N_SEL"
for c in $selected; do echo "   $c"; done
echo "UNREACHABLE by any signal: $blind of $N_CELLS cells. This run says nothing about them."
[ "$N_SEL" = 0 ] && echo "NOTE: nothing selected. That is not a pass; it means no cell references your changed paths."

[ "$RUN" = 1 ] || exit 0
[ "$N_SEL" = 0 ] && exit 0

fail=0; ran=0
for c in $selected; do
  ran=$((ran+1))
  if [ "${c##*.}" = py ]; then python3 "$c" >/dev/null 2>&1; rc=$?; else bash "$c" >/dev/null 2>&1; rc=$?; fi
  if [ "$rc" != 0 ]; then echo "FAIL $c (exit $rc)"; fail=$((fail+1)); else echo "pass $c"; fi
done
# Computed, and it carries what it did NOT cover, so it cannot read as all-clear.
echo "ran $ran, failed $fail, and $blind of $N_CELLS cells were unreachable by the selector"
[ "$fail" -eq 0 ] || exit 1
