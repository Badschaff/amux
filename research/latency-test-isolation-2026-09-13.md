# AF-397: isolate the latency scan fixture

The scan-cap fixture changed `AMUX_LATENCY_SCAN_CAP` to 200 inside the shared
Rust test process. Concurrent tests inherited that limit. The three-family
rollup fixture has 180 current rows and 180 baseline rows; a 200-row scan leaves
only 20 baseline rows, below the 30-per-family threshold, and returns no finding.
This is a remaining global-state leak after 9a919452 removed a separate
`AMUX_AUTOFIX_WINDOW_H` override. It is not proof of which override caused every
historical CI failure.

An exact clean 0c79fc53 run with `AMUX_LATENCY_SCAN_CAP=200` reproduced the card's
assertion: three simultaneous regressions expected one event, got an empty list
(0 passed, 1 failed). This deliberately supplies the contaminating value; it does
not claim to have recreated a particular thread interleaving. An earlier run
also failed, but its source changed during compilation and is excluded from the
clean-snapshot evidence.

The detector now reads the runtime cap once and passes it through the scan,
warning and finding evidence. The existing fixture passes 200 directly to that
same implementation and no longer changes process environment. The normal
runtime environment setting still works. The INFO population log now includes
`scan_cap`, so a sweep can distinguish a low limit from an empty workload. The
existing cap warning retains its actual limit and considered-row count.

Validation before commit:

- `scripts/test-contended.sh -p amux-server --lib runtime_jobs::autofix::tests`
  -> 134 passed, 0 failed, 1 ignored. Both the rollup and cap fixtures passed.
- `scripts/mutate.sh run ... 'detect_latency_with_scan_cap(&conn, now, None, 200)'
  'detect_latency_with_scan_cap(&conn, now, None, 400_000)' -- ... the_scan_cap_truncates_the_baseline_never_the_window`
  -> 0 passed, 1 failed, explicitly rejecting complete coverage for the intended
  capped fixture. Mutation restored. This checks that the fixture reaches the
  real cap; it does not simulate concurrent global-environment mutation.

Private command logs are registered under AF-748 in
`scratch/af748-board-drain/af397-*.log`. These are scoped test results, not a full
server suite or deployment claim. No board task or user message is changed by
the detector's scan.
