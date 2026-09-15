-- Durable interpretation state belongs to the original message, not a second queue.
-- ADDCOL: cmd_history intake_result TEXT
-- ADDCOL: cmd_history intake_attempts INTEGER NOT NULL DEFAULT 0
-- ADDCOL: cmd_history intake_retry_at INTEGER NOT NULL DEFAULT 0
-- ADDCOL: cmd_history intake_hash TEXT
-- ADDCOL: cmd_history intake_called_at INTEGER NOT NULL DEFAULT 0
CREATE INDEX IF NOT EXISTS idx_cmd_intake_hash ON cmd_history(session,intake_hash);
