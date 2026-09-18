#!/bin/bash
# AF-926. shared-index-class-count.py against a small synthetic fixture, not
# the real frustrations.md — a real-ledger assertion would go stale the next
# time anyone edits an entry.
set -euo pipefail

SRC_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
ok()  { printf '  ok   %s\n' "$*"; }
bad() { printf '  FAIL %s\n' "$*" >&2; fail=1; }

cat > "$TMP/frustrations.md" <<'EOF'
# header

## Format

```
irrelevant template block
```

---
## A peer's git add swept my uncommitted work
AREA: attribution
STATUS: open
CARD: TEST-1
SYMPTOM: a shared checkout has one git index and a peer's git add swept my
uncommitted migration into their commit.

## A ghost-rescue timestamp mismatch
AREA: instruments
STATUS: open
CARD: TEST-2
SYMPTOM: a composer timestamp prefix guard misfires on a legitimate message.

## A closed shared-index entry
AREA: instruments
STATUS: fixed 2026-01-01
CARD: TEST-3
SYMPTOM: this shared checkout race was fixed already, so it must not count
toward OPEN even though it matches the keyword list.

## Unrelated browser area entry
AREA: browser
STATUS: open
CARD: TEST-4
SYMPTOM: a worktree keyword here should never be reached because this entry
is outside the candidate AREA pool entirely: worktree cross-lane.
EOF

# Point the script at the fixture instead of the real ledger.
sed "s|FRUST = Path(__file__).resolve().parent.parent / \"frustrations.md\"|FRUST = Path(\"$TMP/frustrations.md\")|" \
  "$SRC_REPO/scripts/shared-index-class-count.py" > "$TMP/count.py"

out="$(python3 "$TMP/count.py")"

if printf '%s' "$out" | grep -q "n_considered (total ledger entries): 4"; then
  ok "counts all 4 entries in the fixture"
else
  bad "wrong n_considered:"
  printf '%s\n' "$out" | sed 's/^/       /' >&2
fi

if printf '%s' "$out" | grep -q "candidate pool (AREA in ('attribution', 'instruments')): 3"; then
  ok "candidate pool excludes the browser-area entry (TEST-4)"
else
  bad "candidate pool count wrong"
fi

if printf '%s' "$out" | grep -q "shared-index-shaped (any status): 2"; then
  ok "shaped-any-status is 2 (TEST-1 open + TEST-3 closed), TEST-2 correctly excluded"
else
  bad "shaped-any-status count wrong"
fi

if printf '%s' "$out" | grep -q "shared-index-shaped AND open: 1"; then
  ok "shaped-AND-open is 1 -- TEST-3's fix must not count as open despite matching the keywords"
else
  bad "shaped-AND-open count wrong (a closed shared-index entry may be leaking into the open count)"
fi

if printf '%s' "$out" | grep -q "TEST-1" && ! printf '%s' "$out" | grep -q "TEST-3"; then
  ok "the printed OPEN list names TEST-1 and omits TEST-3"
else
  bad "the printed OPEN list is wrong"
fi

if ! printf '%s' "$out" | grep -q "TEST-4"; then
  ok "TEST-4 (outside the candidate areas, keyword or not) never appears"
else
  bad "TEST-4 leaked in despite being outside AREA in (attribution, instruments)"
fi

[ "$fail" -eq 0 ] && echo "shared-index-class-count suite: PASS" || echo "shared-index-class-count suite: FAIL" >&2
exit "$fail"
