# Durable command lifecycle

The command planner reconciles each accepted message into board outcomes. The
message remains the receipt and source of truth; its `intake_result` records the
interpretation, canonical task IDs, and measured model-call count. Creation,
revision checks, graph links and message association commit in one transaction.

Structured intake is the default when the configured model client is available.
`AMUX_COMMAND_LIFECYCLE=0` at worker, group or global scope explicitly retains
the legacy capture path. Paused and isolated workers retain their boundaries.

- Search includes older and completed work across boards, with compact ranked
  candidates. A cross-worker match can be verified without overwriting its owner.
- Decompose into independent outcomes with falsifiable criteria. Dependencies
  require a named earlier output and a concrete reason, never mere relatedness.
- Repeated active commands reuse their committed root without another model call.
  Refinements preserve canonical tasks and reuse their open command epic.
- Information and questions stay in Messages. After two unsuccessful interpretation
  attempts and expiry of the in-flight attempt lease, a receipt becomes one
  structured intake investigation on its owner's board. Its gate requires mapping
  the original request to canonical outcomes before implementation. Failed responses,
  errors and token measurements remain attached to the receipt; duplicates reuse it.
- Tasks enter the existing board dispatcher without `source_ref` parking markers.
  Leases, worker pause, delivery, dependency promotion and transition gates remain
  authoritative. Epics require all required successful output states; discarded
  or quarantined children cannot manufacture completion.

## Token controls

`AMUX_INTAKE_MODEL` selects the semantic model, falling back to
`AMUX_HELPER_MODEL` and the configured fast default. Deterministic scheduling,
readiness, completion and unchanged-receipt recovery make zero model calls.

`AMUX_INTAKE_CANDIDATES` defaults to 8 compact candidates (maximum 200).
`AMUX_INTAKE_CALLS_PER_HOUR` defaults to a conservative shared 60-call ceiling.
At most two interpretations run concurrently and a receipt has at most two
attempts. A failed/uncertain interpretation remains visible on the receipt and
then hands recovery to the same board dispatcher, without a third helper call.
No generic endless retry or repeated capture-disposal prompt is produced by this
controller. `/api/board-lifecycle?session=<worker>` exposes decisions, pending
requests and durable call counts. Character counts are explicitly not presented
as measured token usage.

## Standing approval categories

`AMUX_APPROVAL_TYPES=budget,customer_outbound` restricts Needs You to increased
spend/budget and customer communication without existing authorization. The
setting follows process override, then worker/group/global scope. `*` retains
the legacy vocabulary for deployments that have not selected the new policy.
Ordinary choices proceed; missing capabilities require a concrete operational
blocker and an authorized remedy. This board gate does not grant credentials or
approve an external action; the existing capability and sending adapters remain
responsible for actual side-effect authorization.

Validation evidence is recorded per fresh Haiku worker against a fixed 10-point
scorecard. Unit tests use deterministic model fakes; provider integration tests
and live rounds can spend provider tokens. Do not claim full lifecycle effectiveness from compilation or
from a worker saying it finished: inspect the resulting board and artifacts.

The [three-round validation](command-lifecycle-validation-2026-09-15.md) scored
2, 3 and 5 out of 10; those scores remain the historical evidence, not a claim
that all lifecycle paths passed. Subsequent existing-worker receipts successfully
used canonical intake. The September 19 consolidation makes that path the default
and adds a bounded owner-recovery outcome for interpretation failure. No fourth
Haiku validation worker was created. The old fleet backlog has not been bulk
closed or represented as verified.

## Conservative execution and recovery

Owner commands enter the durable Messages ledger before execution. After
reconciliation, the board dispatcher delivers canonical work; the original raw
command is not also sent to the worker. Informational commands still reach the
conversation. Paused workers retain requests without starting interpretation or
execution. Isolated workers retain their explicit raw pass-through behavior.

A completed interpretation is saved before graph mutation. Recovery reuses it
without another model call; a revision bump alone does not invalidate it when
requirements still match. Changed requirements are reinterpreted within the
same bounded attempt allowance. Refinements replace superseded criteria and can
reopen the original command epic for current-output verification.

Read-only helpers use a compact system prompt and low effort. The CLI's
`AMUX_HELPER_MAX_BUDGET_USD` ceiling defaults to 0.10 per helper invocation.
This is a maximum, not a spend target or an invoice measurement. A failed warm
helper returns to the caller's retry policy instead of silently running another
paid helper. Provider-reported input, output and cache usage is retained where
available, with explicit coverage of measured receipts. Worker execution costs
remain separate in the existing token ledger. Empty new-worker configuration
restarts do not generate a continuation turn.

## Live validation fixes

The second Haiku trial exposed a quiet-start deadlock: a new Claude process had
no current-life hook and its idle prompt aged out after the last repaint. Such
workers now keep a bounded terminal probe until structured reports exist. Empty
captures and busy prompts still do not authorize dispatch.

Board acceptance is a distinct delivery mode. The API acknowledges the durable
receipt before planning; repeated pending requests wait on the original receipt.
Conversational interpretations enter the existing durable outbox with a stable
identity. Rejected model output retains its usage and response for one informed
repair. Task handoffs include current criteria, next action and effective gates.

Read-only helpers disable memory-file loading and default to zero extended
thinking tokens through the documented Claude environment settings
([reference](https://code.claude.com/docs/en/env-vars)). These settings apply to
data-only helper processes; working agents retain their normal project context.
`AMUX_HELPER_THINKING_TOKENS` can override the helper thinking budget. Diagnostics
count measured calls, including rejected interpretations, and say when coverage
is incomplete.

Repeated advancement reminders share a durable identity across timestamp, log and
revision-only changes. Only confirmed delivery suppresses a later worker turn.
Changed requirements or a new worker lifetime re-arm the reminder; queued
preconditions refresh in place, and voided delivery remains an observable failure.
