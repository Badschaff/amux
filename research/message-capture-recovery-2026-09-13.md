# Durable recovery for interrupted message capture (AMUX-4486)

A substantive message was committed to `cmd_history` before asynchronous semantic intake. Cancelling the request while it waited for the lane intake lock left the durable message without its board consequence. The pre-fix test positively observed the committed row, cancelled the recording future, and failed its missing-card assertion (0 passed, 1 failed). This reproduces a failure path; it does not establish why the six historical AMUX-4486 messages lost their links.

The message transaction now sets `capture_pending`. Migration 0067 defaults existing rows to zero, so an arbitrary old NULL card link is not treated as permission to create new work. The existing semantic intake reads the retained original message; card creation/association, the source link, and clearing pending commit together. Failed transactions keep the original pending row. Both the 200-row per-session history cap and the age-based storage sweep preserve pending rows. The age sweep still refuses a timestamp cutoff that would empty the original population; its reported survivor count includes protected messages. The queued completion path clears pending when it links a message too.

The registered `message-capture` periodic job runs every 30 seconds (existing isolation and disable conventions apply), scans at most 16 pending IDs per tick, and rotates past failed batches. Each recovery future is bounded at 120 seconds including lane-lock wait. A timeout drops the future and leaves its durable input pending; an already-running blocking model subprocess remains governed by its existing provider timeout. Recovery never invokes command delivery or inserts replacement history. The scan cursor is in memory; a restart resets its position, while pending work survives in SQLite.

Logs distinguish a positive pending population (`capture_recovery_pending`, IDs/count), a failed association transaction (`capture_retry_pending`, message ID), unavailable storage (`capture_recovery_unmeasured`), timeout, and interrupted recovery. Successful links retain existing capture and task-attribution events. The actor transaction rechecks the original row before creating anything, and the existing lane lock serializes concurrent intake.

Validation so far:

- Pre-fix cancellation specimen on 12e12397: 0 passed, 1 failed, original committed message remains unlinked.
- Cancellation plus database close/reopen and repeated recovery: 1 passed, 0 failed. Exactly one original message and one card; pending clears.
- First failure/retry/control/log group: 3 passed, 0 failed. A trigger rejecting the card link rolls back card creation; retry creates one card/claim and zero queued commands. Historical NULLs, control and stuck prompts remain uncaptured. Actual unavailable-storage log is measured=false with zero considered.
- Broader capture group including batch fairness, both retention paths, and subscriber controls: 42 passed, 0 failed with four test threads.
- Production pending-query negative control: 0 passed, 1 failed at the original missing-card assertion; exact mutation restored.
- The first retention fixture expected 500 ordinary rows, but the real cap is 200; corrected to assert 201 survivors (200 ordinary plus one pending), not to weaken retention.
- A parallel warning assertion initially missed the event despite a positively confirmed failed write and pending row. The installed tracing-core 0.1.36 single-dispatch registration shortcut uses the current thread default; another thread without a subscriber can first register that callsite as Never. The test collector retains a second uninstalled dispatch so registration considers all live collectors. A dedicated cross-thread first-use test and subscriber-positive-control assert the instrument actually works; application logging is unchanged.
- Removing the collector registration peer fails its exact cross-thread control: 0 passed, 1 failed, callsite stays disabled; mutation restored.
- Clean workspace gates and independent review are pending at this writing; durable board evidence will record exact results.

Scope limits: reopening a temporary database is not a fresh OS-process lifecycle test. These are source/server tests, not mobile/desktop visual verification. The six original messages 59384, 59391, 59392, 59397, 59416 and 59446 require full-source review and explicit reconciliation; this migration deliberately does not backfill them. Neither AMUX-4486 nor the full AF-748 board drain is complete on this patch alone.

## Live registry follow-up

The pushed c6242e22 was observed live at stable build36e3f03eb7487ab1 with message-capture spawned and ticking. Runtime registration worked, but its catalog row was missing: documented=false, purpose=null and no displayed disable control. The follow-up centralizes the job ID in the existing registry and adds its purpose and AMUX_MESSAGE_CAPTURE_SECS=0 control. Positive values do not configure the fixed cadence.

A subsequent same-build observation showed in_flight=true, last_tick_age_s90.96, last_tick_ms120003.61 and status=hung. The30second cadence implies a90second health threshold, shorter than the permitted120second attempt. A90second cadence gives the unchanged registry rule a240second budget, covering both a normal90second idle interval and the120second attempt. A60second draft was insufficient: its165second budget did not cover both periods. Attempt timeout remains120seconds; no global threshold is relaxed.

Named source constants drive the runtime and a regression that calls the actual registry classifier. Normal idle+attempt must remain ok; a real overrun must still be hung. Restoring the old30second cadence must fail. A startup INFO records interval, attempt timeout, health budget and measured/count fields. This does not claim pending model work succeeded. Original six-link reconciliation and AF-758's inherited attribution boundary remain separate.
