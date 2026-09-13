# Retained dead panes and typed worker status (AF-784)

The typed worker API could still report `running:true` / `idle` after a launch
failure. AMUX-2644's earlier `2a51c882` correction filters all-dead sessions from
the legacy fleet listing. The typed store/scan path is a separate reader: it
captured terminal text and never consumed tmux's physical exit evidence.

## Evidence that discriminates

The first private tmux test passed because incidental shell-prompt text caused
TerminalAdapter to infer an exit. That artifact remains in
`scratch/af784-evidence/initial-probe-fixed-fixture.log`; it is not proof that
physical death was detected.

On parent `b0c10f5da6c5766616cb6a4d2aef2af909dc5858`, the strengthened specimen clears
terminal/history text and prints the original root-launch refusal. A real pane
exits1 and remains present. `TmuxBackend::status` reports Completed/1, capture
contains the refusal and `Pane is dead (status 1)`, and the adapter emits no events.
The actual worker router remains running/idle after ScanLoop: 0 passed / 1 failed.
Raw evidence: `scratch/af784-evidence/neutral-exit-red.log`.

## Correction

The existing backend trait exposes a batched process-exit census. Tmux reads all
pane death/status/signal fields in one bounded call. Only sessions whose every
pane is confirmed dead yield exits; a live side pane retains the session. Failed
or malformed probes do not manufacture exits. Agreeing pane outcomes preserve
the reported code/signal; conflicting dead-pane outcomes report unknown fields.

The scan preserves structured/native voice precedence, then applies the existing
Exited event for an exact matching terminal session instead of scraping its text.
That closes the typed session and changes the worker to stopped. The measured
`/api/debug/scan` population includes these workers and exposes exit code/signal;
`terminal_process_exit` warnings and the system-job summary name the outcome.
A second scan has no live session to close and emits no duplicate exit.

The new integration test starts a child test process with a fresh private
TMUX_TMPDIR and no inherited TMUX. It verifies the actual socket path, uses only
one newly minted worker and temporary SQLite store, then cleans up its private
server. CI requires tmux so a missing executable cannot masquerade as a passing
specimen. No model is invoked and no fleet worker is changed.

## Validation and limits

Actual real-pane/worker-router/diagnostic regression: 1 passed / 0 failed after
correction. Backend census controls cover dead, live, mixed, signaled, ambiguous,
foreign, empty and malformed populations. Scan controls cover missing/failed
probes and a different worker's exit, while retaining structured precedence.
Exact commands/results and subsequent clean publication gates are recorded on
AF-784 and under `scratch/af784-evidence`.

This is a local real-tmux/private-store reproduction, not a new cloud container
launch or production worker kill. The historical originating session is `amux
(cloud rust image, AMUX-2619)`. Its explicit agreement, independent review, full
CI and resolved verification gates remain required. The original active ledger
entry and original AMUX cards are preserved; this report does not retire them.
