#!/usr/bin/env bash
# test-target-clause.sh — AF-346. `cargo test -p amux-server --lib` reports a
# four-digit pass count and SKIPS every tests/*.rs target (50 here). The
# a99955f7 dashboard regression was caught by a guard that ALREADY EXISTED and
# was correct; it did not run, because the author verified with --lib and read
# the number as the suite.
#
# CELL 2 IS THE CONTROL and it is the one that matters: a runner that printed
# this clause unconditionally would be noise on every full run, and would pass
# cell 1 alone.
#
# CELL 3 pins the bug the first version of this clause shipped with: the path
# was derived from BASH_SOURCE, and because the runner snapshots itself to a
# temp file and re-execs (AF-368), it resolved to nothing and the clause never
# printed. A missing warning is indistinguishable from nothing to warn about.
# ASSERT ON A MARKER, NEVER ON THE LENGTH OF THE PROSE (AMUX-4735).
#
# Three cells used to pin `grep -c '^targets:'` against a literal 7 or 4. That
# counts LINES OF THE RUNNER'S EXPLANATION, so c7911c2d broke two of them by
# adding sentences to the message: want [7] got [9], on a runner that was
# working perfectly. The labels already said what the cells meant, "the clause
# fires" and "announces the skipped lib", and a paragraph length is not that.
#
# The irony was one line down. The very next assertion in cell 1 is labelled
# "the count matches the tree, not a constant" and passes, because it compares
# against `find`. A drifted literal sat directly above a computed one.
#
# This file is deliberately NOT wired into `checks` (see
# scripts/fixtures/harness-wired-baseline.txt: every cell compiles for real, so
# wiring it adds minutes to every lane's push). That is defensible and it is
# also why the drift went unseen for as long as it did: nothing runs a
# recorded-unwired harness, so nothing notices when one stops being true.
# Tracked separately as AMUX-4747.
set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$SRC/scripts/test-contended.sh"
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "  ok   $1"; else
       fail=$((fail+1)); echo "  FAIL $1: want [$3] got [$2]"; fi; }

echo "cell 1: --lib says how many integration targets it skipped"
o=$("$RUNNER" -p amux-server --lib invariants::checks::negative_controls 2>&1)
ok "the clause fires" "$(printf '%s' "$o" | grep -c 'were NOT built or run')" "1"
n=$(printf '%s' "$o" | grep -oE 'subset — [0-9]+ integration' | grep -oE '[0-9]+')
real=$(find "$SRC/crates/amux-server/tests" -maxdepth 1 -name '*.rs' | wc -l | tr -d ' ')
ok "the count matches the tree, not a constant" "$n" "$real"

# CELL 2'S CONTRACT CHANGED, deliberately. It used to assert that `--test <name>`
# stayed SILENT, on the reading that naming a target is not the narrowing this
# clause is about. AF-346's own closing sentence says the opposite -- "`--lib` is
# not the only such flag" -- and `--test` is the sharper case: it skips the LIB
# ENTIRELY, which is the larger half of this crate, while printing the smallest
# number of any selector. A caveat that fires for the flag that skips the smaller
# half and stays quiet for the flag that skips the larger one is the wrong way
# round. The runner now announces it, so this cell asserts the announcement.
#
# The full-suite control moved rather than disappeared: it is cell 3 of
# scripts/test-selector-clauses.sh, which stubs cargo and can therefore afford a
# no-selector run. Every cell here compiles for real, which is why this file has
# never had one.
echo "cell 2: --test skips the LIB, and now says so"
o2=$("$RUNNER" -p amux-server --test browser_errors_carry_cause 2>&1)
# TWO DISTINCT PROPERTIES, not one property twice: that a clause was printed at
# all, and that it was specifically about the lib. Expressed as booleans, since
# "did it print" has no number in it.
ok "a clause is printed" "$(printf '%s' "$o2" | grep -qE '^targets:' && echo yes || echo no)" "yes"
ok "and names which half"      "$(printf '%s' "$o2" | grep -c 'THE LIB WAS NOT RUN')" "1"

echo "cell 3: the count is derived from the repo, not from the running script"
# The runner re-execs from a temp snapshot, so a BASH_SOURCE-relative path
# resolves to /var/folders/... and silently yields nothing. Assert the clause
# survives being invoked from an unrelated cwd.
o3=$(cd /tmp && "$RUNNER" -p amux-server --lib invariants::checks::negative_controls 2>&1)
ok "still fires from another cwd" "$(printf '%s' "$o3" | grep -c 'were NOT built or run')" "1"

echo ""
echo "test-target-clause: $pass passed, $fail failed"
[ "$fail" = 0 ]
