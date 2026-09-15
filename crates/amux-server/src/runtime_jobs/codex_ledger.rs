//! Codex turns in the token ledger (AMUX-4583).
//!
//! Nine lanes on this fleet run codex, and every token they spent was invisible
//! to `/api/usage`, `/api/observability` and the Cost tab: `translate_codex`
//! discards the usage on `turn.completed`, and `~/.codex/sessions` was read only
//! to decide whether a lane looked busy. A dashboard that shows the fleet's
//! spend while silently omitting a provider is the confident-zero shape the
//! token ledger itself was built to end.
//!
//! Codex writes the same thing Claude does, in a different place and shape:
//! `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`, one `event_msg` per
//! `token_count` carrying `info.last_token_usage` (the delta for that turn) and
//! `info.total_token_usage` (cumulative). This reads the DELTA, keyed by the
//! event's own `ordinal`, so a re-read cannot double-bill.
//!
//! Attribution is by working directory and only when it is unambiguous. Codex
//! records `cwd` in its `session_meta`; a lane records the same path. When two
//! lanes share one directory the row is left unattributed (`session = ''`),
//! which the ledger already means as "counts toward fleet totals, owned by
//! nobody". Charging a guess to a named lane is worse than charging nobody:
//! the ledger is what the cost view bills, and AMUX-2612 already records what
//! a wrong owner costs to unpick.
use crate::db::{SharedStore, WriteOutcome};
use std::collections::{BTreeMap, HashMap};
use std::io::{BufRead, BufReader, Seek, SeekFrom};
use std::path::{Path, PathBuf};

/// One codex turn's usage, as the ledger stores it.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct CodexTurn {
    pub ts: i64,
    /// The event's position in its own file: stable, so re-reading a file
    /// cannot bill the same turn twice.
    pub ordinal: i64,
    pub model: String,
    /// `[input, cache_read, cache_write, output]`, matching `token_ledger`.
    pub tokens: [i64; 4],
}

/// `~/.codex/sessions`, from the OS home. Codex writes here, NOT into amux's
/// own home; `codex_rollout_files` records what pointing at the wrong one cost.
fn codex_sessions_dir() -> PathBuf {
    PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(".codex/sessions")
}

/// Every `rollout-*.jsonl` under `root`, depth-bounded like the transcript walk.
fn rollout_files(root: &Path) -> Vec<PathBuf> {
    fn walk(dir: &Path, depth: usize, out: &mut Vec<PathBuf>) {
        if depth > 3 {
            return;
        }
        let Ok(rd) = std::fs::read_dir(dir) else { return };
        for e in rd.flatten() {
            let p = e.path();
            if p.is_dir() {
                walk(&p, depth + 1, out);
            } else if p
                .file_name()
                .and_then(|s| s.to_str())
                .is_some_and(|s| s.starts_with("rollout-") && s.ends_with(".jsonl"))
            {
                out.push(p);
            }
        }
    }
    let mut out = Vec::new();
    walk(root, 0, &mut out);
    out
}

/// The conversation key for a rollout file.
///
/// Prefixed `codex:` on purpose. Both providers name conversations with a
/// UUID, and the ledger's cursor table is keyed by that string alone, so an
/// unprefixed collision would let one provider's cursor skip the other's file.
/// It also makes a codex row identifiable in the ledger without a join.
pub(crate) fn conversation_key(path: &Path) -> String {
    let stem = path.file_stem().map(|s| s.to_string_lossy().to_string()).unwrap_or_default();
    // rollout-2026-09-09T14-12-21-<uuid>
    let id = stem.rsplit_once("-").map(|(_, tail)| tail.to_string()).unwrap_or_default();
    let id = if id.len() >= 12 { id } else { stem.clone() };
    format!("codex:{id}")
}

/// The `cwd` a rollout file was opened in, from its `session_meta` first line.
pub(crate) fn rollout_cwd(path: &Path) -> Option<String> {
    let f = std::fs::File::open(path).ok()?;
    let mut first = String::new();
    BufReader::new(f).read_line(&mut first).ok()?;
    let v: serde_json::Value = serde_json::from_str(&first).ok()?;
    v.pointer("/payload/cwd")
        .and_then(serde_json::Value::as_str)
        .map(|s| s.trim_end_matches('/').to_string())
        .filter(|s| !s.is_empty())
}

