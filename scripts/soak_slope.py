#!/usr/bin/env python3
"""Steady-state RSS slope for the soak probe's leak verdict.

WHY A SLOPE AND NOT PEAK-MINUS-BASELINE (AMUX-4810). soak-probe.sh scored
`(MAX_RSS - BASE_RSS) / BASE_RSS` against a baseline taken 30 SECONDS into the
run. The server takes roughly two hours to reach steady state, so that ratio is
almost entirely warm-up, and the peak is an overshoot the process gives back.
Measured on the 09-13 weekly run (240 samples, 4h):

    quarter 1  +30,076 KB      quarter 3   -7,960 KB
    quarter 2  +14,768 KB      quarter 4   -2,536 KB
    peak 117,272 KB, final 105,752 KB

It plateaus by the two-hour mark and the second HALF is negative, yet that run
scored 1.175 against a 0.20 threshold and "failed". Every run of that
instrument since 08-16 failed the same way, which is a detector that reports
one verdict regardless of input.

A leak is a POSITIVE SLOPE AT STEADY STATE. Warm-up flattens; a leak does not.
So fit a least-squares line over the final fraction of the samples and ask
whether it rises. Measured final-half slopes:

    weekly 09-13 (4h, conc 8)      +657 KB/h   R2 0.01   <- genuine steady state
    nightly 09-17 (20m, conc 4)  +3,741 KB/h   R2 0.02   <- still warming up
    nightly 09-18 (20m, conc 4)  +2,356 KB/h   R2 0.83   <- still warming up

The 20-minute runs have not reached steady state, so their final half is still
warm-up and no leak verdict is honest from them. The caller decides that with
--min-minutes; this script reports `steady` so the caller cannot pass a verdict
off as measured when it was not.

Reads the probe's samples.tsv (elapsed_s, rss_kb, fds) and prints one JSON
object. Exit status is always 0: this reports, the caller gates.
"""

import argparse
import json
import sys


def read_samples(path):
    rows = []
    with open(path) as fh:
        for line in fh:
            parts = line.split()
            if len(parts) >= 2 and parts[0].isdigit():
                rows.append((int(parts[0]), int(parts[1])))
    return rows


def fit(rows):
    """Least squares rss_kb on elapsed_s. Returns (kb_per_hour, r2, stderr_per_hour)."""
    n = len(rows)
    if n < 3:
        return None
    mean_x = sum(r[0] for r in rows) / n
    mean_y = sum(r[1] for r in rows) / n
    sxx = sum((r[0] - mean_x) ** 2 for r in rows)
    syy = sum((r[1] - mean_y) ** 2 for r in rows)
    sxy = sum((r[0] - mean_x) * (r[1] - mean_y) for r in rows)
    if sxx == 0:
        return None
    slope = sxy / sxx
    r2 = (sxy * sxy) / (sxx * syy) if syy > 0 else 0.0
    # Residual standard error of the slope, so a noisy rise is not read as a
    # trend. With n-2 degrees of freedom; 2*stderr is roughly a 95% bound.
    resid = syy - slope * sxy
    stderr = ((resid / (n - 2)) / sxx) ** 0.5 if n > 2 and resid > 0 else 0.0
    return slope * 3600.0, r2, stderr * 3600.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("samples")
    ap.add_argument("--fraction", type=float, default=0.5,
                    help="trailing fraction of samples treated as steady state")
    ap.add_argument("--soak-minutes", type=float, required=True)
    ap.add_argument("--min-minutes", type=float, default=120.0,
                    help="below this the run has not reached steady state and no verdict is given")
    # BOTH conditions are needed and neither is redundant. Significance alone
    # calls a noiseless asymptotic tail a leak, because stderr goes to zero and
    # any positive slope clears 2*stderr: a synthetic warm-up curve tripped
    # exactly that during development. Magnitude alone calls scatter a leak on
    # a noisy run. Calibration: the only genuine steady-state observation on
    # record (09-13 weekly, final half) is +657 KB/h, and a noiseless warm-up
    # tail over the same window is about +946 KB/h, so 2048 clears both with
    # margin while still catching 6 MB/h (100 KB/min), which is 144 MB/day.
    ap.add_argument("--threshold-kb-per-hour", type=float, default=2048.0,
                    help="a steady-state rise at or below this is not a leak")
    args = ap.parse_args()

    rows = read_samples(args.samples)
    out = {
        "measured": False,
        "why_unmeasured": None,
        "steady": args.soak_minutes >= args.min_minutes,
        "samples": len(rows),
        "min_minutes": args.min_minutes,
        "soak_minutes": args.soak_minutes,
    }

    tail = rows[len(rows) // 2:] if args.fraction == 0.5 else rows[int(len(rows) * (1 - args.fraction)):]
    if len(tail) < 3:
        out["why_unmeasured"] = (
            f"only {len(tail)} sample(s) in the trailing window; a slope needs at least 3. "
            "Raise SOAK_MINUTES or lower SOAK_SAMPLE_S."
        )
        print(json.dumps(out))
        return

    fitted = fit(tail)
    if fitted is None:
        out["why_unmeasured"] = "the trailing window has no spread in elapsed_s"
        print(json.dumps(out))
        return

    slope, r2, stderr = fitted
    out.update({
        "measured": True,
        "kb_per_hour": round(slope, 1),
        "r2": round(r2, 3),
        "stderr_kb_per_hour": round(stderr, 1),
        "tail_samples": len(tail),
        "threshold_kb_per_hour": args.threshold_kb_per_hour,
        # A rise counts only when it is BOTH big enough to matter and
        # distinguishable from noise. See the argument's comment for why
        # either test alone gives a wrong answer on a real curve.
        "rising": bool(slope > args.threshold_kb_per_hour and slope > 2 * stderr),
    })
    if not out["steady"]:
        out["why_unmeasured"] = (
            f"soaked {args.soak_minutes:g}m, below the {args.min_minutes:g}m needed to reach steady "
            "state; the trailing window is still warm-up, so the slope is reported but is NOT a "
            "leak verdict"
        )
    print(json.dumps(out))


if __name__ == "__main__":
    sys.exit(main())
