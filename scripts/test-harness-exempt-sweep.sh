#!/usr/bin/env bash
# Cells for scripts/harness-exempt-sweep.sh (AMUX-4747).
#
# The sweep's job is to run the recorded-unwired harnesses that CAN run and to
# refuse to imply anything about the ones that cannot. Both halves are pinned
# here, against a SYNTHETIC baseline rather than the real one: the real file's
# verdicts change as harnesses are fixed, and a cell whose result moves with
# unrelated repair work is a cell nobody can trust.
set -Eeuo pipefail
trap 'echo "FAIL harness-exempt-sweep fixture line=$LINENO command=$BASH_COMMAND" >&2' ERR
cd "$(dirname "$0")/.."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
say() { if [ "$2" = 0 ]; then echo "ok   — $1"; PASS=$((PASS+1)); else echo "FAIL — $1"; FAIL=$((FAIL+1)); fi }

# A sweep run against a baseline we control, in a scratch copy of the repo
# layout, so the cells assert on the sweep and not on today's harness health.
run_sweep() {  # $1 = baseline contents
  rm -rf "$TMP/repo"; mkdir -p "$TMP/repo/scripts/fixtures"
  cp scripts/harness-exempt-sweep.sh "$TMP/repo/scripts/"
  printf '%s\n' "$1" > "$TMP/repo/scripts/fixtures/harness-wired-baseline.txt"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/repo/scripts/green.sh"
  printf '#!/usr/bin/env bash\necho "a real failure"\nexit 1\n' > "$TMP/repo/scripts/red.sh"
  printf '#!/usr/bin/env bash\necho "cannot run here"\nexit 2\n' > "$TMP/repo/scripts/skipper.sh"
  chmod +x "$TMP/repo/scripts/"*.sh
  set +e
  ( cd "$TMP/repo" && bash scripts/harness-exempt-sweep.sh ) > "$TMP/out" 2>&1
  RC=$?
  set -e
}

# 1. A broken [local] harness must fail the sweep. This is the whole point: a
#    declared exemption was never a claim that the file still works, and 3 of 3
#    runnable exempt harnesses were broken on main when this was written.
run_sweep "green.sh   [local]   fine
red.sh     [local]   broken"
grep -q "FAIL   red.sh" "$TMP/out"; say "a broken [local] harness is reported by name" $?
[ "$RC" != 0 ]; say "a broken [local] harness makes the sweep exit non-zero" $?

# 2. THE CONTROL that keeps cell 1 honest: an all-green sweep must exit 0.
#    Without this, a sweep hardcoded to fail would pass cell 1.
run_sweep "green.sh   [local]   fine"
[ "$RC" = 0 ]; say "an all-green sweep exits zero" $?

# 3. A self-reported SKIP (exit 2) is not a failure and not a pass. Counting it
#    as a pass would let a permanently unreachable harness read as coverage,
#    which is this card's subject one layer in.
run_sweep "skipper.sh [local]   needs a live server"
grep -q "SKIP   skipper.sh" "$TMP/out"; say "exit 2 is reported as a self-skip" $?
[ "$RC" = 0 ]; say "a self-skip does not fail the sweep" $?
grep -q "0 passed" "$TMP/out"; say "a self-skip is NOT counted as a pass" $?

# 4. THE REFUSAL. Unrunnable entries must be named every run. A sweep that
#    printed "1 of 3 green" while staying silent about the other two would be
#    the accumulate-without-discriminating shape this file exists to prevent.
run_sweep "green.sh   [local]    fine
ios.mjs    [device]   needs a booted Simulator
who.py     [identity] needs the owner tailnet"
grep -q "NOT CHECKED BY ANY AUTOMATION" "$TMP/out"; say "the unchecked set is announced" $?
grep -q "ios.mjs" "$TMP/out" && grep -q "who.py" "$TMP/out"
say "every unchecked harness is named, not just counted" $?
[ "$RC" = 0 ]; say "unrunnable entries do not affect the exit code" $?

# 5. An UNTAGGED entry is a defect in the record, not a licence to guess. The
#    tag is how the sweep knows what it may claim.
run_sweep "green.sh   [local]  fine
mystery.sh          no tag here"
grep -q "no verifiability tag" "$TMP/out"; say "an untagged baseline entry is an error" $?
[ "$RC" != 0 ]; say "an untagged entry fails the sweep rather than being skipped" $?

# 6. ONE LIST: the runnable set comes from the baseline, not from the sweep.
#    Re-tagging an entry must change what runs, or the sweep is carrying its own
#    copy of a fact the baseline owns (AF-161).
run_sweep "red.sh     [device]  not runnable here"
[ "$RC" = 0 ]; say "re-tagging a broken harness [device] stops the sweep running it" $?
grep -q "red.sh" "$TMP/out"; say "and it is still named as unchecked" $?

# 7. The real baseline must be parseable by the real sweep: every entry tagged.
untagged=$(grep -vE '^\s*(#|$)' scripts/fixtures/harness-wired-baseline.txt \
  | awk '$2 !~ /^\[.*\]$/ {print $1}')
[ -z "$untagged" ]; say "every entry in the SHIPPED baseline carries a tag" $?

echo ""
echo "test-harness-exempt-sweep: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
