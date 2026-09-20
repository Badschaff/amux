# Command intake and board adherence

The lifecycle has three distinct records: the original command, its executable
board outcomes, and the current runtime claim. Receiving a message does not prove
that the worker switched tasks. A follow-up preserves the active claim and stays
visible for intake.

## Shared boundaries

1. **Receipt:** owner commands use the durable command lifecycle before execution
   by default (see `command-lifecycle.md`). Explicit opt-outs and model-free
   operation retain legacy capture. Legacy session and orchestrator delivery call
   `session_verbs::mint_capture_card`. It redacts secrets, excludes control/status
   chatter, deduplicates identical open receipts, and derives a readable title.
   Markdown list markers are removed before finding the first sentence.
2. **Intake:** preserve the original request, compare the existing board, and
   either structure the one outcome or turn the receipt into an epic linked to
   canonical tasks. The existing atomic decomposition endpoint handles children
   and retry identity. `has_execution_details` recognizes a next action plus
   textual acceptance criteria even when `**Prompt:**` provenance remains.
   Its SQL mirror is parity-tested. Structuring a receipt releases only the
   harness's delivery marker, never a genuine approval or event hold.
3. **Selection:** use positive current provider evidence, including a bounded
   pane probe when a structured hook expires. Unknown, empty and busy panes never
   authorize delivery. Scan Doing/Review candidates past refusals and confirmed
   unchanged reminders without a fixed prefix cutoff. Selection and enqueue share the durable reminder lookup.
   WIP and verification share one execution-slot predicate: raw captures, epics
   and held work do not block independent verification. An already-reviewed
   blocker suppresses repeated blocker prompts, not unrelated completion work.
4. **Parallel execution:** fan-out assigns independent ready outcomes to stable
   child identities. Connected prerequisite chains remain together on the owner
   board; moving one prerequisite cannot strand its dependents on another board.
   It uses the same dependency completion predicate as normal
   dispatch. Both `/launch` and `/{id}/fan-out` use one ephemeral provisioner with
   worktrees and backlog draining enabled. It preserves existing configuration,
   pause/archive state, and assignments on retry. An identical open launch graph
   is reused and the response reports `idempotent: true`.
5. **Completion:** verification batches select up to eight oldest unoffered
   outcomes. Partial progress releases other candidates; unchanged output/contract
   fingerprints stay quiet, while changed evidence or gates re-arm verification.
   The assignment ends at its type's completion boundary, not at
   receipt delivery or a generic Done label. Runtime changes still require
   verification. Fan-out Verified requires a successful integration receipt for
   the current clean worktree head; gate acknowledgements cannot substitute for
   that artifact check. Evidenced prerequisites can integrate before queued
   successors, while the shared Doing-slot rule protects active implementation.
   Discard/quarantine stop execution but do not satisfy dependent
   outcomes. The reaper uses actual ephemeral membership, retains workers with
   queued work, and leaves worktree disposal to the worktree lifecycle.

## Determinism and cost

Receipt persistence, retries, ownership, readiness, claims and transition gates
are harness decisions. Decomposition, semantic equivalence and whether evidence
proves a result require model judgment. Do not claim otherwise or replace those
judgments with a title-similarity threshold.

Scheduling adds no model probes. Semantic command intake uses the existing
compact helper and bounded budget; exhaustion creates one owned intake investigation
through the normal board lifecycle rather than an immortal pending command.
Unchanged reminders remain suppressed. Paused and isolated workers remain excluded
from automation. The live global and amux-group verification gates now require the
owning worker to reproduce results and record evidence; they no longer create a
mandatory dependency on a different worker. Tests, integration, deployment where
applicable and regression checks remain required. Explicit custom gates still resolve
through the same card/worker/group/global/type precedence.

A bulk historical import is an intake inventory, not hundreds of ready tasks.
Reconcile it in bounded batches against current artifacts and existing outcomes;
preserve provenance, attach evidence, and retire duplicates only with a named
canonical survivor. “No acceptance criteria” is a diagnostic, not proof that a
historical task failed or permission to close it.

## Validation

`fan_out_e2e` exercises API retries, stable assignment after retitling, dependency
readiness and pause/configuration preservation. Run with one test thread because
its fixtures set AMUX_HOME. These tests do not require model execution. The fleet
audit is retained outside the repository because its board contents are private.

Git contention is scoped to the worker’s own checkout and index. A worker must not
wait on a fleet-wide `pgrep -f "git commit"`: that expression matches the waiting
shell’s own command line and can never clear. Use the worktree’s actual Git
result/lock state and a bounded retry; inspect the concrete holder before taking
any recovery action. A process existing is not evidence of task progress.
