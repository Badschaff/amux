//! Self-contained board policy runs in its own process (environment is global).
use amux_server::api::{router, AppState};
use amux_server::db::Store;
use axum::{body::Body, http::{Request, StatusCode}};
use serde_json::{json, Value};
use tower::ServiceExt;

async fn call(app: &axum::Router, method: &str, path: &str, worker: &str, body: Value) -> (StatusCode, Value) {
    let req = Request::builder().method(method).uri(path).header("Content-Type","application/json")
        .header("X-Amux-Worker",worker).body(Body::from(body.to_string())).unwrap();
    let r=app.clone().oneshot(req).await.unwrap();
    let status=r.status();
    let bytes=axum::body::to_bytes(r.into_body(),usize::MAX).await.unwrap();
    (status,serde_json::from_slice(&bytes).unwrap())
}

#[tokio::test]
async fn workers_keep_assignments_and_dependencies_on_their_own_board() {
    let home=tempfile::tempdir().unwrap();
    std::fs::create_dir(home.path().join("sessions")).unwrap();
    for lane in ["owner","peer"] {
        std::fs::write(home.path().join(format!("sessions/{lane}.env")),"CC_DIR=/tmp\n").unwrap();
    }
    std::env::set_var("AMUX_HOME",home.path());
    std::env::set_var("AMUX_BOARD_DELEGATION","0");
    let store=std::sync::Arc::new(Store::open(&home.path().join("test.db")).unwrap());
    let app=router(AppState{store:store.clone(),started:std::time::Instant::now(),build_hash:"test".into(),auth_token:None,
        reconciled:std::sync::Arc::new(std::sync::atomic::AtomicBool::new(true))});
    let create_body=|title:&str|json!({"title":title,"status":"backlog","type":"chore","next_action":"Implement the local outcome","acceptance_criteria":["Recorded artifact passes its check"]});
    let (s,dep)=call(&app,"POST","/api/board","peer",create_body("Peer component")).await;
    assert_eq!(s,StatusCode::CREATED,"{dep}");
    let peer_id=dep["id"].as_str().unwrap();
    let (s,own)=call(&app,"POST","/api/board","owner",create_body("Own outcome")).await;
    assert_eq!(s,StatusCode::CREATED,"{own}");
    let id=own["id"].as_str().unwrap();
    let count=||store.read().unwrap().query_row("SELECT count(*) FROM issues",[],|r|r.get::<_,i64>(0)).unwrap();
    let before=count();
    for route in [json!({"request_to":"peer"}),json!({"session":"peer"})] {
        let mut b=create_body("Not another worker assignment");
        b.as_object_mut().unwrap().extend(route.as_object().unwrap().clone());
        let (s,v)=call(&app,"POST","/api/board","owner",b).await;
        assert!(matches!(s,StatusCode::CONFLICT|StatusCode::FORBIDDEN),"{v}");
    }
    let mut b=create_body("Not a cross-board wait"); b["depends_on"]=json!([peer_id]);
    let (s,v)=call(&app,"POST","/api/board","owner",b).await;
    assert_eq!(s,StatusCode::CONFLICT,"{v}");
    assert_eq!(v["code"],"cross_board_dependency_forbidden");
    assert_eq!(count(),before,"no refused path may mint a card");
    let (s,v)=call(&app,"PATCH",&format!("/api/board/{id}"),"owner",json!({"depends_on":[peer_id],"desc_append":"must not persist"})).await;
    assert_eq!(s,StatusCode::CONFLICT,"{v}");
    assert_eq!(v["code"],"cross_board_dependency_forbidden");
    let (_,unchanged)=call(&app,"GET",&format!("/api/board/{id}"),"owner",Value::Null).await;
    assert_eq!(unchanged["rev"],own["rev"]);
    assert_eq!(unchanged["desc"],own["desc"]);
    // Same-board real dependencies still work; historical foreign edges can
    // be removed in the same edit that records the owner's next action.
    let (_,local)=call(&app,"POST","/api/board","owner",create_body("Local input")).await;
    let (s,v)=call(&app,"PATCH",&format!("/api/board/{id}"),"owner",json!({"depends_on":[local["id"]]})).await;
    assert_eq!(s,StatusCode::OK,"{v}");
    let (s,v)=call(&app,"PATCH",&format!("/api/board/{id}"),"owner",json!({"depends_on":[],"desc_append":format!("Reuse evidence from {peer_id}; own any missing implementation here")})).await;
    assert_eq!(s,StatusCode::OK,"{v}");
}
