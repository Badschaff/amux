-- AMUX-4580: bill each Claude API response exactly once.
--
-- The indexer deduped a transcript `usage` line only against the line directly
-- before it (py:18133 parity), deliberately not a set, because two different
-- turns can carry identical token counts. Subagent transcripts repeat one API
-- response across NON-adjacent lines, so a single response was billed several
-- times: live rows 886560..886563 were one message (msg_011Cf3qVXATq2kVtV2ceQ7u3)
-- billed four times, and an audited subagent had 7 real calls and 25 rows.
--
-- The transcript already names the response: message.id. Keying on it removes
-- the repeat without the false merge a counts-set would cause, since two real
-- turns never share an id. Rows indexed before this migration have no id and
-- keep their historical (possibly overstated) values; nothing is rewritten.
--
-- ADDCOL: token_ledger message_id TEXT
-- ADDCOL: token_ledger request_id TEXT
CREATE UNIQUE INDEX IF NOT EXISTS idx_token_ledger_message
    ON token_ledger(conversation, message_id) WHERE message_id IS NOT NULL;
