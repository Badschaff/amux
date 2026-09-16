//! `request_to`: a board create routed onto ANOTHER lane's board (AMUX-4653).
//!
//! `amux board request <lane> <title>` used to post
//! `{status: backlog, reviewer: <lane>}` with no session, so the card landed on
//! the SENDER's board. Dispatch selects by session and the reviewer nudge fires
//! only on review/done, so the named lane was never offered it: 88 such cards
//! were sitting in senders' backlogs on 2026-09-15, ten of them
//! mixpeek-finances' (MF-1160..1167, 1169, 1174), draining back into their own
//! pickup as churn.
//!
//! Its own process, so `AMUX_HOME` can point at a fixture fleet. The lanes this
//! suite routes to are FILES under `sessions/`, because that is what the server
//! reads to decide whether a lane exists, is archived, or is isolated.

use amux_server::api::{router, AppState};
use amux_server::db::Store;
use axum::body::Body;
use axum::http::{header, Request, StatusCode};
use serde_json::{json, Value};
use std::sync::OnceLock;
use tower::ServiceExt;

/// A fixture fleet, created once for the whole process.
///
/// One home shared by every test here rather than one per test: `AMUX_HOME` is
/// process-global and these run on parallel threads, so a per-test home is a
/// race in which one test reads another's fleet. The directory is leaked on
/// purpose, because a `TempDir` dropped by the first test to finish would
/// delete the fleet out from under the others.
fn fleet_home() -> &'static std::path::Path {
    static HOME: OnceLock<std::path::PathBuf> = OnceLock::new();
    HOME.get_or_init(|| {
        let dir = Box::leak(Box::new(tempfile::tempdir().expect("tempdir")));
        let sessions = dir.path().join("sessions");
        std::fs::create_dir_all(&sessions).expect("sessions dir");
        std::fs::write(sessions.join("lane-a.env"), "CC_DIR=/tmp\n").expect("lane-a");
        std::fs::write(sessions.join("lane-b.env"), "CC_DIR=/tmp\n").expect("lane-b");
        std::fs::write(sessions.join("lane-paused.env"), "CC_DIR=/tmp\nCC_PAUSED=1\n").expect("paused");
        std::fs::write(sessions.join("lane-archived.env"), "CC_DIR=/tmp\nCC_ARCHIVED=1\n").expect("archived");
        std::fs::write(sessions.join("lane-iso.env"), "CC_DIR=/tmp\nCC_ISOLATED=1\n").expect("isolated");
        std::env::set_var("AMUX_HOME", dir.path());
        std::env::set_var("AMUX_APPROVAL_TYPES", "*");
        dir.path().to_path_buf()
    })
    .as_path()
}

fn app() -> (axum::Router, std::sync::Arc<Store>, tempfile::TempDir) {
    let _ = fleet_home();
    let dir = tempfile::tempdir().unwrap();
    let store = std::sync::Arc::new(Store::open(&dir.path().join("amux-test.db")).unwrap());
    let state = AppState {
        store: store.clone(),
        started: std::time::Instant::now(),
        build_hash: "test".into(),
        auth_token: None,
        reconciled: std::sync::Arc::new(std::sync::atomic::AtomicBool::new(true)),
    };
    (router(state), store, dir)
}

async fn post_as(app: &axum::Router, worker: &str, body: Value) -> (StatusCode, Value) {
    let req = Request::builder()
        .method("POST")
        .uri("/api/board")
        .header("X-Amux-Worker", worker)
        .header(header::CONTENT_TYPE, "application/json")
        .body(Body::from(body.to_string()))
        .unwrap();
    let res = app.clone().oneshot(req).await.unwrap();
    let status = res.status();
    let bytes = axum::body::to_bytes(res.into_body(), usize::MAX).await.unwrap();
    let v: Value = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
    (status, v)
}

