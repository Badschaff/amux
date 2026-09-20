# Board Statuses and Transitions

Reference: `crates/amux-core/src/board.rs:TaskStatus` and `board.rs:apply_transition`.

## The 11 Statuses

| Status | Meaning | Next Steps |
|--------|---------|-----------|
| **Backlog** | Parked, not auto-claimed; triage is human's call | `queue` → Todo |
| **Todo** | Queued and dispatchable | `start` → Doing, `claim` to hold it |
| **Doing** | In progress by assigned worker | `submit` → Review, `complete` → Done, `request_input` → NeedsYou, `block` → Blocked |
| **Review** | Awaiting review from peer | `approve` + evidence → Done, `reject` → Doing |
| **NeedsYou** | Stuck on user; exact question on card | `resume` → Doing, `block` → Blocked |
| **Blocked** | Stuck on structured dependency or external condition | `unblock` → Todo |
| **Done** | Worker claims work complete; unverified (Invariant 7) | `verify` + evidence → Verified, `verification_failed` → Doing |
| **Verified** | Harness concludes work done with evidence (terminal) | `discard` → Discarded, `archive` → archived flag |
| **Discarded** | Deliberately abandoned (terminal) | `archive` → archived flag |
| **Armed** | Dormant watch/tripwire waiting on firing event; never auto-picked | `fire` → Todo, `discard` → Discarded |
| **Quarantined** | Execution limits exhausted, anti-livelock terminal (terminal) | `archive` → archived flag |

## Key Transitions (`apply_transition`, line 646+)

- **Lifecycle arc**: Backlog/Todo → Doing → (Review →) Done → Verified
- **Worker holds work** via claim; start auto-claims if unclaimed
- **Review path**: submit/request_review (Doing → Review) → approve (+ evidence) → Done
- **Direct path**: complete (Doing → Done, skips review)
- **Failed verification** revokes Done claim, returns to Doing (line 807)
- **Archive is a flag**, not a status; restore brings card back to its position
- **Terminal statuses** (is_terminal): Verified, Discarded, Quarantined

All transitions gate-checked via `gate_check(task, new_status, effective_gates)`.
