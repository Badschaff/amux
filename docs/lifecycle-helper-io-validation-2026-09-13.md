# Helper I/O validation — September 13, 2026

Native lifecycle remains **INCOMPLETE** while host admission denies new workers.
That prerequisite does not prevent testing real local subprocess transport.

The prior implementation synchronously wrote stdin before starting the timeout,
polled child exit without reading either output pipe, then called blocking
`wait_with_output()`. Three real subprocess tests failed: unread two MiB prompt,
512 KiB stdout plus 512 KiB stderr, and a descendant retaining output after its
parent exited. The pre-fix result was **0 passed / 3 failed**.

The replacement uses nonblocking pipes with fair reads and writes, starts its
deadline before spawn, and applies it through pipe EOF and child completion.
No I/O thread is detached. Helpers start in their own process group. The direct
child stays waitable until pipe EOF so timeout cleanup has a reserved group
identity; failures kill that group and reap the direct child. Deliberately
detached descendants that leave the process group are outside that scope.

Combined retained stdout/stderr is bounded by `AMUX_HELPER_OUTPUT_MAX_BYTES`
(default eight MiB, configurable positive byte count). Exceeding the limit is
an explicit failure, never a truncated successful model answer. A successful
exit with an incomplete prompt also fails. Failed exits still return their
bounded quota/error diagnostic even when the child closes stdin early.

Logs distinguish spawn, timeout, I/O, output-limit and incomplete-input errors
with measurement counts and byte budgets, without copying prompts or output.
Cleanup reports whether the group was signalled and the direct child reaped.

Fixtures use only local shell tools: no real provider calls, billing changes,
worker-admission overrides, or mutations to production workers. Raw evidence is
in the private `helper-io-20260913` artifact directory. LC-HELPER-FAILURE records
these acceptance cases; they do not certify live semantic merging or worker
completion. Validation results:

- Before: three newly added real subprocess tests failed (0 passed / 3 failed).
- After: `scripts/test-contended.sh -p amux-server --lib -- api::mdai::
  api::board_intake:: runtime_jobs::message_capture::` → **42 passed, 0 failed,
  0 ignored, 2355 filtered out**. This is a selected unit-test scope.
- Exact mutation via `scripts/mutate.sh run` changed `started.elapsed() >= budget`
  to `started.elapsed() >= budget.saturating_mul(20)`. The unread-prompt deadline
  test failed, the inverse mutation reverted, and the restored final selection
  above passed.

- `scripts/safe-cargo.sh check --workspace` → **exit 0**.
- `scripts/safe-cargo.sh clippy --workspace --all-targets -- -D warnings` → **exit 0**.
- Lifecycle runner unit tests → **9 passed**.

The portable receipt is [lifecycle-helper-io-2026-09-13.json](evidence/lifecycle-helper-io-2026-09-13.json).
