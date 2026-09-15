-- Host utilization history (DESKT-39). Every host instrument amux had was a
-- spot read: /health, /api/metrics/host, the memory tripwire. On 2026-09-15
-- free disk had fallen 151 GB overnight and nothing could say when, because no
-- reading was ever kept. One row per sample of the SAME analysis
-- /api/metrics/host serves makes the over-time question answerable without a
-- second source that can disagree with the first.
--
-- `sample` holds the whole payload (~1.8 KB) rather than only the extracted
-- columns, so a field added to host-analysis.sh later is still recorded for
-- rows written before anyone thought to extract it. The extracted columns
-- exist so a series is queryable without parsing JSON per row.
--
-- Every extracted column is nullable on purpose: a probe that could not read
-- memory must store NULL, never 0. "the machine used no memory" and "nobody
-- measured it" have to stay distinguishable (ethos rule 4), which is also why
-- a failed tick writes a row with measured = 0 instead of writing nothing.
CREATE TABLE IF NOT EXISTS host_metrics (
    ts             INTEGER NOT NULL,
    measured       INTEGER NOT NULL,
    why_unmeasured TEXT,
    cpu_count      INTEGER,
    load1          REAL,
    load_per_core  REAL,
    mem_total_mb   REAL,
    mem_used_mb    REAL,
    mem_percent    REAL,
    mem_pressure   TEXT,
    swap_used_mb   REAL,
    swap_total_mb  REAL,
    disk_free_gb   REAL,
    disk_total_gb  REAL,
    proc_total     INTEGER,
    sample         TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_host_metrics_ts ON host_metrics(ts);
