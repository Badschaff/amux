#!/usr/bin/env bash
set -u
set -o pipefail

# AF-791: verifies shared-target stale-output detection in test-contended.
# If a source edit does not advance mtime, Cargo may reuse a stale artifact.
# This test requires the fixture in scratch/af791-evidence/cargo-specimen.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC="$ROOT/scratch/af791-evidence/cargo-specimen"
if [ ! -d "$SPEC" ]; then
  echo "missing fixture: $SPEC" >&2
  exit 1
fi

TMP_TARGET="$ROOT/scratch/af791-evidence/fingerprint-target"
rm -rf "$TMP_TARGET"
mkdir -p "$TMP_TARGET"
export CARGO_TARGET_DIR="$TMP_TARGET"
WRAP="$ROOT/scripts/test-contended.sh"

PASS=0
FAIL=0
ok() { echo "  ok   $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

run_once() {
  local log="$1"
  local expect="$2"
  shift 2
  (
    cd "$SPEC"
    AF791_EXPECT="$expect" \
    CARGO_TARGET_DIR="$TMP_TARGET" \
    "$WRAP" --quiet -p amux-af791-mtime-probe "$@" >"$log" 2>&1
  )
}

extract_value() {
  python3 - "$SPEC/src/lib.rs" <<'PY'
import re
import sys

text = open(sys.argv[1]).read()
m = re.search(r'pub fn answer\(\) -> u64 \{\s*([0-9]+)\s*\}', text)
if not m:
    raise SystemExit(1)
print(m.group(1))
PY
}

# Baseline, then preserve-source mtime while changing content.
BASELOG="$TMP_TARGET/baseline.log"
BASEVAL="$(extract_value)"
if [ -z "$BASEVAL" ]; then
  echo "failed to parse baseline value from $SPEC/src/lib.rs" >&2
  exit 1
fi

if ! run_once "$BASELOG" "$BASEVAL" test; then
  bad "baseline test accepts AF791_EXPECT=$BASEVAL"
elif ! grep -q "test result: ok." "$BASELOG"; then
  bad "baseline test for AF791_EXPECT=$BASEVAL produced no passing test output"
else
  ok "baseline test accepts AF791_EXPECT=$BASEVAL"
fi

# Create a content-only edit and preserve mtime.
STAMP=$(stat -f %m "$SPEC/src/lib.rs")
NEXTVAL=$((BASEVAL + 1))
python3 - "$SPEC/src/lib.rs" "$NEXTVAL" <<'PY'
import re
import sys

path, value = sys.argv[1], sys.argv[2]
text = open(path).read()
updated = re.sub(
    r'pub fn answer\(\) -> u64 \{\s*[0-9]+\s*\}',
    f'pub fn answer() -> u64 {{ {value} }}',
    text,
    count=1,
)
if text == updated:
    raise SystemExit(1)
open(path, "w").write(updated)
PY
touch -t "$(date -r "$STAMP" +%Y%m%d%H%M.%S)" "$SPEC/src/lib.rs"
if [ "$(stat -f %m "$SPEC/src/lib.rs")" -ne "$STAMP" ]; then
  bad "preserved-mtime edit setup failed"
fi

STALENESS="$TMP_TARGET/staleness.log"
if ! run_once "$STALENESS" "$NEXTVAL" test; then
  bad "rerun with preserved mtime does not accept AF791_EXPECT=$NEXTVAL"
elif grep -q 'staleness: shared target cache for package amux-af791-mtime-probe differs from source digest;' "$STALENESS"; then
  ok "preserved-mtime edit forced cache refresh; test now passes AF791_EXPECT=$NEXTVAL"
else
  bad "preserved-mtime edit did not print a staleness notice"
fi

echo "test-cargo-target-fingerprint: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
