//! A compact projection of existing boards, not a second orchestration store.
use super::{org, AppState};
use crate::db::board_store;
use axum::{
    extract::State,
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use rusqlite::Connection;
use serde_json::{json, Value};
use std::collections::HashSet;

fn project(
    conn: &Connection,
    ephemeral: &HashSet<String>,
    allowed: Option<&HashSet<String>>,
) -> rusqlite::Result<Value> {
    let mut stmt = conn.prepare("SELECT id,title,status,COALESCE(type,'code'),epic,session,COALESCE(archived,0),updated FROM issues WHERE deleted IS NULL")?;
    let rows = stmt.query_map([], |r| {
        let status: String = r.get(2)?;
        let kind: String = r.get(3)?;
        Ok(json!({"id":r.get::<_,String>(0)?,"title":r.get::<_,String>(1)?,
            "execution_terminal":board_store::execution_is_terminal(&status,&kind),
            "status":status,"type":kind,"epic":r.get::<_,Option<String>>(4)?,
            "session":r.get::<_,Option<String>>(5)?,"archived":r.get::<_,i64>(6)?,"updated":r.get::<_,f64>(7)?}))
    })?.collect::<rusqlite::Result<Vec<_>>>()?;
    // Scope before following graph edges: an allowed child must not disclose a
    // foreign parent's title. Missing parents remain explicit to the renderer.
    let rows: Vec<_> = rows
        .into_iter()
        .filter(|r| allowed.is_none_or(|a| r["session"].as_str().is_some_and(|s| a.contains(s))))
        .collect();
    let n = rows.len();
    let parents: HashSet<_> = rows.iter().filter_map(|r| r["epic"].as_str()).collect();
    let cards: Vec<_> = rows
        .iter()
        .filter(|r| {
            r["type"] == "epic"
                || r["epic"].as_str().is_some()
                || r["id"].as_str().is_some_and(|id| parents.contains(id))
                || r["session"].as_str().is_some_and(|s| ephemeral.contains(s))
        })
        .cloned()
        .collect();
    let mut workers: Vec<_> = ephemeral
        .iter()
        .filter(|name| allowed.is_none_or(|scope| scope.contains(*name)))
        .cloned()
        .collect();
    workers.sort();
    Ok(json!({"measured":true,"n_considered":n,"cards":cards,"ephemeral_workers":workers}))
}

pub async fn list(State(state): State<AppState>, headers: HeaderMap) -> Response {
    let allowed = org::local_member_scope(&headers)
        .filter(|s| !s.is_global())
        .map(|s| {
            org::scoped_worker_names(&s)
                .into_iter()
                .collect::<HashSet<_>>()
        });
    let entries = match std::fs::read_dir(crate::config::amux_home().join("sessions")) {
        Ok(entries) => Some(entries),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => None,
        Err(e) => {
            tracing::warn!(verdict="orchestration_inventory_failed",error=%e,"could not measure fan-out inventory");
            return (StatusCode::SERVICE_UNAVAILABLE,Json(json!({"measured":false,"n_considered":0,"error":"Could not read fan-out inventory"}))).into_response();
        }
    };
    let workers: Vec<Value> = entries
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|e| {
            let file = e.file_name();
            let file = file.to_str()?;
            let name = file
                .strip_suffix(".env")
                .or_else(|| file.strip_suffix(".env.reaped"))?
                .to_string();
            let env = crate::config::parse_env_file(&e.path());
            if !env.get("CC_EPHEMERAL").is_some_and(|v| v == "1")
                || allowed.as_ref().is_some_and(|scope| !scope.contains(&name))
            {
                return None;
            }
            let retired = file.ends_with(".env.reaped");
            let lifecycle = if retired {
                "expired"
            } else if env.get("CC_ARCHIVED").is_some_and(|v| v == "1") {
                "archived"
            } else if env.get("CC_PAUSED").is_some_and(|v| v == "1") {
                "paused"
            } else {
                "active"
            };
            let home = crate::config::amux_home();
            let workspace = crate::fanout_workspace::load(&home, &name);
            Some(json!({"name":name,"ephemeral":true,"lifecycle":lifecycle,
                "running":if retired {json!(false)} else {Value::Null},
                "worktree_active":home.join("worktrees").join(&name).join(".git").exists(),
                "branch":workspace.map(|w|w.branch),
                "worktree_integration":crate::fanout_workspace::integration_status(&home,&name)}))
        })
        .collect();
    let ephemeral: HashSet<_> = workers
        .iter()
        .filter_map(|w| w["name"].as_str().map(str::to_string))
        .collect();
    let result = state
        .store
        .read()
        .and_then(|conn| Ok(project(&conn, &ephemeral, allowed.as_ref())?));
    match result {
        Ok(mut v) => {
            v["workers"] = json!(workers);
            Json(v).into_response()
        }
        Err(e) => {
            tracing::warn!(verdict="orchestration_projection_failed",error=%e,"orchestration board projection failed");
            (StatusCode::SERVICE_UNAVAILABLE, Json(json!({"measured":false,"n_considered":0,"error":"Could not read orchestration boards"}))).into_response()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn projection_includes_full_child_board_and_does_not_return_history_prose() {
        let c = crate::db::migrate::test_memdb();
        c.execute_batch(
            "INSERT INTO issues(id,title,status,type,session,epic,created,updated,desc) VALUES
            ('E','Epic','doing','epic','parent',NULL,1,1,'private long prompt'),
            ('A','Assignment','done','code','child','E',1,1,''),
            ('B','Follow-up','backlog','code','child',NULL,1,1,''),
            ('C','Unrelated history','done','code','other',NULL,1,1,'');",
        )
        .unwrap();
        let eph = HashSet::from(["child".into()]);
        let v = project(&c, &eph, None).unwrap();
        assert_eq!(v["cards"].as_array().unwrap().len(), 3);
        assert_eq!(v["n_considered"], 4);
        assert!(!v.to_string().contains("private long prompt"));
        assert!(!v["cards"]
            .as_array()
            .unwrap()
            .iter()
            .find(|r| r["id"] == "A")
            .unwrap()["execution_terminal"]
            .as_bool()
            .unwrap());
        let v = project(&c, &eph, Some(&HashSet::from(["child".into()]))).unwrap();
        assert_eq!(v["cards"].as_array().unwrap().len(), 2);
        assert!(!v.to_string().contains("\"title\":\"Epic\""));
    }
}
