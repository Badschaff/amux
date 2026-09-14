# Direct submission evidence in history readers — AF-889

The message sweep found MSG-59389 and MSG-59393 recorded with `delivery=direct`
and `submit_verdict=stuck`. Both `frustration_scan.py` and `GET /api/history/{id}`
returned `delivered`. The shared erroneous assumption was that inserting a direct
record proved submission. The writer already preserves the stronger outcome:
`confirmed`, `retried`, `stuck` or `unverified`. No sender change or replay is needed.

Both direct readers now honor that outcome: confirmed/retried means delivered,
stuck means not delivered, and unverified/missing/unrecognized values mean unknown.
The scanner selects the actual column in its existing bounded SQLite query and
retains it in each emitted candidate. Old schemas remain readable using NULL,
which is unknown rather than invented certainty. Positive direct fixtures now
carry explicit confirmed outcomes; this keeps their genuine double-delivery
controls meaningful rather than preserving an unsupported historical assumption.

The scanner's payload includes a measured population, unconfirmed-direct count
and whether the verdict column exists. A nonzero population emits
`friction_direct_submission_unconfirmed` to `$AMUX_HOME/logs/friction-sweep.log`;
audit failures stay visible on stderr. The history endpoint emits a structured
`history_delivery_not_confirmed` warning with message ID, stored verdict, computed
outcome, measured=true and n_considered=1. No message bodies are logged by these
new diagnostics.

Seven complete scanner query/output tests against the original exact scanner:
2 passed, 5 failed. Corrected:7 passed,0 failed. Full existing scan suite including
those tests:18 passed,0 failed. A fixture initially used wording below the marker
threshold after stuck pairs were correctly excluded from double-delivery; its
wording was strengthened to keep both actual output candidates observable. The
final red/green pair uses the same corrected specimen.

The actual history endpoint regression seeds six direct rows in a temporary
store (confirmed, stuck, retried, unverified, NULL, future value) and GETs each
through the real router. Before correction:0 passed,1 failed specifically at
row2, delivered versus not-delivered despite stuck. An earlier source-label
assertion failed first on row1; that weaker negative is retained separately and
is not the behavioral negative-control claim. Corrected full history group:
13 passed,0 failed with four test threads, including existing full-router receipt
and source-link safety tests. Raw evidence lives in scratch/sweep-evidence:
`delivery-final-red.log`, `delivery-final-green.log`, `messages-suite.log`,
`history-direct-behavior-red.log`, `history-green.log`.

Read-only corrected live-store scan reports both exact RTSP messages as
not-delivered with their stuck verdicts intact. It does not prove why native
submission stuck or authorize blind resend. Existing recovery work remains on
AF-735. The queued-message steering join is unchanged: timestamp-based legacy
inference, outcome/identity ambiguity and reply visibility are not certified by
this direct-path correction. It is not a claim that every delivery observer is
now exact.

Originating session is amux-frustrations. Final source/CI/live verification and
independent peer evidence remain on AF-889; its ledger entry is retained until
originating-session agreement and all resolved verification gates hold.
