# Active-worker lifecycle validation, September 15, 2026

**The fleet is not validated for unattended backlog drain.** All 17 active
workers' boards were audited. Ten additional live command probes produced ten
canonical chores with no duplicate tasks; six completed with independently
correct artifacts, including two that first reached Done with incorrect output
and needed evaluator feedback. Four probes remained behind existing work.
The earlier mvs-infra test failed before execution. Six active workers explicitly
opt out of automation through isolation.

This is a bounded validation of the existing system, not a rollout of fixes or a
bulk cleanup of the old boards. It does not upgrade the earlier three fresh
Haiku workers' scores or establish semantic deduplication of the whole backlog.

## Coverage and method

The initial inventory contained 140 workers: **17 active, 38 paused, 85 archived**.
All non-deleted, non-archived board records for each active worker were read,
including completed records: **6,648 records**. An active lifecycle does not
necessarily mean that the worker is currently executing. Isolation was preserved;
the live driver explicitly reported `isolated` for all six isolated workers.

The ten new non-isolated probes each requested one local JSON report computed
from a snapshot of that worker's actual board. Inventory, computation and checking
were explicitly one chore, with no epic, dependency edges, source changes,
production operations, customer contact, new workers or spending changes. Each
request was delivered twice with distinct transport identities. The separately
completed [mvs-infra test](command-lifecycle-mvs-infra-validation-2026-09-15.md)
was reused rather than buying another run of the same known failure.

Only `AMUX_COMMAND_LIFECYCLE` and `AMUX_INTAKE_MODEL` were temporarily set on the
ten workers, selecting Haiku 4.5 for interpretation. Candidate limits and all
execution models, pause states and isolation settings were retained. The existing
workers performed execution with their existing model and context; this was not
a controlled comparison of execution models. The only active Codex worker was
isolated, so this run did not execute a Codex or Gemini probe.

The local fixture deliberately represents `source_ref`, `blocked_on` and
`acceptance_criteria` as **boolean presence flags**. Dependency lists and status
values are retained. An independent checker recomputes every required metric
from that input, verifies the missing-criteria projection against the full raw
board snapshot, and compares the report exactly. Checking keys, totals or upper
bounds alone is insufficient. Raw card prose and personal/business details are
kept local.

## Every active worker

Counts are from the baseline snapshots, before the test chores. "Missing AC"
means an empty explicit `acceptance_criteria` field; it does not establish that
the description contains no acceptance conditions. The report tasks do not
validate or complete the original Backlog tasks.

| Worker | Backlog | Missing AC | Needs You | Live probe result |
| --- | ---: | ---: | ---: | --- |
| mixpeek-cicd | 154 | 154 | 28 | MC-2021: queued behind existing work; execution unmeasured |
| amux | 41 | 41 | 8 | AMUX-4691: queued behind existing work; execution unmeasured |
| mixpeek-general | 19 | 19 | 12 | MG-1803: correct artifact and Done; automatic interpretation repair |
| mixpeek-agent-memory-research | 0 | 0 | 0 | MAMR-3: queued behind live child work; execution unmeasured |
| mvs-infra | 121 | 121 | 8 | Earlier live test: both plans rejected, no execution |
| amux-helper | 15 | 15 | 0 | Isolated; board audit and driver refusal observed |
| tubescience | 36 | 31 | 0 | TUBES-2813: correct artifact and Done, no evaluator repair |
| gtm-research | 0 | 0 | 0 | Isolated; board audit and driver refusal observed |
| studio-plg | 42 | 42 | 8 | SP-961: queued behind existing work; execution unmeasured |
| mixpeek-ops-server | 38 | 27 | 7 | MOS-203: correct artifact and Done, no evaluator repair |
| desktop | 6 | 6 | 3 | Isolated; board audit and driver refusal observed |
| self | 14 | 14 | 0 | Isolated; board audit and driver refusal observed |
| random | 4 | 4 | 1 | Isolated; board audit and driver refusal observed |
| mixpeek-finances | 11 | 11 | 7 | MF-1178: false Done, then correct after one evaluator-assisted reopen |
| amux-gtm-auto | 0 | 0 | 0 | Isolated; board audit and driver refusal observed |
| social-activities | 0 | 0 | 2 | SA-185: correct artifact and Done; automatic recovery across server restart |
| mixpeek-homepage-claude | 16 | 15 | 18 | MHC-856: false Done, then correct after one evaluator-assisted reopen |
| **Total** | **517** | **500** | **102** | **17 boards covered; coverage limitations stated per worker** |

## What passed, and what did not

All ten new requests committed exactly one canonical chore. All twenty receipts
resolved; each duplicate shared its original's card and used zero model calls.
The ten task graphs had no epics or dependency edges. Mixpeek-general's first
response returned `kind=information` with nonempty tasks; the validator rejected
it, and the second attempt repaired it without partial graph creation.

The running server changed from `d01b6ed8a625` / build `c85d636017348546` to
`3bb1364ad124` / build `ba9830336e9a65ff` during the live probes. That range did
not change the controller's source. Social-activities had claimed an attempt
without saving a response when the process was replaced. Its durable receipt
survived, the second attempt completed, and the duplicate reused the same card.
The first call's usage was not retained; it must not be reported as zero cost.

