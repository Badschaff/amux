# Durable command lifecycle

The command planner reconciles each accepted message into board outcomes. The
message remains the receipt and source of truth; its `intake_result` records the
interpretation, canonical task IDs, and measured model-call count. Creation,
revision checks, graph links and message association commit in one transaction.

Enable the staged controller through `AMUX_COMMAND_LIFECYCLE=1` at worker,
group or global scope. During validation it is enabled only on the canary
workers. Disabling it preserves the existing capture path.

- Search includes older and completed work across boards, with compact ranked
  candidates. A cross-worker match can be verified without overwriting its owner.
- Decompose into independent outcomes with falsifiable criteria. Dependencies
  require a named earlier output and a concrete reason, never mere relatedness.
- Repeated active commands reuse their committed root without another model call.
  Refinements preserve canonical tasks and reuse their open command epic.
- Information and questions stay in Messages; failed interpretation stays pending
  instead of minting a runnable fallback task.
- Tasks enter the existing board dispatcher without `source_ref` parking markers.
  Leases, worker pause, delivery, dependency promotion and transition gates remain
  authoritative. Epics require all required successful output states; discarded
  or quarantined children cannot manufacture completion.

## Token controls

`AMUX_INTAKE_MODEL` selects the semantic model, falling back to
`AMUX_HELPER_MODEL` and the configured fast default. Deterministic scheduling,
readiness, completion and unchanged-receipt recovery make zero model calls.

`AMUX_INTAKE_CANDIDATES` defaults to 24 compact candidates (maximum 200).
`AMUX_INTAKE_CALLS_PER_HOUR` defaults to a conservative shared 60-call ceiling.
At most two interpretations run concurrently and a receipt has at most two
attempts. A failed/uncertain interpretation remains visible on the receipt.
No generic endless retry or repeated capture-disposal prompt is produced by this
controller. `/api/board-lifecycle/?session=<worker>` exposes decisions, pending
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
scorecard. Unit tests use deterministic model fakes; only the live rounds spend
provider tokens. Do not claim full lifecycle effectiveness from compilation or
from a worker saying it finished: inspect the resulting board and artifacts.
