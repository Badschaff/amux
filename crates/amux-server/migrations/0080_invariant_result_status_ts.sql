-- AMUX-4750. The retention trim in invariants::store::record ran a 261,860-row
-- index scan on EVERY monitor cycle to delete 0 rows, holding the single writer
-- while it did — and every non-GET request in the fleet waits behind that
-- writer via record_receipt in policy::enforce.
--
-- The shipped predicate is `ts < pass_cut AND (status='pass' OR ts < fail_cut)`,
-- which idx_inv_result_ts can only serve by walking the whole tail older than
-- the pass cut and testing status per row. Measured on a 311k-row table with
-- the live distribution: 377ms per cycle, 0 rows deleted.
--
-- With this index the pass arm becomes a covering seek straight to
-- (status='pass', ts < cut): 0.1ms, same 0 rows. The store splits the predicate
-- into its two arms so each can use the index that suits it.
CREATE INDEX IF NOT EXISTS idx_inv_result_status_ts
    ON _amux_invariant_result(status, ts);
