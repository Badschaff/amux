# Command intake and board adherence

The lifecycle has three distinct records: the original command, its executable
board outcomes, and the current runtime claim. Receiving a message does not prove
that the worker switched tasks. A follow-up preserves the active claim and stays
visible for intake.

## Shared boundaries

1. **Capture:** both session delivery and orchestrator delivery call
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
3. **Selection:** continue the exact current claim, subject to the existing
   idle/stale recovery rules; otherwise select eligible owned work. A suppressed
   per-card reminder falls through to guarded pickup. Captured backlog requests
   can receive the same once-per-card intake action as Doing receipts.
4. **Parallel execution:** fan-out assigns independent ready outcomes to stable
   child identities. Connected prerequisite chains remain together on the owner
   board; moving one prerequisite cannot strand its dependents on another board.
   It uses the same dependency completion predicate as normal
   dispatch. Both `/launch` and `/{id}/fan-out` use one ephemeral provisioner with
   worktrees and backlog draining enabled. It preserves existing configuration,
   pause/archive state, and assignments on retry. An identical open launch graph
   is reused and the response reports `idempotent: true`.
5. **Completion:** the assignment ends at its type's completion boundary, not at
   receipt delivery or a generic Done label. Runtime changes still require
   verification. Discard/quarantine stop execution but do not satisfy dependent
   outcomes. The reaper uses actual ephemeral membership, retains workers with
   queued work, and leaves worktree disposal to the worktree lifecycle.

## Determinism and cost

Receipt persistence, retries, ownership, readiness, claims and transition gates
are harness decisions. Decomposition, semantic equivalence and whether evidence
proves a result require model judgment. Do not claim otherwise or replace those
judgments with a title-similarity threshold.

This consolidation adds no model probes or periodic model calls. Existing nudge
budgets and suppression remain. The opt-in model intake controller remains
opt-in; enabling a controller whose prior lifecycle trial did not succeed is not
a substitute for resolving its failures. Paused and isolated workers remain
excluded from automation.

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