/// Parse `token_count` deltas after `offset`.
///
/// Returns the new byte offset and one turn per event that reported any tokens.
/// A zero-token event is skipped rather than stored: codex emits one on turns
/// that spent nothing, and a ledger row of four zeros is noise a reader has to
/// explain.
pub(crate) fn parse_codex_from(path: &Path, offset: u64) -> (u64, Vec<CodexTurn>) {
    let Ok(mut f) = std::fs::File::open(path) else {
        return (offset, vec![]);
    };
    if offset > 0 && f.seek(SeekFrom::Start(offset)).is_err() {
        return (offset, vec![]);
    }
    let mut new_off = offset;
    let mut out = Vec::new();
    let mut model = String::new();
    for raw in BufReader::new(f).split(b'\n') {
        let Ok(mut bytes) = raw else { break };
        // `split` drops the delimiter; the cursor must still count it, or every
        // line shifts the offset back by one byte and the next pass re-reads a
        // partial line as garbage (the same trap the Claude parser records).
        new_off += bytes.len() as u64 + 1;
        if bytes.last() == Some(&b'\r') {
            bytes.pop();
        }
        let Ok(e) = serde_json::from_slice::<serde_json::Value>(&bytes) else { continue };
        // The model is named by turn context events, not by `session_meta`.
        // Remember the most recent one: it is what the turns below were spent on.
        for key in ["/payload/model", "/model", "/payload/turn_context/model"] {
            if let Some(m) = e.pointer(key).and_then(serde_json::Value::as_str) {
                if !m.trim().is_empty() {
                    model = m.trim().to_string();
                }
            }
        }
        if e.pointer("/payload/type").and_then(serde_json::Value::as_str) != Some("token_count") {
            continue;
        }
        let Some(last) = e.pointer("/payload/info/last_token_usage") else { continue };
        let n = |k: &str| last.get(k).and_then(serde_json::Value::as_i64).unwrap_or(0);
        // `input_tokens` INCLUDES the cached part (measured on a live rollout:
        // 58880 input of which 57344 cached), and `total_tokens` is input +
        // output, so `reasoning_output_tokens` is already inside output_tokens
        // and must not be added again.
        let cache_read = n("cached_input_tokens");
        let fresh_input = (n("input_tokens") - cache_read).max(0);
        let tokens = [fresh_input, cache_read, n("cache_write_input_tokens"), n("output_tokens")];
        if tokens.iter().all(|t| *t == 0) {
            continue;
        }
        let Some(ts) = e
            .get("timestamp")
            .and_then(serde_json::Value::as_str)
            .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
            .map(|t| t.timestamp())
        else {
            continue;
        };
        let ordinal = e.get("ordinal").and_then(serde_json::Value::as_i64).unwrap_or(-1);
        out.push(CodexTurn { ts, ordinal, model: model.clone(), tokens });
    }
    (new_off, out)
}

/// cwd -> the single lane that works there. A directory two lanes share is
/// dropped rather than guessed at.
pub(crate) fn unambiguous_owners(workdirs: &BTreeMap<String, String>) -> HashMap<String, String> {
    let mut by_dir: HashMap<String, Vec<String>> = HashMap::new();
    for (lane, dir) in workdirs {
        let dir = dir.trim().trim_end_matches('/').to_string();
        if dir.is_empty() {
            continue;
        }
        by_dir.entry(dir).or_default().push(lane.clone());
    }
    by_dir
        .into_iter()
        .filter(|(_, lanes)| lanes.len() == 1)
        .map(|(dir, lanes)| (dir, lanes[0].clone()))
        .collect()
}

/// One pass over the codex rollouts. Returns how many ledger rows were written.
pub async fn index_once(store: &SharedStore, home: &Path) -> anyhow::Result<usize> {
    index_once_at(store, home, &codex_sessions_dir(), &crate::api::session_verbs::all_session_workdirs()).await
}