The false Done cases are concrete failures of artifact verification:

| Chore | Metric | First reported | Independently expected |
| --- | --- | ---: | ---: |
| MF-1178 | Backlog with source reference | 11 | 9 |
| MF-1178 | Backlog with blocker text | 11 | 1 |
| MF-1178 | Backlog without acceptance criteria | 0 | 11 |
| MHC-856 | Backlog with blocker text | 16 | 0 |
| MHC-856 | Backlog without acceptance criteria | 0 | 15 |

Both workers had supplied completion evidence, including claimed passing checks.
Their checks did not recompute all required values using the fixture's boolean
semantics. The evaluator saved the bad artifacts, reopened each **same** chore
once with the mismatches, and independently checked the corrected artifacts.
The corrected results pass, but the initial unattended outcomes remain failures.
Chores legitimately terminate at Done; changing the column label to Verified
would not make an incorrect artifact correct. Evidence was added to the existing
AF-393 verification-routing issue.

The four unstarted probes were observed for at least twenty minutes after
admission. The driver kept them behind existing claims, live child work or
ongoing turns. Their requested artifacts were not produced. This demonstrates
queue retention and preservation of existing work, not successful execution or
proof that every wait was necessary. The evaluator ends these bounded probes
without interpreting a time limit as task completion.

## Why the old queues remain saturated

The 517 Backlog records include **463 with source references, 138 with blocker
text, and 73 with dependency lists**. These are overlapping categories. The
explicit dependency lists contain 100 edges. At the dependency audit, 19 edges
pointed to paused workers and six to archived workers; some targets already had
Done or Verified statuses, so this is not a count of 25 necessarily unresolved blockers. Four
targets were discarded. Those relationships require evidence-based resolution,
not blanket deletion of dependency edges.

The initial driver traces for ops-server, finances and homepage reported no
eligible work while their drain subsets were parked and previous verification
batches remained pending. The code treats **any** nonempty `source_ref` plus a
verification timestamp inside 24 hours as a live external trigger. Nonempty
`blocked_on` text also excludes a backlog card. Thus refreshing provenance or a
stale assumption can preserve the parking state without producing an outcome.
The mvs-infra test separately demonstrated timestamp refresh without promotion.

The 102 Needs You records retain legacy categories: 72 decision, 12 credential,
10 access, four untyped, and one each approval, money, external and judgment.
The new policy guards new transitions; it has not reconciled these old records.
Some questions concern real spending or unavailable credentials, while others
ask ordinary implementation choices. Reconciliation must read the actual ask
and available capabilities; relabeling everything would not grant missing access
or establish that a spending decision was authorized.

The initial runtime/board join also flagged mvs-infra and tubescience as actively
running without a valid active-card attribution. These are observations of live
state, not proof that the worker was performing the test request. Existing work
that progressed during the run is not credited to these probes.

## Cost, cleanup and remaining work

The ten test requests used **12 interpretation calls**, versus a maximum of two
per request. The ten duplicates used **zero**. Provider usage is available for
11 of the 12 calls:

| Measured portion | Fresh input | Cache creation | Cache read | Output |
| --- | ---: | ---: | ---: | ---: |
| Test requests, 11 measured calls | 33 | 91,146 | 9,068 | 4,480 |
| Two unrelated messages arriving during temporary enablement | 3,863 | 7,194 | 0 | 541 |

The measured test portion is **100,247 input/cache tokens**. The latest prompts
were still 27,466–30,789 characters for single local chores. The retrieval/context
size problem remains; a small number of calls alone does not establish token
efficiency. The unrelated messages resolved and are reported separately rather
than silently included in or excluded from the experiment's footprint. Existing
worker execution was concurrent and its cost is not attributed to this test.

The four unclaimed, queued probe chores were moved to Discarded with explicit
reasons after the twenty-minute observation window: AMUX-4691, MAMR-3, MC-2021
and SP-961. Their artifacts remain unproduced and their execution is unmeasured.
This withdraws the experiment; it does not claim completion of its requested
outcome. The six completed chores retain the checked output artifacts. No probe
was left queued to consume worker tokens later, and no running work was interrupted.

Both temporary keys were restored to their exact prior values on every tested
worker after all new receipts had resolved. No new receipt was left pending for
legacy fallback. Execution models, isolation and worker lifecycle settings were
not changed. No original Backlog task was promoted, discarded or force-completed
by the evaluator. Original boards were not bulk migrated.

The next implementation work is the same shared harness work exposed by the
mvs-infra run: bound and normalize retrieval, preserve canonical identity and
task shape, reconcile legacy parking/approval records using actual evidence,
drive real prerequisite remedies, and verify required artifact values before
accepting terminal claims. AF-904 contains the fleet intake/recovery evidence;
AF-393 contains the false-completion evidence. These issues remain open.

Local raw evidence, the independent checker, request receipts, original failed
artifacts, corrected artifacts and exact settings-restoration proofs are in
`/Users/ethan/Documents/Codex/2026-09-10/for/work/fleet-lifecycle-validation-20260915/`.
