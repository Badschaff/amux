# AF-720: match the nudge to its attribution evidence

Zero-attribution git-hygiene notices now tell the recipient to preserve the
files and continue their task. They show the complete count and a ten-path
preview, with the omitted count stated. Full safety guidance and the complete
path/attribution inventory remain retrievable through the existing prefs GET
endpoint. One latest record per lane replaces the previous record; the notice
and record both carry an observation timestamp. A later record is explicitly
identified as potentially newer than the delivered notice.

Any positively attributed path, including a shared path beyond the displayed
preview or in another freshness section, retains the full existing guidance.
Attribution is about edit records, not ownership of current dirty bytes. Partial
attribution stays disclosed. No landed-path match count is invented. This
change neither restores files nor stages them, and does not suppress the nudge.

## Measurement before choosing the change

The previous investigation searched `cmd_history` and found only peer messages
discussing nudges. The actual retained bodies are in `steering_history`, keyed
by `guard='commit-nudge'`. A read-only snapshot contained 733 records across
57 lanes, with delivered_at spanning 1787540212.431606 through 1789331799.875026.

The bounded historical classifier reads exact renderer section headers and
complete generated-file lists. It does not interpret sentiment or arbitrary
approval-shaped prose. Positive attribution in any section is positive; zero
requires every primary section to be readable. Truncated generated lists and
unrecognized formats remain unknown. Its nine controls include a positive in
a later section, a truncated list, missing observation footer, and ordinary
prose that mentions attribution. Re-running the saved classifier reproduces
all 733 row verdicts.

| Population | Explicit zero | Positive | Unknown |
|---|---:|---:|---:|
| All 733 retained records | 591 | 27 | 115 |
| 511 records with a `sent` outcome | 375 | 21 | 115 |
| Distinct lanes in the sent-outcome categories | 53 | 10 | 36 |

Categories of lanes overlap. The other 222 records have null outcomes, which
are not certified deliveries. The 375 zero-attribution sent records carried
4,046,295 characters of text. This is a retained-history population, not a
claim of complete historical fleet coverage. These are rendered attribution
claims, not fresh ownership verification. The reporter's five-nudge series
remains separately attributed and is not silently equated with this sample.

This supports shortening zero-attribution notices while preserving the
positive case. It does not support blanket suppression or interpreting a
truncated path list as zero.

## Mechanism and observability

The same guard predicate supplies section headers, commit-worthy filtering,
and the new whole-population count. SAME paths are excluded, and duplicate
paths do not inflate the count. The full notice is prepared by the unchanged
safety renderer before selecting the delivery format.

Compact delivery requires successful persistence of its full evidence. A
SQLite write failure emits `commit_nudge_detail_unavailable` and sends the
full guidance instead of a broken link. The actual queue result emits
`commit_nudge_enqueue` with measured, n_considered, n_with_edit_record,
n_without_edit_record, attribution_partial, format, chars/full_chars,
detail_stored, queued, message_id and refusal. `queued=true` means accepted
into steering, not proof the model consumed it. Refusal no longer increments
the sweep's queued count. Existing daily-cap timing is unchanged; a refused
enqueue can still consume that day's cap.

No new endpoint, migration, classifier model call, or lane-specific exception
was added. The full detail uses the existing key/value store and read API.

## Evidence and limits

Evidence is retained under `scratch/af720-evidence/`: read-only
`retained-nudges.json`, `classify_history.py`, `history-reproduced.json`,
and the command logs. The initial compile failed on an unavailable `url`
dependency; the correction uses the existing reqwest URL re-export.

The first two delivery regressions passed, exercising actual private SQLite
storage, steering queue, fallback on a real SQLite trigger failure, and
refusal of a nonexistent worker. The expanded regression also follows the
actual notice URI through the existing prefs HTTP handler and compares the
retrieved evidence. `scripts/safe-cargo.sh test -p amux-server --lib
runtime_jobs::commit_nudge:: -- --test-threads=4` passed 55 tests, zero failed.
This is the nudge population, not the full server suite.

Two deliberate mutations compiled and failed their targeted test (0 passed,
1 failed each): forcing the old full text at the actual enqueue boundary,
and counting attribution only within the first ten paths. `scripts/mutate.sh
run` reverted each mutation in its trap; before/after source SHA-256 matched.
See `full-payload-mutation.log`, `visible-sample-mutation.log`, and
`mutation-results.json`. Restored-source release gates are recorded in
`gates.json`: restored-source nudge tests 55 passed/0 failed, workspace check
exit 0, and workspace/all-target Clippy with `-D warnings` exit 0. These
fixtures do not send a production nudge or mutate a
peer's checkout. Publication, independent review, fresh live behavior and
resolved Verified gates remain separate requirements.

## Review correction: origin availability

Independent amux-research review of published `5d1651cd` found a P2 wording
defect: the compact lede claimed that paths differ from origin, although the
existing filter deliberately retains paths when origin or a local operand
cannot be read. The footer did not make that affirmative lede truthful.

The correction calls these "dirty paths considered" and labels the fallback
"dirty in this checkout". It preserves the existing provenance and classified
history labels. The detail and actual enqueue log now name the measurement
scope as `recipient_edit_records`; the log also records `origin_provenance`.
These attribution counts are not a claim that every origin comparison ran.

Two new real-Git regressions failed before the wording change (0 passed,
2 failed): a repository with no origin, and a repository with a readable origin
but a failed local `hash-object` operand. The latter includes both a genuinely
changed/readable file and a SAME file that the actual filter removes. Neither
test replaces the filesystem probe with a fabricated successful comparison.
See `provenance-red.log` and the subsequent `provenance-*` gates.
After correction, the full nudge group passed 57/0 with four threads;
workspace check and all-target Clippy with `-D warnings` both exited 0.

The first candidate is live at build `f9ac99cb032046d9`, but that adoption is
not review approval. The original historical measurement and approved portions
of the independent review remain valid. The P2 correction needs an exact new
review and publication readback before this card can be treated as complete.
