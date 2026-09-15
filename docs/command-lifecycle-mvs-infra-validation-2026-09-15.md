# Real-backlog validation: mvs-infra, September 15, 2026

**Result: failed before execution.** The new command controller did not produce
an admissible plan for a refinement of an existing task on this real board.
Both allowed Haiku attempts failed. This is not a successful backlog drain.

The running server was `d01b6ed8a625`, build `c85d636017348546`, at both the
initial and final observations. The test used the existing active mvs-infra
worker, retained its execution model and pause state, and temporarily enabled
the staged controller with Haiku 4.5 for interpretation. No new worker was
created. This was the owner's separately requested real-worker test after the
three earlier fresh-worker trials.

## Starting board

The uncapped, full, non-archived API snapshot contained 1,418 records:

| State | Count |
| --- | ---: |
| Backlog | 121 |
| To do | 1 |
| Doing | 1 |
| Review | 1 |
| Needs You | 8 |
| Armed | 1 |
| Done | 720 |
| Verified | 44 |
| Discarded | 521 |

Among the 121 Backlog items, 118 had `source_ref`, 95 had `blocked_on` text,
17 had explicit dependency edges, and none had explicit `acceptance_criteria`.
These categories overlap. A reference or missing criteria alone does not prove
that work is blocked, ready, or complete.

MI-5797 already tracked backlog triage. Its runtime attribution initially still
pointed at the invalid older claim MI-5761. The test deliberately reused the
existing task rather than adding another broad cleanup task.

## Request and receipts

The request refined MI-5797 into one bounded chore: script the complete board
inventory, deeply review at most five representative Backlog items, attempt up
to two independently ready existing local outcomes, and write a report. It
explicitly prohibited a new tracking card or epic, production changes, customer
contact, paid infrastructure, heavy remote builds, and resuming other paused
workers. Completing a partial local outcome would not complete a broader card.

Two identical deliveries with distinct transport IDs tested deduplication:

| Receipt | Acknowledgment | Planner calls | Result |
| --- | ---: | ---: | --- |
| MSG-63813 | 23 ms | 2 | Both plans rejected before graph mutation |
| MSG-63814 | 30 ms | 0 | Waited on the original interpretation |

The ongoing worker finished MI-5797 before the planner read its candidates.
The candidates correctly said that it was Done. Nevertheless, both plans used
`update` on that completed task and proposed four new preparatory cards in
front of it. Both were rejected with `completed matches require output
verification`. The repair repeated the same mistake despite receiving the
previous response and the error. It began about six minutes after the first
attempt's start, including the configured five-minute backoff and scheduler
delay.

No graph was committed, no test cards were created, and no work from the test
request was dispatched. The requested worker report was absent. Duplicate
suppression and the pre-mutation completion guard worked; automatic refinement,
decomposition, execution and recovery did not complete. No third planner call
was made.

## Token cost and retrieval defect

Provider usage was available for both calls:

| Attempt | Fresh input | Cache creation | Cache read | Output | Thinking |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 3 | 9,141 | 0 | 1,491 | 0 |
| 2 | 3 | 10,652 | 0 | 1,467 | 0 |
| Total | 6 | 19,793 | 0 | 2,958 | 0 |

That is **19,799 input/cache tokens and 2,958 output tokens without an accepted
plan**. Character counts below are separate from measured tokens. Existing
worker execution was concurrent, so its token ledger is not a clean benchmark
of this request and is not attributed to it.

The first call searched 8,714 available agent-owned records and selected eight
candidates. Seven were from another worker. Their titles contained entire
multi-paragraph write-ups: the eight titles totaled 18,585 characters, and the
prompt totaled 29,847 characters. The explicitly named MI-5797 ranked second.
The retry prompt grew to 35,861 characters. Limiting candidate count did not
bound context size or ensure relevance: unnormalized title overlap outweighed
the explicitly named target's fixed score bonus.

## What the existing worker actually did

During observation, the worker's pre-existing Doing, Review, and To do items
reached Done. Done increased from 720 to 723; Backlog remained 121. These were
existing work, not execution of the rejected request. The recorded evidence on
MI-5795 and MI-5798 distinguishes Done from pending live verification; this
test did not independently run their production/CI verification gates.

MI-5797's own final evidence recorded nine discarded cards, 121 refreshed
verification timestamps, and **zero promoted cards**. The baseline already had
121 Backlog items, so the earlier discards are not credited as this test's
progress. Refreshing timestamps made the stale-reference metric quieter while
leaving the execution problem unresolved.

At the final observation, mvs-infra was active in lifecycle but idle in runtime.
The driver reported:

- Zero eligible To do cards and no Doing/Review card to advance.
- Drain enabled, but all 113 candidates considered by that path parked on a
  human requirement or a `source_ref` verified within 24 hours; zero free.
- 535 Done cards awaiting verification, with the previous verification batch
  still pending behind a 24-hour retry.
- The backlog-triage nudge already sent within its cooldown.

The 113 is the drain path's considered population, not the full Backlog count
of 121. Neither number establishes that every blocker is legitimate.

## Cleanup and retained failure

The previous worker settings were restored; its execution model and lifecycle
were unchanged. Both failed test receipts were explicitly linked through the
history API to the existing **open AF-904 intake defect**, with an audit reason
stating that the requested work had not executed. Their raw failed responses
and usage remained retained. No original backlog card was promoted, closed or
rewritten by the evaluator.

The receipt links resolved pending capture before disabling the temporary
controller. This matters because the current disabled-controller path can fall
through to legacy capture; an already-failed request must not silently acquire
a fallback task during cleanup. The link is failure tracking, not completion of
MI-5797 or of the requested validation outcome.

## Required follow-up

1. Make refinement granularity and allowed canonical operations enforceable;
   valid JSON and high confidence do not guarantee the requested task shape.
2. Prioritize explicitly referenced task identities and bound/normalize candidate
   fields. Preserve canonical requirements while avoiding full unrelated
   documents masquerading as titles.
3. Distinguish verified blocker evidence from a freshness timestamp. Queue the
   real prerequisite/remedy and verification work on relevant state changes;
   a refreshed timestamp or a broad cooldown is not progress toward completion.
4. Keep durable ownership of staged receipts across feature disable/rollback,
   with an explicit failed/cancelled disposition that cannot invoke legacy
   fallback capture.

This test did not implement those follow-ups or establish that the controller is
ready for unattended rollout. AF-904 remains open with the new evidence.

Local raw evidence is in
`/Users/ethan/Documents/Codex/2026-09-10/for/work/mvs-infra-validation-20260915/`.
It includes full before/after snapshots, both requests and receipts, retained
responses, provider usage, driver decisions and settings-restoration proof.
Raw card prose is kept local rather than copied into this public report.
