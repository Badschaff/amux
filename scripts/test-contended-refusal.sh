#!/usr/bin/env bash
# AMUX-4689 — a refused run must certify nothing.
#
# THE DEFECT: when the cargo budget guard refuses before cargo starts, nothing is
# built and nothing is tested, and test-contended.sh printed its clauses anyway:
#
#   contention: the auto-builder was NOT rebuilding during this run, so the shared
#   contention: binary was stable under it. A failure here is NOT build contention.
#   worktree:  clean at start and end, so no peer's uncommitted source was in this build.
#
# Both describe a run. There had been none. VERIFY.md's contract is to paste the
# command AND ITS RESULT LINE as evidence, so that block IS what a lane pastes,
# and it is reassurance about work that did not occur.
#
# NOT an exit-code bug, though the card was originally filed as one. The exit
# status was always 75 and still is; the card's author ran the script through a
# pipe in an interactive shell with no pipefail and read `tail`'s 0 as the
# script's. The exit code is asserted below anyway, because a cell that only
# checked the text would pass a version that printed the right words and exited
# 0.
#
# Exit 0 = all pass, 1 = a failure.
set -euo pipefail

cd "$(dirname "$0")/.."
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# A scratch target dir, so nothing here touches the real one.
export CARGO_TARGET_DIR="$TMP/target"
mkdir -p "$CARGO_TARGET_DIR"

# THE FREE-SPACE ARM, not the size arm. cargo-budget.py takes its ceiling in
# whole GB, so the smallest cap expressible is 1GB and a fresh scratch dir is
# kilobytes: the size arm cannot be made to fire against it without writing a
# gigabyte of ballast, which is a slow test that fills a disk to prove a point.
# min_free refuses on the same code path with the same cargo_budget_refused
# event and needs no ballast at all. (The first cut used the size arm and
# SKIPPED on this host, which is a cell that reports success having measured
# nothing.)
REFUSE_ENV=(AMUX_CARGO_MIN_FREE_GB=999999)

check() { # label result
  if [ "$2" = "1" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  FAIL  $1"; fi
}

echo "a refused run certifies nothing (AMUX-4689)"
echo

# ---------------------------------------------------------------------------
# REFUSED. min_free is set above any real disk, so cargo-budget.py refuses
# before spawning cargo. Its own event line is the discriminator the script
# under test reads, so this drives the real mechanism rather than a stand-in.
# ---------------------------------------------------------------------------
set +e
env "${REFUSE_ENV[@]}" ./scripts/test-contended.sh -p amux-server --lib -- \
  __amux_4689_no_such_test__ > "$TMP/refused.out" 2>&1
REFUSED_RC=$?
set -e

# THE PREMISE, ASSERTED. If the guard did not refuse, every cell below passes
# vacuously, so this is a FAILURE rather than a skip: a harness that reports
# success having measured nothing is the defect this whole card is about.
if grep -q '"event": "cargo_budget_refused"' "$TMP/refused.out"; then
  PASS=$((PASS+1))
else
  echo "  FAIL  the budget did not refuse, so the refusal path was never exercised"
  head -5 "$TMP/refused.out" | sed 's/^/    /'
  exit 1
fi

check "a refused run exits non-zero" "$([ "$REFUSED_RC" != 0 ] && echo 1 || echo 0)"
check "it says NO TEST RAN" \
  "$(grep -q 'NO TEST RAN' "$TMP/refused.out" && echo 1 || echo 0)"
check "it names the remedy command" \
  "$(grep -q 'cargo-target-guard.py clear' "$TMP/refused.out" && echo 1 || echo 0)"
check "it names the one-run override" \
  "$(grep -q 'AMUX_CARGO_MAX_TARGET_GB=' "$TMP/refused.out" && echo 1 || echo 0)"

# THE HEART OF IT. These sentences describe a run, so on a refusal they must be
# absent. Each is asserted separately: a single combined grep would pass while
# one of them came back.
check "no contention verdict is printed" \
  "$(grep -q 'NOT build contention' "$TMP/refused.out" && echo 0 || echo 1)"
check "no worktree certification is printed" \
  "$(grep -q 'uncommitted source was in this build' "$TMP/refused.out" && echo 0 || echo 1)"
check "no targets-covered clause is printed" \
  "$(grep -q '^targets:' "$TMP/refused.out" && echo 0 || echo 1)"

# ---------------------------------------------------------------------------
# THE DISCRIMINATION. A run that ACTUALLY HAPPENS must still get its clauses and
# its own exit status. Without this cell the suppression could fire on every run
# and every assertion above would still pass.
# ---------------------------------------------------------------------------
# REUSES THE CALLER'S TARGET DIR, and a small crate. The refusal half above
# needs no compile, but this half does, and pointing it at the scratch dir would
# rebuild amux-server from nothing every run: minutes, for a cell about which
# sentences get printed. The inherited dir already holds the artifacts, and
# amux-core is the smallest crate in the workspace. The cap is raised because
# this box's shared target sits over the 40GB default, which would refuse the
# control and silently turn the discrimination into the refusal case again.
set +e
env -u CARGO_TARGET_DIR AMUX_CARGO_MAX_TARGET_GB=100000 AMUX_CARGO_MIN_FREE_GB=1 \
  ./scripts/test-contended.sh -p amux-core --lib -- \
  __amux_4689_no_such_test__ > "$TMP/ran.out" 2>&1
RAN_RC=$?
set -e

if grep -q '"event": "cargo_budget_started"' "$TMP/ran.out"; then
  check "a real run still prints its contention verdict" \
    "$(grep -q '^contention:' "$TMP/ran.out" && echo 1 || echo 0)"
  check "a real run prints no refusal block" \
    "$(grep -q '^refused:' "$TMP/ran.out" && echo 0 || echo 1)"
  # A filter matching nothing is a successful run of zero tests, so 0 here.
  check "a real run reports its own exit status" "$([ "$RAN_RC" = 0 ] && echo 1 || echo 0)"
else
  echo "  note: the control run did not start cargo (compile refused or unavailable);"
  echo "  note: the discrimination cells are unmeasured rather than passing."
fi

echo
echo "  population: $((PASS + FAIL)) cells, $FAIL failing"
if [ "$FAIL" -gt 0 ]; then
  echo "FAIL ($FAIL of $((PASS + FAIL)) cells)"
  exit 1
fi
echo "PASS ($PASS cells)"
