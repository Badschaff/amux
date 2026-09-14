# Commit-nudge self-attribution investigation

Scope: bounded AF-746 ledger correction, prompted by the complete mixpeek-frustrations report on 2026-09-12. No writes to the reported Mixpeek checkout. Shared-root peer drafts are excluded.

The six historical studio paths are not present in this server's current observation store (read-only SQLite inspection: two records total, zero studio records). Their exact historical provenance is therefore unconfirmed. File age and lane assignment alone do not establish which guard mechanism produced the claim.

Independently reproducible source boundary: requester-only mtime observations enter `GuardInputs.mine` without a writer record. With unstaged changes they become a shared row with an unknown peer; otherwise they disappear from the negative ownership lists. Both forms reach the nudge as “your edit record.” Existing MOS-33 tests protect against observations naming peers, but deliberately retained this requester fallback. Unclaimed work remains committable when cotenants are visible, so removing the ownership assertion does not require a new permission gate.

A second defect at the same boundary: the guard's `undecided` is a boolean, but the nudge decoded it as a path array. It also inferred ownership for paths omitted by the classifier cap. Coverage must travel with the verdict before absence from negative lists can be used.

Tests exercise `apply_observed -> classify -> Envelope -> ownership_from_verdict -> build`, with real writer controls and both staged/unstaged shapes. Additional controls reject undecided, disabled and truncated verdicts. Validation results are recorded below.

Separate instrument report: on this Darwin host, a controlled two-file fixture (one current, one 40 days old) returned only the current file for both `find -newermt '6 hours ago'` and `'30 days ago'`, exit 0. The reporter's zero-result symptom remains unreproduced; this correction does not change `find` or its hooks.

Validation on clean detached `3055392438687f84787925c7dacdfbddd5e54a70`: all-target workspace Clippy passed (43.78s); installed-hook compatibility 6/6. New boundary tests first failed 0/2 on the old behavior, then passed 2/2. Existing guard tests 76/76 and nudge tests 53/53 passed. The clean library run passed 2,358, failed six and ignored eight. All 58 integration targets were reached across the initial run and its remaining-target continuation: 340 passed, one failed, 24 ignored. All seven failures were the live memory-admission check or worker-start 503s. The running pre-fix `3d79ad58d378` also reported admission deny with about 53GB swap. This is not a green broad-suite claim. The wrapper confirmed clean source and no concurrent builder during the clean runs.

Full logs: `scratch/ios-simulator-review/nudge-authorship-clean-server.log`, `nudge-authorship-clean-integration.log`, `nudge-authorship-clean-integration-remaining.log`, and `nudge-authorship-clean-clippy.log`. The full exact `find . -path ./.git -prune -o -type f -newermt ... -print` control also passed both windows with three inputs (current, 40-day-old, and a current file under .git); only the current non-.git file was selected. Artifact: `scratch/ios-simulator-review/nudge-find-control.json`.
