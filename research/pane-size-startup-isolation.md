# AF-789: pane-size startup bypassed fleet isolation

The real `pane_size::spawn()` launched boot repair in a separate Tokio task
before calling the guarded periodic constructor. With `AMUX_ISOLATED=1`, the
registry therefore correctly showed a disabled job while its startup task still
enumerated and resized panes. The central isolation implementation from
AMUX-3221 covered the loop but missed this caller's independent startup task.

The first periodic tick is immediate. Boot repair now runs on that tick, inside
the same constructor as every subsequent sweep. The first sweep still ignores
viewer leases; subsequent sweeps respect them. Startup and later sweeps now run
serially and share isolation, tick accounting, cancellation, and manual-trigger
semantics. There is no new switch or independent scheduler.

The existing central suppression log and disabled registry reason now describe
the whole job, including startup. The boot repair count/session log remains and
is emitted once only when the boot sweep actually runs. The test checks these
actual logs; merely reading the knob or the registry would have missed the bug.

## Regression and controls

`crates/amux-server/tests/pane_size_isolation.rs` invokes the actual public
`spawn()` function in four separate processes: `AMUX_ISOLATED=1`,
`AMUX_NO_FLEET=1`, `AMUX_PANE_SIZE_SECS=0`, and enabled. Each child has a private
fake `tmux` executable as its entire PATH. A positive fixture call in every
child proves command execution and recording work. No real tmux socket, worker,
server, production database, or input delivery is involved.

Disabled cases assert zero command calls, zero ticks, the exact visible disable
reason, a completed task handle, refusal of manual triggers, and the suppression
log. The enabled control asserts the enumeration and all three exact restoration
commands despite a fresh viewer lease. A manually triggered second tick must
enumerate again but perform no restoration under that lease. The boot log must
appear exactly once with count 1 and the fixture session identity.

Pre-fix specimen: aef6f0dec3f29204bab71f76b16ef8066422f4ab plus the new test.
`scripts/safe-cargo.sh test -p amux-server --test pane_size_isolation -- --nocapture`
failed (0 passed, 1 failed, exit 101). The first isolated child recorded
`list-windows`, `set-option default-size`, `resize-window`, and
`set-option window-size latest`; the retained assertion prints every argument.
This is a real failure of the original production call path, not a source-text
expectation. Raw evidence: `scratch/af789-evidence/startup-red.log`.

After the correction, the same command passed: 1 passed, 0 failed, with all four
child scenarios green. `scripts/safe-cargo.sh test -p amux-server --lib
runtime_jobs:: -- --test-threads=4` passed: 606 passed, 0 failed, 1 ignored.
These are the startup integration target and the runtime-job unit group, not a
claim that the full server or browser suite ran. Logs are retained as
`scratch/af789-evidence/startup-green.log` and `runtime.log`.

## Limits

The disabled observation is a bounded one-second runtime execution, backed by
the pre-fix failure and enabled positive controls. This test does not boot a
second full server or operate a production pane. `ghost_rescue::spawn()` was
source-inspected: all of its work already runs inside `spawn_periodic`; it has
no equivalent independent boot task. That inspection is not a fresh live rescue
test. Full fleet safety, CI, and original-session acceptance are not inferred
from this bounded correction.

The ledger entry remains active. The originating `autofix (subagent)` must
explicitly validate this entry and agree it is complete before Verified and
retirement; independent review does not substitute for that agreement.
