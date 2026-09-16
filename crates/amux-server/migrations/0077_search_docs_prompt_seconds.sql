-- AMUX-4548: search_docs.updated_at is a MIXED-UNIT column. Six of its seven
-- families write seconds; the seventh writes milliseconds.
--
-- Measured on the live DB 2026-09-16, 21,465 rows:
--
--   task       19186   max 1789561042      seconds
--   prompt      1910   max 1789559556000   MILLISECONDS
--   schedule     205   max 1789561034      seconds
--   journal      136   max 1786329505      seconds
--   message       25   max 1786800464      seconds
--   worker         3   max 1788135969      seconds
--
-- `schema.timestamp_units_declared` reported it as "MAX = 1789559556000, which
-- under the declared unit is -496602776 hours from now". The card framed the
-- remedy as a choice between the writer and the declaration. It is neither: the
-- declaration matches 19,555 of 21,465 rows and all six other writers, and one
-- writer disagrees with the other six.
--
-- 0056 introduced it in three places at once, all reading `cmd_history.ts`,
-- which is MILLISECONDS while every other source column here is seconds: the
-- `search_prompt_ai` trigger, that migration's own backfill, and `BACKFILL_SQL`
-- in api/search.rs (fixed in the same commit as this migration, so a reindex
-- and a live insert cannot disagree).
--
-- The trigger is REPLACED rather than patched: 0056 created it with
-- `CREATE TRIGGER IF NOT EXISTS`, so on a database that already has the old one
-- a second IF NOT EXISTS is a silent no-op and the bug survives the migration.
DROP TRIGGER IF EXISTS search_prompt_ai;
CREATE TRIGGER search_prompt_ai AFTER INSERT ON cmd_history
WHEN new.type = 'user' BEGIN
    INSERT INTO search_docs (doc_id, entity_type, entity_id, title, body, scope, task_id, worker_id, link, meta, updated_at)
    VALUES ('prompt:'||new.id, 'prompt', new.id,
            substr(replace(new.text, char(10), ' '), 1, 80), new.text,
            new.session, new.card_id, new.session, '#history/'||new.id,
            json_object('session', new.session, 'origin', new.origin, 'card_id', new.card_id),
            new.ts/1000)
    ON CONFLICT(doc_id) DO UPDATE SET
        title=excluded.title, body=excluded.body, scope=excluded.scope,
        task_id=excluded.task_id, worker_id=excluded.worker_id,
        link=excluded.link, meta=excluded.meta, updated_at=excluded.updated_at;
END;

-- Repair the rows 0056 already wrote. Guarded on MAGNITUDE rather than on
-- entity_type alone so it cannot divide twice: after this runs the values are
-- ~1.79e9 and the predicate no longer matches, which makes a re-run a no-op on
-- a database that has already been fixed.
--
-- 1e11 is an unambiguous separator here. As seconds it is the year 5138; as
-- milliseconds it is 1973. Live prompt values are 1.78e12 and live second
-- values are 1.79e9, so nothing real sits near the boundary.
--
-- The UPDATE fires search_docs_au, which re-syncs the FTS row. title and body
-- are untouched, so the re-indexed content is identical and only updated_at
-- moves.
UPDATE search_docs SET updated_at = updated_at/1000
 WHERE entity_type = 'prompt' AND updated_at > 100000000000;
