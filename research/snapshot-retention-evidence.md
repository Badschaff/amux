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
