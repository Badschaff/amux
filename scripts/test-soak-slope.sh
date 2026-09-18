#!/usr/bin/env bash
# Proves soak_slope.py can FAIL, which is the whole point of replacing the old
# peak-minus-baseline check (AMUX-4810). That check reported one verdict
# regardless of input for the entire life of the instrument; a replacement that
# is merely greener is not an improvement, so every case below names what it
# would catch.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SLOPE="$HERE/soak_slope.py"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
check() { # check <label> <expr-description> <actual> <expected>
  if [ "$3" = "$4" ]; then
    printf '  ok    %-46s %s\n' "$1" "$2=$3"; pass=$((pass + 1))
  else
    printf '  FAIL  %-46s %s expected %s got %s\n' "$1" "$2" "$4" "$3"; fail=$((fail + 1))
  fi
}
field() { python3 -c "import json,sys;print(json.load(sys.stdin).get('$1'))"; }

gen() { # gen <file> <n> <start_kb> <per_sample_kb> [jitter]
  python3 - "$1" "$2" "$3" "$4" "${5:-0}" <<'PY'
import sys, random
path, n, start, step, jitter = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), float(sys.argv[4]), int(sys.argv[5])
random.seed(7)
with open(path, "w") as fh:
    fh.write("elapsed_s\trss_kb\tfds\n")
    for i in range(n):
        rss = start + step * i + (random.randint(-jitter, jitter) if jitter else 0)
        fh.write("%d\t%d\t43\n" % ((i + 1) * 60, int(rss)))
PY
}

echo "soak_slope — a leak must be caught, and warm-up must not be called a leak"

# 1. FLAT at steady state. The healthy case; must not be rising.
gen "$WORK/flat.tsv" 240 100000 0 400
out=$(python3 "$SLOPE" "$WORK/flat.tsv" --soak-minutes 240)
check "flat steady state" rising "$(printf '%s' "$out" | field rising)" "False"
check "flat steady state" measured "$(printf '%s' "$out" | field measured)" "True"

# 2. A REAL LEAK: 2MB per minute, unmistakable. If this does not trip, the
#    detector is decoration.
gen "$WORK/leak.tsv" 240 100000 2048
out=$(python3 "$SLOPE" "$WORK/leak.tsv" --soak-minutes 240)
check "linear leak 2MB/min" rising "$(printf '%s' "$out" | field rising)" "True"

# 3. A SLOW leak that the old ratio check would have buried in warm-up noise:
#    100KB per minute = 6MB/h, steady.
gen "$WORK/slow.tsv" 240 100000 100
out=$(python3 "$SLOPE" "$WORK/slow.tsv" --soak-minutes 240)
check "slow leak 100KB/min" rising "$(printf '%s' "$out" | field rising)" "True"

# 4. WARM-UP THEN FLAT — the shape every real run has, and the one the old
#    check failed. The trailing window must read flat.
python3 - "$WORK/warm.tsv" <<'PY'
import sys
with open(sys.argv[1], "w") as fh:
    fh.write("elapsed_s\trss_kb\tfds\n")
    for i in range(240):
        rss = 60000 + (40000 * (1 - 2.718281828 ** (-i / 40.0)))
        fh.write("%d\t%d\t43\n" % ((i + 1) * 60, int(rss)))
PY
out=$(python3 "$SLOPE" "$WORK/warm.tsv" --soak-minutes 240)
check "warm-up then plateau" rising "$(printf '%s' "$out" | field rising)" "False"

# 4b. THE THRESHOLD ITSELF, pinned from both sides. Without these the default
#     could be changed to any value and every other case would still pass.
gen "$WORK/under.tsv" 240 100000 30     # 30 KB/min = 1800 KB/h, under 2048
out=$(python3 "$SLOPE" "$WORK/under.tsv" --soak-minutes 240)
check "rise under the threshold" rising "$(printf '%s' "$out" | field rising)" "False"
gen "$WORK/over.tsv" 240 100000 50      # 50 KB/min = 3000 KB/h, over 2048
out=$(python3 "$SLOPE" "$WORK/over.tsv" --soak-minutes 240)
check "rise over the threshold" rising "$(printf '%s' "$out" | field rising)" "True"

# 5. SHORT RUN: a 20-minute soak has not reached steady state, so the slope is
#    reported but must NOT be presented as a measured verdict.
gen "$WORK/short.tsv" 20 60000 1200
out=$(python3 "$SLOPE" "$WORK/short.tsv" --soak-minutes 20)
check "20m run is not steady state" steady "$(printf '%s' "$out" | field steady)" "False"
why=$(printf '%s' "$out" | field why_unmeasured)
case "$why" in
  *"below the 120m"*) printf '  ok    %-46s %s\n' "short run says why" "why_unmeasured is populated"; pass=$((pass + 1)) ;;
  *) printf '  FAIL  %-46s got %s\n' "short run says why" "$why"; fail=$((fail + 1)) ;;
esac

# 6. TOO FEW SAMPLES: must report measured=false rather than a verdict from 2
#    points, which is the failure mode the old script already guarded against.
gen "$WORK/tiny.tsv" 3 60000 100
out=$(python3 "$SLOPE" "$WORK/tiny.tsv" --soak-minutes 240)
check "3 samples cannot carry a slope" measured "$(printf '%s' "$out" | field measured)" "False"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
