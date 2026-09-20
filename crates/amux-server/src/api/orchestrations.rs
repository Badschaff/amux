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

/// Orchestration roles are ordinary workers plus their existing board graph.
/// The deterministic name makes a retried launch reuse its coordinator, while
/// the stored key prevents borrowing a manually created worker on collision.
pub(crate) async fn prepare_coordinator(
    source: &str, name: &str, key: &str, profile: &(String, String, String),
) -> Result<(), String> {
    use super::session_verbs::{self, EnvFile};
    static PREPARE: std::sync::OnceLock<tokio::sync::Mutex<()>> = std::sync::OnceLock::new();
    let _guard = PREPARE.get_or_init(|| tokio::sync::Mutex::new(())).lock().await;
    let path = session_verbs::env_path(name);
    let mut env = EnvFile::load(&path);
    if path.exists() {
        if env.get("CC_ORCHESTRATOR") != Some("1") || env.get("CC_ORCHESTRATION_KEY") != Some(key) {
            return Err(format!("worker {name} is already in use; no settings changed"));
        }
        if ["CC_PAUSED", "CC_ARCHIVED", "CC_ISOLATED"].iter().any(|k| env.get(k) == Some("1")) {
            return Err(format!("orchestrator {name} is paused, archived or isolated; preserving its state"));
        }
        return Ok(());
    }
    let parent = session_verbs::parse_env(source);
    if ["CC_PAUSED", "CC_ARCHIVED", "CC_ISOLATED"].iter().any(|k| parent.get(k) == Some("1")) {
        return Err("workspace worker is paused, archived or isolated".into());
    }
    for k in ["CC_DIR", "CC_WORKTREE_VERIFY", "CC_WORKTREE_BASE"] {
        if let Some(v) = parent.get(k) { env.set(k,v); }
    }
    env.set("CC_ORCHESTRATOR", "1");
    env.set("CC_ORCHESTRATION_KEY", key);
    env.set("CC_ORCHESTRATION_SOURCE", source);
    let cohort = format!("orchestration-{}", &key[..16]);
    let tags = parent.get_or("CC_TAGS", "");
    env.set("CC_TAGS", &if tags.is_empty() { cohort } else { format!("{tags},{cohort}") });
    env.set("CC_PROVIDER", &profile.0);
    let flags = session_verbs::route_model_to_env(&mut env, &profile.0, &profile.1, &profile.2);
    env.set("CC_FLAGS", &flags);
    env.set("CC_DESC", "Orchestrator: coordinate child outcomes, resolve questions, and verify the complete epic");
    env.set("AMUX_DISPATCH_BACKLOG_WHEN_IDLE", "1");
    env.set("CC_CREATOR", &format!("orchestration:{source}"));
    env.write(&path).map_err(|e|e.to_string())?;
    tracing::info!(session=name, source, provider=%profile.0, model=%profile.1,
        verdict="orchestrator_provisioned", measured=true, n_considered=1,
        "created the coordinating worker separately from its fan-out profiles");
    Ok(())
}

pub(crate) fn child_instructions(parent: &str) -> String {
    format!("[no-board] Your role is a fan-out worker. Your orchestrator is {parent}. Own and drain your entire board in your dedicated worktree, with actual tests and integration evidence. Resolve ordinary prerequisites locally. When requirements conflict or you need direction, send one concise question with your card ID, evidence, attempted remedies and recommendation using `amux send {parent} --no-board --stdin`; continue independent work while the orchestrator responds. Do not create a task on the orchestrator's board or make a cross-worker dependency. Completion callbacks already report outcomes to {parent}; do not poll or send repetitive progress messages. Preserve actual spending/customer-outbound approvals and access restrictions.")
}

pub(crate) fn worker_profile(name: &str) -> Value {
    let path=super::session_verbs::env_path(name);
    let retired=path.with_extension("env.reaped");
    let env=if path.exists() { super::session_verbs::parse_env(name) }
        else if retired.exists() { super::session_verbs::EnvFile::load(&retired) }
        else { return json!({"measured":false,"provider":null,"model":null}); };
    let provider=env.get_or("CC_PROVIDER", "claude");
    json!({"measured":true,"provider":provider,"model":super::session_verbs::configured_model_for(provider,env.get_or("CC_MODEL",""),env.get_or("CC_FLAGS",""))})
}

pub(crate) async fn start_coordinator(state: &AppState, name: &str, epic: &str, dedicated: bool) -> Value {
    use super::session_verbs as sv;
    let instructions=format!("[no-board] You are the orchestrator for epic {epic}. Read its current children and evidence. Fan-out workers own their boards and implementation worktrees; you own decomposition, priorities, clarifications, resolving conflicting direction and checking the combined outcome. Answer their requests using `amux send <worker> --no-board --stdin`. Keep implementation and missing prerequisites on the child's board; do not create cross-worker dependency gates or become mandatory peer approval. The harness routes completion callbacks, checks integration and closes the epic when required outcomes satisfy their actual terminal gates. Keep working on actionable coordination and verification until those outcomes hold, then stay quiet. Use events and existing evidence rather than polling workers or repeating status requests. Preserve genuine spending/customer-outbound approvals and access restrictions.");
    if dedicated {
        sv::set_initial_instructions(name, &instructions);
    } else if let Err(error) = sv::steer_enqueue_idempotent(state,name,&instructions,"","amux",&format!("orchestration-start:{epic}")).await {
        return json!({"name":name,"role":"orchestrator","profile":worker_profile(name),"started":false,"error":error});
    }
    let (started, detail)=sv::start_session(state,name,"",false).await;
    tracing::info!(session=name,epic,started,detail,verdict="orchestrator_start_result",measured=true,n_considered=1,
        "coordinator launch outcome recorded independently of child starts");
    json!({"name":name,"role":"orchestrator","profile":worker_profile(name),"started":started,
        "error":if started {Value::Null} else {json!(detail)}})
}

fn project(
    conn: &Connection,
    tracked_workers: &HashSet<String>,
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
                || r["session"].as_str().is_some_and(|s| tracked_workers.contains(s))
        })
        .cloned()
        .collect();
    let mut workers: Vec<_> = tracked_workers
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
            if !(env.get("CC_EPHEMERAL").is_some_and(|v| v == "1") || env.get("CC_ORCHESTRATOR").is_some_and(|v| v == "1"))
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
            Some(json!({"name":name,"ephemeral":env.get("CC_EPHEMERAL").is_some_and(|v|v=="1"),"lifecycle":lifecycle,
                "role":if env.get("CC_ORCHESTRATOR").is_some_and(|v|v=="1") {"orchestrator"} else {"fan-out"},
                "ephemeral_parent":env.get("CC_PARENT"),"profile":worker_profile(&name),
                "running":if retired {json!(false)} else {Value::Null},
                "worktree_active":home.join("worktrees").join(&name).join(".git").exists(),
                "branch":workspace.map(|w|w.branch),
                "worktree_integration":crate::fanout_workspace::integration_status(&home,&name)}))
        })
        .collect();
    let tracked_workers: HashSet<_> = workers
        .iter()
        .filter_map(|w| w["name"].as_str().map(str::to_string))
        .collect();
    let result = state
        .store
        .read()
        .and_then(|conn| Ok(project(&conn, &tracked_workers, allowed.as_ref())?));
    match result {
        Ok(mut v) => {
            v["ephemeral_workers"] = json!(workers.iter().filter(|w|w["ephemeral"]==true).filter_map(|w|w["name"].as_str()).collect::<Vec<_>>());
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
