# AF-790: snapshot count is evidence, not a deletion instruction

The disk-pressure detector attached the same advice to every successful snapshot
count, including zero: all file deletion was said to recover nothing, followed
by a privileged snapshot-thinning command. The reclaim view repeated the blanket
no-recovery claim. A failed snapshot probe disappeared from the disk finding,
while successful empty stdout was counted as zero. These are amux instrument
defects distinct from macOS retaining blocks in snapshots.

The correction uses one Rust retention explanation for disk findings, stored
reclaim findings, snapshot-list notes, and post-purge notes. The dashboard banner
uses the same qualified explanation and no longer displays a thinning command.
Zero means no local snapshots were observed; a positive count establishes
possible retention, not retained bytes or the cause of every failed reclamation.
No count recommends deleting backups. Missing, failed, or unrecognized listings
remain explicitly unmeasured. Disk findings carry `apfs_local_snapshots_measured`,
`apfs_local_snapshots_n_considered`, `apfs_retention`, and an unavailable reason
when needed. The actual `disk_snapshot_context` log carries the same states.
The recheck prints the native listing instead of counting its header with `wc`.

The parser requires a recognizable listing header before it can report zero.
Empty output, unexpected diagnostics, invalid bytes, or an unsupported output
format yield no measurement. A header with no snapshot rows is measured zero;
recognized snapshot rows are counted individually. Localized or changed native
output is intentionally unknown until supported, rather than a quiet disk.

## Current observation and the original claim

Read-only probes on 2026-09-13 found 24 local snapshots and one configured local
backup destination without a mount point. `tmutil latestbackup -t` exited zero
but returned no timestamp. Backup age and how long the destination has been
absent are therefore **unmeasured**, not zero and not an established outage.
`scratch/af790-evidence/read-only-probes.json` records that distinction without
storing destination names, identifiers, or network URLs. The native listing is
retained separately; no backup or snapshot mutation was performed.

A subsequent native listing and read-only storage diagnostic were bracketed by
stable server commit `5af2526fb60d`, build `8b5f92f8f904ecee`, retained in
`scratch/af790-evidence/live-storage.json`. That source predates this correction.
The diagnostic's `n_considered` is its storage population, not a snapshot count.

