-- A delivered message and its pending board consequence commit together.
-- Old NULL card links are deliberately not interpreted as pending work.
ALTER TABLE cmd_history ADD COLUMN capture_pending INTEGER NOT NULL DEFAULT 0;
CREATE INDEX idx_cmd_history_capture_pending ON cmd_history(id) WHERE capture_pending != 0;