/// The whole point: the card lands on the TARGET, attributed to the caller,
/// with a callback armed back to them, and the target's dispatch can see it.
#[tokio::test]
async fn a_request_lands_on_the_target_board_attributed_and_armed() {
    let (app, store, _dir) = app();

    let (st, v) = post_as(
        &app,
        "lane-a",
        json!({
            "title": "pick up the docker bundle",
            "request_to": "lane-b",
            "desc": "WS5 of the standalone epic",
            "type": "investigation",
            "due": "2026-09-30",
        }),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED, "{v}");

    // On THEIR board, not the requester's. This is the cell the 88 stranded
    // cards failed.
    assert_eq!(v["session"], json!("lane-b"), "{v}");
    assert_eq!(v["requested_by"], json!("lane-a"), "{v}");
    assert_eq!(v["callback"]["session"], json!("lane-a"), "{v}");
    assert_eq!(v["callback"]["state"], json!("armed"), "{v}");

    // THE STRUCTURED FIELDS SURVIVE, which is why this is a create and not a
    // message: mint_capture_card titles a card from the prompt text and has
    // nowhere to put a type, a desc or a due date.
    assert_eq!(v["type"], json!("investigation"), "{v}");
    assert_eq!(v["desc"], json!("WS5 of the standalone epic"), "{v}");
    assert_eq!(v["due"], json!("2026-09-30"), "{v}");

    // And it is DISPATCHABLE by the target, which the reviewer link never was.
    // `todo` is what board-drive hands out; `backlog` sits until someone pulls
    // it, and sitting is the defect.
    assert_eq!(v["status"], json!("todo"), "{v}");
    let id = v["id"].as_str().expect("id").to_string();
    let conn = store.read().unwrap();
    let dispatchable: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM issues WHERE id=?1 AND session='lane-b' \
             AND status='todo' AND owner_type='agent' AND deleted IS NULL",
            rusqlite::params![id],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(dispatchable, 1, "the target's dispatch query must return it");
}

/// The relaxation is for the request shape ALONE. A plain cross-board create
/// stays refused, and if it did not, this whole change would be "any lane may
/// write to any board" wearing a narrower name.
#[tokio::test]
async fn a_plain_cross_board_create_is_still_refused() {
    let (app, _store, _dir) = app();

    let (st, v) = post_as(
        &app,
        "lane-a",
        json!({ "title": "not yours to file", "session": "lane-b" }),
    )
    .await;
    assert_eq!(st, StatusCode::FORBIDDEN, "{v}");
    assert_eq!(v["code"], json!("cross_board_create_forbidden"), "{v}");
    // The refusal must name the verb that DOES route work, or it sends the
    // caller back to the reviewer link whose cards nobody sees.
    let how = v["how_to_fix"].as_str().unwrap_or_default();
    assert!(how.contains("request_to"), "the refusal must point at the working path: {how}");
}

/// `requested_by` comes from the verified header and NEVER from the body.
/// A body that could name its own requester would let a lane route work while
/// pointing the callback, and the accountability, at someone else.
#[tokio::test]
async fn the_body_cannot_choose_who_the_requester_is() {
    let (app, _store, _dir) = app();

    let (st, v) = post_as(
        &app,
        "lane-a",
        json!({
            "title": "attributed to the caller",
            "request_to": "lane-b",
            "requested_by": "someone-else",
        }),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED, "{v}");
    assert_eq!(v["requested_by"], json!("lane-a"), "the header wins: {v}");
    assert_eq!(v["callback"]["session"], json!("lane-a"), "{v}");
    // And the ignored-field report says the key went nowhere, rather than
    // letting the caller believe it landed.
    let ignored = v["ignored_fields"].as_array().cloned().unwrap_or_default();
    assert!(
        ignored.iter().any(|k| k == "requested_by"),
        "an unhonoured key must be reported as ignored: {v}"
    );

    // A callback aimed at a third party is refused outright rather than
    // silently rewritten, because the caller asked for something specific.
    let (st, v) = post_as(
        &app,
        "lane-a",
        json!({
            "title": "callback elsewhere",
            "request_to": "lane-b",
            "callback": {"session": "lane-paused"},
        }),
    )
    .await;
    assert_eq!(st, StatusCode::FORBIDDEN, "{v}");
}

