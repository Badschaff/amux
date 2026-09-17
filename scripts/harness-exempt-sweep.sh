#!/usr/bin/env bash
# Run the recorded-unwired harnesses that CAN be run, and name the ones that
# cannot (AMUX-4747).
#
# WHY THIS EXISTS. `scripts/test-harness-wired.sh` asks whether an unwired
# harness has a DECLARED reason. It never asks whether the exempt file still
# WORKS, and those are different questions. Measured when this was written: of
# the 3 exempt harnesses runnable on a dev box, 3 of 3 were broken on main.
#
#   test-target-clause.sh     drifted literal, "want [7] got [9]", since c7911c2d
#   test-lineage-render.sh    BLIND: the function it tested was deleted in 43d0ec84;
#                             the harness was RETIRED in turn (AMUX-4771)
#   test-unstamped-ledger.sh  dies on a zero-match grep under `set -o pipefail`,
#                             reports real failures when it survives, and is not
#                             idempotent between runs
#
# An unwired harness that is also broken reads as coverage while providing none,
# which is worse than no file: its name is in the baseline and in the workflow's
# comments, so a reader counts it.
#
# WHY NOT JUST WIRE THEM INTO `checks`. The exemptions are real. The clause
# harness compiles for real in every cell, which is minutes on every lane's
# push, and two of the three need a live server that a hosted runner does not
# have. The gate cannot be "run them all on every push"; it can be "run them
# somewhere, on a schedule, and put the result where someone looks".
#
# WHAT IT REFUSES TO DO. It never implies the unrunnable ones are fine. Of the
# 7 recorded entries, 4 need a booted Xcode iOS Simulator or the owner's
# Tailscale identity and cannot be automated on any box we have. A sweep that
# printed "3 of 7 green" would be the accumulate-without-discriminating shape
# one layer out, so the unchecked set is printed by name, with its tag, every
# run.
#
# Exit 0 when every [local] harness passed or self-reported SKIP; non-zero when
# any of them failed. The unrunnable ones never affect the exit code, because
# this sweep has no evidence about them either way.
set -uo pipefail
cd "$(dirname "$0")/.."

BASELINE=scripts/fixtures/harness-wired-baseline.txt
[ -f "$BASELINE" ] || { echo "FATAL: no baseline at $BASELINE" >&2; exit 2; }

# ONE LIST. Runnability is read from the baseline's own tag rather than kept
# here, because a second list of "which are runnable" is the same fact in two
# spellings and drifts (AF-161 is this repo's own specimen of that).
entries=$(grep -vE '^\s*(#|$)' "$BASELINE")
[ -n "$entries" ] || { echo "FATAL: baseline has no entries — nothing to sweep" >&2; exit 2; }

pass=0; fail=0; skip=0; unchecked=0
failed_names=""; unchecked_lines=""

while IFS= read -r line; do
  [ -n "$line" ] || continue
  name=$(printf '%s' "$line" | awk '{print $1}')
  tag=$(printf '%s' "$line" | awk '{print $2}')
  case "$tag" in
    "[local]") ;;
    "["*"]")
      unchecked=$((unchecked + 1))
      unchecked_lines="${unchecked_lines}      ${name}  ${tag}
"
      continue
      ;;
    *)
      # An untagged entry is not silently swept. The tag is how this sweep knows
      # what it may claim, so a missing one is a defect in the record, not a
      # reason to guess.
      echo "  ERROR  $name has no verifiability tag in $BASELINE" >&2
      fail=$((fail + 1))
      failed_names="${failed_names} ${name}(untagged)"
      continue
      ;;
  esac

  path="scripts/$name"
  if [ ! -e "$path" ]; then
    echo "  ERROR  $name is tagged [local] but does not exist" >&2
    fail=$((fail + 1)); failed_names="${failed_names} ${name}(missing)"
    continue
  fi

  case "$name" in
    *.sh) out=$(bash "$path" 2>&1); rc=$? ;;
    *.mjs|*.js) out=$(node "$path" 2>&1); rc=$? ;;
    *.py) out=$(python3 "$path" 2>&1); rc=$? ;;
    *) out=$("$path" 2>&1); rc=$? ;;
  esac

  case "$rc" in
    0) pass=$((pass + 1)); echo "  ok     $name" ;;
    # EXIT 2 IS THE HARNESS SAYING IT COULD NOT RUN, not that it failed. Two of
    # these declare that contract in their own headers (unreachable server).
    # Counting a self-reported skip as a pass would let a permanently
    # unreachable harness read as coverage, which is this card's whole subject.
    2) skip=$((skip + 1)); echo "  SKIP   $name (self-reported: cannot run here)" ;;
    *)
      fail=$((fail + 1)); failed_names="${failed_names} ${name}"
      echo "  FAIL   $name (exit $rc)"
      printf '%s\n' "$out" | tail -12 | sed 's/^/           /'
      ;;
  esac
done <<< "$entries"

echo ""
echo "harness-exempt-sweep: ${pass} passed, ${fail} failed, ${skip} self-skipped"
# NAMED, NOT COUNTED AWAY. This is the line that stops the sweep implying the
# device- and identity-bound harnesses are green.
if [ "$unchecked" -gt 0 ]; then
  echo "NOT CHECKED BY ANY AUTOMATION WE HAVE (${unchecked}); this sweep says nothing about them:"
  printf '%s' "$unchecked_lines"
fi
[ -n "$failed_names" ] && echo "failed:${failed_names}"
[ "$fail" = 0 ]