[Apple's local snapshot documentation](https://support.apple.com/en-us/102154)
describes approximately hourly snapshots retained for a day and automatic
removal as they age or space is needed. Thus the 24-snapshot observation does
not itself prove an abnormally long backup-disk absence. It also does not
disprove the original measured failure to recover space promptly. The original
storage-audit session must adjudicate that remaining requirement; this change
does not invent a backup-age threshold or modify backup policy.

The recorded historical pointer `AMUX-2701` currently resolves to an unrelated
discarded Gmail route-invariant finding. Its closure cannot establish this
incident's resolution or author agreement. That mismatch is recorded on AF-790;
the original ledger text and author label remain intact.

## Regression

Before correction, after extracting the unchanged disk advice into a helper,
`scripts/safe-cargo.sh test -p amux-server --lib snapshot_context_distinguishes
-- --nocapture` compiled and failed: 0 passed, 1 failed. The assertion prints
the actual zero-count evidence recommending `Thin them first` and its privileged
command. See `scratch/af790-evidence/snapshot-context-red.log`.

The regression checks zero, 24, and unavailable observations through the exact
evidence function used by `detect_disk`, including actual log output. Parser
controls distinguish a real empty listing, a two-snapshot listing, empty output,
diagnostics, malformed headers, and invalid bytes. These are instrument tests;
they neither delete files nor thin snapshots or trigger production disk alarms.

Results: snapshot-filter tests 11 passed, including both new regressions;
autofix unit group 136 passed, 0 failed, 1 ignored; reclaim 16 passed, 0 failed;
storage 17 passed, 0 failed. Restoring just the old marker-count parser through
`scripts/mutate.sh run` compiled then failed the listing regression (0 passed,
1 failed): empty output became `Some(0)`. The inverse trap restored the source
hash. Logs are under `scratch/af790-evidence/`.

Browser regression `e2e/reclaim-snapshot-context.spec.ts`: old committed app.js
from `5af2526f` failed on mobile because the visible banner contained the thinning
command. Candidate app.js passed desktop, mobile Chromium, and iPhone-profile
WebKit: 3 passed. All reclaim requests used read-only fixtures, including an old
stored finding with unsafe prose. The test checks visible count, qualified text,
absence of the command, and viewport geometry. All three screenshots were opened
and inspected; the complete note is readable and on screen at phone width.
This is browser emulation, not native iOS Simulator testing. The API was a private
copy of the installed `5af2526f` binary through the existing isolated lifecycle
wrapper; candidate JavaScript was explicitly injected and hashed. It does not
constitute execution of the changed Rust API responses.

JavaScript syntax and state-bundle freshness checks passed. SPA lint passed with
0 errors and 48 existing warnings after supplying the author worktree's missing
dependency link; the initial missing-eslint attempt is retained as a tooling
failure, not a product failure. APP_VER and CACHE both advance to 0.9.939.

Remaining scope: reclaim's existing native snapshot reader still has its own
unbounded command/empty-on-failure behavior; the new explicit measurement fields
belong to the disk-pressure detector, not that older reader. The snapshot-list
API retains its manual command metadata for compatibility and now marks it as
requiring backup review. No thinning capability was invoked. Backup absence
duration remains unmeasured; reading the protected Time Machine preferences also
failed with Operation not permitted. Neither backup permissions nor policy were
changed. These limits must remain on AF-790 before any full-card closure claim.

This is bounded source/evidence work. Full CI, final production behavior, and
originating-session agreement remain separate gates. AF-790's ledger entry
must not be retired solely on this correction or independent review.


## Reclaim probe follow-up to 263f0bad

The remaining reader gap is corrected in the follow-up: reclaim and autofix use
one native listing parser/probe. The deadline covers process lifetime and stdout
consumption, including a descendant retaining the pipe after its parent exits.
Reads are nonblocking with a 1 MiB ceiling; failure paths kill/reap the owned
child. Async reclaim handlers dispatch the bounded call off the executor.

Unknown is preserved as a nullable count/list, with measurement metadata in the
snapshot response and nullable persisted scan count. Scan completion records the
final probe (rather than retaining the potentially different initial count).
Purge responses retain unknown and explain it. No purge is invoked by these tests.
The Disk Cleanup view shows unavailable snapshot status at desktop/phone widths.
APP_VER and CACHE advance together to 0.9.940.

`storage_snapshot_probe` logs measured/n_considered for every completed native
attempt, with WARN and why_unmeasured for unavailable results. Deadline and output
ceiling failures have separate diagnostic names. Historical stored zero counts
cannot be retrospectively distinguished from the old reader's failures; these
are not re-certified by the new reader. Backup age and destination absence
remain unmeasured; this change does not infer either from snapshot count.

Evidence is retained in scratch/af790-evidence/probe-*; final commands/results
are recorded below once checks finish. This is a bounded instrumentation change,
not originating storage-audit agreement, full CI, or permission to retire the
original ledger entry.


Follow-up failing controls and browser results:
- `scripts/mutate.sh run` replacing the shared helper with exact263f's prior
  helper, then `safe-cargo.sh test -p amux-server --lib
  snapshot_probe_bounds_running_child_and_inherited_stdout -- --nocapture`:
  compiled, 0 passed/1 failed on the inherited stdout operand. Exit101;
  byte-scoped trap restored the source hash.
- Mutation adding `.or(Some(0))` to the actual snapshot payload's count:
  `safe-cargo.sh test -p amux-server --lib
  snapshot_response_never_turns_failed_measurement_into_zero -- --nocapture`:
  compiled, 0 passed/1 failed (unknown mislabeled measured). Exit101;
  byte-scoped trap restored source hash.
- `playwright test --config=scratch/af790-browser.config.ts
  reclaim-snapshot-context.spec.ts`: 6 passed on desktop/mobile/WebKit,
  positive and unavailable listings. Actual app SHA256
  3a9335151eb71564283a07c9c2a8a960eb63be21439240f87fef3b7c808892d9.
  Three unavailable-state screenshots opened: note readable and in viewport.
  The exact263f app fails the same mobile unavailable case because no warning
  is rendered. The private API binary remains5af; all reclaim API requests
  are stubbed GET-only. This is neither native Simulator nor new Rust API proof.
- JS syntax and state bundle freshness exit0; SPA lint0errors/48existingwarnings.
- Read-only production bracket after publishing263f still reads5af2526fb60d,
  build8b5f92f8f904ecee,25snapshots. No adoption proof inferred from that result.


The first expanded storage group returned20passed/1failed: the new log assertion
captured an empty buffer under concurrent process-wide tracing callsite changes.
The assertion now runs in an exact-name child of the test binary, retaining both
unknown/WARN and measured/INFO controls; the parent requires a successful
nonempty one-test result. This avoids mutating process environment/subscribers
shared with other test cases. That isolated log control passed in the next
four-thread storage run. That run instead failed a timing assertion in the size
fixture: a long shell echo loop was an unsuitable way to require a byte ceiling
before a deadline. The final fixture uses finite `/bin/dd` streams (128 KiB
succeeds, 2 MiB must be rejected by the 1 MiB ceiling), so without the ceiling
the second stream can finish and return bytes. The probe drains available data
without sleeping between successful reads; it sleeps only when no data progressed.


A final caller search also found the same blanket "until they are thinned"
claim in disk_watch's critical-pressure WARN. Its text is now qualified in the
same way; thresholds, severity and dispatch remain unchanged. This is a log-text
correction, not a new pressure detector or proof of backup destination absence.
The autofix source-scan control was updated for its actual remaining local
subprocess (du_one); shared snapshot helper behavior stays covered by the native
runtime tests. Its prior expectation of two local helper call sites failed
135passed/1failed/1ignored after the helper moved, before the control was updated.


Final author checks for the follow-up:
- `scripts/safe-cargo.sh test -p amux-server --lib runtime_jobs::storage::tests -- --test-threads=4`:21passed/0failed.
- Same command, `runtime_jobs::autofix::tests`:136passed/0failed/1ignored.
- Same command, `api::reclaim::tests`:17passed/0failed.
- Same command, `runtime_jobs::disk_watch::tests`:22passed/0failed.
- `scripts/safe-cargo.sh check --workspace`:exit0; workspace/all-target Clippy with `-D warnings`:exit0.
These are focused groups, not a full-server or CI claim. The final commit hook
and clean snapshot gates are recorded on AF-790 separately.


Integration: source14342f70 is applied over published9e7582f8, which is a direct
child of263f0bad. The upstream MDAI path fix is preserved. Both branches had
selected940, so integration advances APP_VER/CACHE to941. No other manual
semantic resolution. A fresh authenticated health/disk identity bracket showed
live9e7582f8/build9db97c9cec77471c, matching its installed binary and receipt.
The earlier suspected receipt mismatch was disproved; no publication-seam defect
is inferred from comparing that image with an older5af health sample.

Integration self-tests: storage21/0,reclaim17/0,upstream MDAI dashboard asset
guard1/0, browser6/0 desktop/mobile/WebKit, state freshness exit0 and SPA lint
0errors/48existingwarnings. Latest integrated mobile/desktop unavailable-state
screenshots opened and legible. Eight strict Git-blob comparisons preserve the
authored Rust/test files and upstream API/static-file/asset-guard files.