/// Who may receive a routed request, and who may not. Each refusal has its own
/// status because they are different problems: a typo, an opt-out, and a lane
/// that is gone.
#[tokio::test]
async fn a_request_target_must_be_a_lane_that_can_receive_one() {
    let (app, _store, _dir) = app();

    for (target, want_status, want_code) in [
        ("lane-nobody", StatusCode::NOT_FOUND, "unknown_lane"),
        ("lane-iso", StatusCode::FORBIDDEN, "isolated_lane"),
        ("lane-archived", StatusCode::CONFLICT, "archived_lane"),
        ("../escaped", StatusCode::BAD_REQUEST, "invalid_lane_name"),
    ] {
        let (st, v) = post_as(
            &app,
            "lane-a",
            json!({ "title": format!("to {target}"), "request_to": target }),
        )
        .await;
        assert_eq!(st, want_status, "{target}: {v}");
        assert_eq!(v["code"], json!(want_code), "{target}: {v}");
    }

    // A PAUSED lane IS a valid target. A pause ends, and paused lanes already
    // hold cards (AMUX-4663 is four of them), so refusing here would make a
    // lane's own pause silently reject work meant for it.
    let (st, v) = post_as(
        &app,
        "lane-a",
        json!({ "title": "waits for the resume", "request_to": "lane-paused" }),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED, "a paused lane must still receive: {v}");
    assert_eq!(v["session"], json!("lane-paused"), "{v}");

    // Routing to yourself is a plain create with extra steps, and accepting it
    // would arm a callback from a lane to itself.
    let (st, v) = post_as(
        &app,
        "lane-a",
        json!({ "title": "to myself", "request_to": "lane-a" }),
    )
    .await;
    assert_eq!(st, StatusCode::BAD_REQUEST, "{v}");
    assert_eq!(v["code"], json!("request_to_self"), "{v}");

    // An unverified caller cannot route: there would be nobody to attribute it
    // to and nobody to report back to.
    let (st, v) = post_as(&app, "", json!({ "title": "anon", "request_to": "lane-b" })).await;
    assert_eq!(st, StatusCode::BAD_REQUEST, "{v}");
    assert_eq!(v["code"], json!("request_requires_verified_caller"), "{v}");

    // A `session` that disagrees with `request_to` is an ambiguity, and picking
    // either silently would file the card somewhere nobody asked for.
    let (st, v) = post_as(
        &app,
        "lane-a",
        json!({ "title": "two answers", "request_to": "lane-b", "session": "lane-paused" }),
    )
    .await;
    assert_eq!(st, StatusCode::BAD_REQUEST, "{v}");
    assert_eq!(v["code"], json!("request_target_ambiguous"), "{v}");
}

/// A routed request keeps its OWN record; the semantic intake never folds it.
///
/// `plan_create` treats `request_to` as structured, alongside `callback` and
/// `depends_on`, so the model comparison is skipped. Without that, a delegation
/// could be appended into whatever other card happened to be open on the
/// target's board, and the callback would answer the requester about THAT card.
/// AF-616 is the same shape without a requester attached: a capture folded into
/// an unrelated finding carded in the same minute, so the trail from the report
/// to its fix ran through a card about something else.
///
/// The first cut of AMUX-4653 instead armed the callback on the fold path. A
/// mutation deleting that block left the suite green, because folding needs a
/// model client and no test has one, so the cell was asserting about the create
/// path while claiming to cover the fold. This asserts the reachable fact.
#[tokio::test]
async fn a_routed_request_keeps_its_own_record_rather_than_folding() {
    let (app, _store, _dir) = app();

    let (st, first) = post_as(
        &app,
        "lane-a",
        json!({ "title": "ship the bundle installer", "request_to": "lane-b" }),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED, "{first}");

    let (st, again) = post_as(
        &app,
        "lane-a",
        json!({ "title": "ship the bundle installer", "request_to": "lane-b" }),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED, "a repeat is its own record: {again}");
    assert_ne!(first["id"], again["id"], "a fold would have returned the first id");
    assert_eq!(again["intake"]["action"], json!("create"), "{again}");
    assert_eq!(
        again["intake"]["comparison"]["decision"]["reason"],
        json!("explicit task structure must be preserved in its own record"),
        "the intake must say WHY it did not compare: {again}"
    );

    // And the second one is armed in its own right, so a requester who asks
    // twice is answered twice rather than silently once.
    assert_eq!(again["requested_by"], json!("lane-a"), "{again}");
    assert_eq!(again["callback"]["state"], json!("armed"), "{again}");
}
