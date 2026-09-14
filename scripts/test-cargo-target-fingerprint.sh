#!/usr/bin/env bash
set -u
set -o pipefail

# AF-791: verifies shared-target stale-output detection in test-contended.
# If a source edit does not advance mtime, Cargo may reuse a stale artifact.
# Build a private, dependency-free fixture so a clean checkout can run this.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/amux-fingerprint-test.XXXXXX")
trap 'rm -rf "$FIXTURE_ROOT"' EXIT
SPEC="$FIXTURE_ROOT/specimen"
TMP_TARGET="$FIXTURE_ROOT/target"
mkdir -p "$SPEC/src" "$TMP_TARGET"
cat > "$SPEC/Cargo.toml" <<'TOML'
[package]
name = "amux-af791-mtime-probe"
version = "0.1.0"
edition = "2021"
[workspace]
TOML
cat > "$SPEC/src/lib.rs" <<'RS'
pub fn answer() -> u64 { 7 }
#[test]
fn matches_expected_value() {
    assert_eq!(answer(), std::env::var("AF791_EXPECT").unwrap().parse::<u64>().unwrap());
}
RS
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
    "$WRAP" --offline --quiet -p amux-af791-mtime-probe "$@" >"$log" 2>&1
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

if ! run_once "$BASELOG" "$BASEVAL"; then
  bad "baseline test accepts AF791_EXPECT=$BASEVAL"
elif ! grep -q "test result: ok. 1 passed; 0 failed;" "$BASELOG"; then
  bad "baseline test for AF791_EXPECT=$BASEVAL produced no passing test output"
else
  ok "baseline test accepts AF791_EXPECT=$BASEVAL"
fi

# Create a content-only edit and preserve mtime.
STAMP=$(python3 -c 'import os,sys;print(os.stat(sys.argv[1]).st_mtime_ns)' "$SPEC/src/lib.rs")
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
python3 - "$SPEC/src/lib.rs" "$STAMP" <<'PYTIME'
import os,sys
p,stamp=sys.argv[1],int(sys.argv[2]);os.utime(p,ns=(os.stat(p).st_atime_ns,stamp))
assert os.stat(p).st_mtime_ns==stamp
PYTIME

STALENESS="$TMP_TARGET/staleness.log"
if ! run_once "$STALENESS" "$NEXTVAL"; then
  bad "rerun with preserved mtime does not accept AF791_EXPECT=$NEXTVAL"
elif grep -q 'test result: ok. 1 passed; 0 failed;' "$STALENESS" && grep -q 'staleness: shared target cache for package amux-af791-mtime-probe differs from source digest;' "$STALENESS"; then
  ok "preserved-mtime edit forced cache refresh; test now passes AF791_EXPECT=$NEXTVAL"
else
  bad "preserved-mtime edit did not print a staleness notice"
fi

echo "test-cargo-target-fingerprint: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
