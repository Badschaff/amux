-- Add worktree and fan_out flags to schedules.
-- worktree: each firing creates an ephemeral worktree session.
-- fan_out: the command is treated as priorities and fanned out via /api/board/launch.
ALTER TABLE schedules ADD COLUMN worktree INTEGER NOT NULL DEFAULT 0;
ALTER TABLE schedules ADD COLUMN fan_out INTEGER NOT NULL DEFAULT 0;
ALTER TABLE schedules ADD COLUMN fan_out_model TEXT;
