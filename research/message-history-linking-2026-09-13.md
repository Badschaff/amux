# Reviewed attribution for retained original messages

AMUX-4486 names six delivered original messages whose card links were never recorded. Migration 67 deliberately does not backfill old NULL links: replaying historical semantic intake can falsely claim old work as Doing. Existing history append/import operations create rows, rather than repairing the original source operand. An explicit source-to-card operation preserves the human request and the reviewer's choice of existing work.

`PUT /api/history/{id}/card` accepts a positive numeric or MSG-prefixed ID and JSON fields `session`, `card_id`, and `reason`. The session is an expected source-session assertion, not the requester's identity. The target must exist and be unarchived. It may have a different owner: linking context must not reassign work or require a duplicate card. Existing application authentication applies. Request actor comes from the normal request-log headers.

Example (substitute a personally reviewed source/card; do not run blindly):

```json
{"session":"original-lane","card_id":"EXISTING-1","reason":"Reviewed the complete original request and confirmed this card carries its work"}
```

The store transaction updates the original message link and clears capture_pending, appends an attributed rationale to the card log, advances its revisions, and writes MessageUpdated/TaskUpdated events atomically. A repeated same link is a no-op; a different existing link returns 409. Wrong expected session, invalid/missing ID, missing/archived target, empty/oversized rationale and unknown fields are rejected. Original text, timestamp and delivery metadata are unchanged. Card owner, status and description are unchanged. No message or card is created, no steering command is sent, and no task.claimed runtime event is emitted.

Successful and rejected handled requests emit explicit_message_card_link with operand IDs, actor, status, measured and count. Transaction errors emit WARN message_card_link_failed. History GET/list now expose the persisted capture_pending marker. These distinguish capture recovery from already delivered command state.

Tests exercise the actual router, cross-owner existing card, idempotent repeat, preserved history/card state and zero steering/claim rows. An SQLite trigger rejects the card audit write after the message UPDATE, proving transaction rollback; the test asserts the actual WARN includes the original message/card IDs and measured=false. Removing the route produces a 404 at the positive success assertion (0 passed / 1 failed), then restores. Final group/catalog/gate evidence is recorded on AMUX-4486 and AF-748.

Limits: this operation records reviewed source attribution; it does not prove that the chosen card's work is finished. It does not repair the inherited post-link runtime-attribution crash boundary; AF-758 tracks that separate source-audited gap. Six original links remain untouched until this API is reviewed, published and live and their target work is explicitly reconciled. No full-board, simulator or UI verification claim.

Independent amux-research review found a P2 acknowledgement mismatch in c0c75620: changed alone is not understood by interaction middleware. The new full api::router regression first failed on a real persisted receipt with phase unknown, applied_writes1 and200 acknowledgement. Corrected responses retain changed and add applied false/true. First/repeat/refusal receipts must be applied/noop/refused respectively; successful calls must emit no interaction_outcome warning, with a real refusal-log positive control proving collection. The original11 router-only tests were green while this integration boundary was broken.
