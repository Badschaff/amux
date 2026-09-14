-- AMUX-4590: /api/history joins each message's card to its epic lineage with
-- `linked.id = root OR linked.epic = root`. issues had no index on epic, so
-- SQLite scanned every issue once per card on the page. Measured on the live
-- DB 2026-09-14: a limit=500 page (264 distinct cards, 20,903 issues) spent
-- 9,753 ms in that one query, and the phone saw 30 to 99 s under load. With
-- this index the same join returned the same 519 rows in 1.7 ms.
CREATE INDEX IF NOT EXISTS idx_issues_epic ON issues(epic);
