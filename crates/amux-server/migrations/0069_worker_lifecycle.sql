-- 0069_worker_lifecycle.sql — First-class worker lifecycle (active/paused/archived/deleted).
--
-- Replaces the soft-delete sidecar hack (deleted_at inside the state JSON) and
-- the env-file CC_ARCHIVED flag with one canonical lifecycle column on the
-- workers table. Orthogonal to WorkerState (execution state): a worker can be
-- active+stopped, paused+stopped, or archived+stopped.
--
-- Migration 0003's soft-delete deviation (queries.rs module docs) is resolved
-- here: deleted_at is promoted from a JSON sidecar to a real column value.

-- ADDCOL: _amux_workers lifecycle TEXT NOT NULL DEFAULT 'active'

-- Migrate existing soft-deleted rows.
UPDATE _amux_workers
   SET lifecycle = 'deleted'
 WHERE json_extract(state, '$.deleted_at') IS NOT NULL;

-- Clean the sidecar from state JSON now that lifecycle carries the truth.
UPDATE _amux_workers
   SET state = json_remove(state, '$.deleted_at')
 WHERE json_extract(state, '$.deleted_at') IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_amux_workers_lifecycle ON _amux_workers(lifecycle);