/// The pass with its roots injected, so a test drives a temp tree and a fixed
/// lane map instead of this machine's real ones.
pub async fn index_once_at(
    store: &SharedStore,
    home: &Path,
    sessions: &Path,
    workdirs: &BTreeMap<String, String>,
) -> anyhow::Result<usize> {
    if !sessions.is_dir() {
        return Ok(0);
    }
    let table = super::token_ledger::prices(home);
    let owners = unambiguous_owners(workdirs);
    let cursors: HashMap<String, u64> = {
        let conn = store.read()?;
        let mut stmt = conn.prepare("SELECT conversation, offset FROM ledger_cursor")?;
        let rows = stmt
            .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)? as u64)))?;
        rows.flatten().collect()
    };

    let mut pending: Vec<(String, String, u64, i64, Vec<CodexTurn>)> = Vec::new();
    for path in rollout_files(sessions) {
        let conversation = conversation_key(&path);
        let Ok(meta) = path.metadata() else { continue };
        let size = meta.len();
        let offset = cursors.get(&conversation).copied().unwrap_or(0);
        if offset >= size {
            continue; // nothing new; a truncated file re-reads from its start
        }
        let offset = if offset > size { 0 } else { offset };
        let lane = rollout_cwd(&path)
            .and_then(|cwd| owners.get(&cwd).cloned())
            .unwrap_or_default();
        let mtime = meta
            .modified()
            .ok()
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);
        let (new_off, turns) = parse_codex_from(&path, offset);
        if turns.is_empty() && new_off == offset {
            continue;
        }
        pending.push((conversation, lane, new_off, mtime, turns));
    }
    if pending.is_empty() {
        return Ok(0);
    }
    let expected: usize = pending.iter().map(|(_, _, _, _, turns)| turns.len()).sum();

    // How many of these rows take the default price because no table entry
    // names their model. Reported beside the row count: a defaulted dollar
    // figure that looks measured is worse than no figure at all.
    let guessed: usize = pending
        .iter()
        .flat_map(|(_, _, _, _, turns)| turns.iter())
        .filter(|t| !super::token_ledger::model_is_priced(&table, &t.model))
        .count();
    let models: std::collections::BTreeSet<String> = pending
        .iter()
        .flat_map(|(_, _, _, _, turns)| turns.iter())
        .filter(|t| !super::token_ledger::model_is_priced(&table, &t.model))
        .map(|t| t.model.clone())
        .collect();
    if guessed > 0 {
        tracing::warn!(
            verdict = "codex_rows_priced_by_default",
            rows = guessed,
            models = %models.into_iter().collect::<Vec<_>>().join(","),
            measured = true,
            n_considered = expected,
            "codex turns carry the DEFAULT price: their token counts are measured, their cost is not. \
             Set real rates for these models in ~/.amux/prices.json (config, no redeploy)."
        );
    }
    let inserted = store
        .write_async(move |conn| {
            let mut n = 0usize;
            {
                let mut ins = conn.prepare(
                    "INSERT INTO token_ledger
                       (ts, session, conversation, model, input, cache_read, cache_write, output, cost_usd, message_id)
                     VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10)
                     ON CONFLICT(conversation, message_id) WHERE message_id IS NOT NULL
                     DO UPDATE SET output = MAX(output, excluded.output),
                                   cost_usd = MAX(cost_usd, excluded.cost_usd)",
                )?;
                let mut cur = conn.prepare(
                    "INSERT INTO ledger_cursor (conversation, offset, mtime) VALUES (?1,?2,?3)
                     ON CONFLICT(conversation) DO UPDATE SET offset=?2, mtime=?3",
                )?;
                for (conversation, lane, off, mtime, turns) in &pending {
                    for t in turns {
                        let cost = super::token_ledger::turn_cost_usd(&table, &t.model, t.tokens);
                        ins.execute(rusqlite::params![
                            t.ts,
                            lane,
                            conversation,
                            t.model,
                            t.tokens[0],
                            t.tokens[1],
                            t.tokens[2],
                            t.tokens[3],
                            cost,
                            format!("ord:{}", t.ordinal),
                        ])?;
                        n += 1;
                    }
                    cur.execute(rusqlite::params![conversation, *off as i64, mtime])?;
                }
            }
            Ok(WriteOutcome { applied: n > 0, events: vec![] })
        })
        .await
        .map(|_| expected)?;
    // Codex rows join the same task attribution pass Claude rows get, so a
    // card's cost view does not silently mean "Claude only".
    if inserted > 0 {
        super::token_ledger::attribute_tasks(store).await?;
    }
    Ok(inserted)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn store() -> SharedStore {
        let dir = tempfile::tempdir().unwrap();
        let st = crate::db::Store::open(&dir.path().join("codex-ledger-test.db")).unwrap();
        std::mem::forget(dir);
        std::sync::Arc::new(st)
    }

    /// One `token_count` event in the shape codex actually writes (copied from a
    /// live rollout on this box, trimmed).
    fn token_count(ordinal: i64, ts: &str, input: i64, cached: i64, cache_write: i64, output: i64) -> String {
        format!(
            r#"{{"timestamp":"{ts}","ordinal":{ordinal},"type":"event_msg","payload":{{"type":"token_count","info":{{"total_token_usage":{{"input_tokens":999999,"cached_input_tokens":0,"output_tokens":999}},"last_token_usage":{{"input_tokens":{input},"cached_input_tokens":{cached},"cache_write_input_tokens":{cache_write},"output_tokens":{output},"reasoning_output_tokens":{reasoning},"total_tokens":{total}}},"model_context_window":258400}}}}}}"#,
            reasoning = output / 3,
            total = input + output,
        )
    }

    fn session_meta(cwd: &str) -> String {
        format!(
            r#"{{"timestamp":"2026-09-15T10:00:00.000Z","ordinal":0,"type":"session_meta","payload":{{"session_id":"019a4580-abd6-7153-993c-217e6941ea1d","cwd":"{cwd}","model_provider":"openai"}}}}"#
        )
    }

    fn rollout(dir: &Path, cwd: &str, body: &str) -> PathBuf {
        let day = dir.join("2026/09/15");
        std::fs::create_dir_all(&day).unwrap();
        let p = day.join("rollout-2026-09-15T10-00-00-019a4580-abd6-7153-993c-217e6941ea1d.jsonl");
        std::fs::write(&p, format!("{}\n{}", session_meta(cwd), body)).unwrap();
        p
    }

    /// The mapping this whole file rests on: codex reports the input total WITH
    /// the cached part inside it, and the reasoning tokens inside the output.
    /// Getting either wrong inflates a lane's bill with tokens nobody spent.
    #[test]
    fn a_turn_splits_cached_input_out_and_never_counts_reasoning_twice() {
        let dir = tempfile::tempdir().unwrap();
        let body = format!(
            "{}\n{}\n{}\n",
            r#"{"timestamp":"2026-09-15T10:00:01.000Z","ordinal":1,"type":"turn_context","payload":{"model":"gpt-5-codex"}}"#,
            token_count(2, "2026-09-15T10:00:02.000Z", 58880, 57344, 0, 390),
            token_count(3, "2026-09-15T10:00:03.000Z", 0, 0, 0, 0),
        );
        let p = rollout(dir.path(), "/Users/ethan/Dev/amux", &body);

        let (off, turns) = parse_codex_from(&p, 0);
        assert_eq!(turns.len(), 1, "the zero-token event is not a ledger row: {turns:?}");
        let t = &turns[0];
        assert_eq!(t.tokens, [1536, 57344, 0, 390],
            "fresh input is input_tokens minus the cached part, and output is not summed with reasoning");
        assert_eq!(t.model, "gpt-5-codex", "the model comes from the turn context, not session_meta");
        assert_eq!(t.ordinal, 2);
        assert_eq!(t.ts, 1789466402);
        assert_eq!(off, std::fs::metadata(&p).unwrap().len(), "the cursor lands on the end of the file");

        // Resuming from that cursor finds nothing: the same turn cannot be
        // billed twice by a second pass.
        let (off2, again) = parse_codex_from(&p, off);
        assert!(again.is_empty(), "{again:?}");
        assert_eq!(off2, off);
    }

    /// A directory two lanes share attributes to NEITHER: the ledger is what
    /// the cost view bills, and a wrong owner is worse than an unowned row.
    #[test]
    fn a_shared_working_directory_is_left_unattributed() {
        let mut dirs = BTreeMap::new();
        dirs.insert("alpha".to_string(), "/Users/ethan/Dev/amux".to_string());
        dirs.insert("beta".to_string(), "/Users/ethan/Dev/amux/".to_string()); // same dir, trailing slash
        dirs.insert("solo".to_string(), "/Users/ethan/Dev/solo".to_string());
        dirs.insert("nowhere".to_string(), String::new());
        let owners = unambiguous_owners(&dirs);
        assert_eq!(owners.get("/Users/ethan/Dev/solo"), Some(&"solo".to_string()));
        assert!(!owners.contains_key("/Users/ethan/Dev/amux"), "two lanes, no owner: {owners:?}");
        assert!(!owners.contains_key(""), "an empty workdir owns nothing");
    }

    /// End to end: a rollout becomes ledger rows charged to the lane that works
    /// in that directory, and a second pass adds nothing.
    #[tokio::test]
    async fn a_rollout_becomes_ledger_rows_for_the_lane_that_works_there() {
        let home = tempfile::tempdir().unwrap();
        let sessions = tempfile::tempdir().unwrap();
        let body = format!(
            "{}\n{}\n{}\n",
            r#"{"timestamp":"2026-09-15T10:00:01.000Z","ordinal":1,"type":"turn_context","payload":{"model":"gpt-5-codex"}}"#,
            token_count(2, "2026-09-15T10:00:02.000Z", 1000, 400, 0, 50),
            token_count(4, "2026-09-15T10:00:04.000Z", 2000, 0, 0, 70),
        );
        rollout(sessions.path(), "/Users/ethan/Dev/amux", &body);
        let mut workdirs = BTreeMap::new();
        workdirs.insert("amux-research".to_string(), "/Users/ethan/Dev/amux".to_string());

        let st = store();
        let n = index_once_at(&st, home.path(), sessions.path(), &workdirs).await.unwrap();
        assert_eq!(n, 2);
        {
            let conn = st.read().unwrap();
            let rows: Vec<(String, String, String, i64, i64, i64, String)> = conn
                .prepare("SELECT session, conversation, model, input, cache_read, output, message_id \
                          FROM token_ledger ORDER BY ts")
                .unwrap()
                .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?, r.get(6)?)))
                .unwrap()
                .flatten()
                .collect();
            assert_eq!(rows.len(), 2, "{rows:?}");
            assert_eq!(rows[0].0, "amux-research", "charged to the lane working in that cwd");
            assert!(rows[0].1.starts_with("codex:"), "the conversation says which provider it came from: {}", rows[0].1);
            assert_eq!(rows[0].2, "gpt-5-codex");
            assert_eq!((rows[0].3, rows[0].4, rows[0].5), (600, 400, 50));
            assert_eq!(rows[0].6, "ord:2");
            assert_eq!(rows[1].6, "ord:4");
        }

        // Idempotent: the cursor holds, and re-running bills nothing again.
        let again = index_once_at(&st, home.path(), sessions.path(), &workdirs).await.unwrap();
        assert_eq!(again, 0, "a second pass must not re-bill the same turns");
        let conn = st.read().unwrap();
        assert_eq!(
            conn.query_row("SELECT COUNT(*) FROM token_ledger", [], |r| r.get::<_, i64>(0)).unwrap(),
            2
        );
    }

    /// A rollout in a directory no lane owns still counts toward fleet totals,
    /// unowned. Dropping it would recreate the invisible-spend hole this closes.
    #[tokio::test]
    async fn an_unknown_working_directory_still_reaches_the_ledger_unowned() {
        let home = tempfile::tempdir().unwrap();
        let sessions = tempfile::tempdir().unwrap();
        rollout(sessions.path(), "/somewhere/nobody/owns",
            &format!("{}\n", token_count(2, "2026-09-15T10:00:02.000Z", 500, 0, 0, 10)));
        let st = store();
        let n = index_once_at(&st, home.path(), sessions.path(), &BTreeMap::new()).await.unwrap();
        assert_eq!(n, 1);
        let conn = st.read().unwrap();
        let (session, input): (String, i64) = conn
            .query_row("SELECT session, input FROM token_ledger", [], |r| Ok((r.get(0)?, r.get(1)?)))
            .unwrap();
        assert_eq!(session, "", "unowned, not dropped and not guessed");
        assert_eq!(input, 500);
    }
}
