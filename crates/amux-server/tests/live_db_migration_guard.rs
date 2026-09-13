//! AF-786: exercise the real guard/apply boundary without opening the live DB.
use amux_server::db::migrate::apply_all_guarded;
use rusqlite::Connection;
use std::path::PathBuf;

fn schema_objects(conn: &Connection) -> i64 {
    conn.query_row("SELECT COUNT(*) FROM sqlite_master", [], |r| r.get(0))
        .unwrap()
}

#[test]
fn working_tree_migrations_require_live_database_opt_in() {
    if std::env::var_os("AMUX_MIGRATION_GUARD_TEST_CHILD").is_none() {
        // The override is process-global. Isolate its two cases rather than
        // racing unit tests or changing the developer's HOME/database config.
        for allow in [false, true] {
            let mut cmd = std::process::Command::new(std::env::current_exe().unwrap());
            cmd.args([
                "--exact",
                "working_tree_migrations_require_live_database_opt_in",
                "--nocapture",
            ])
            .env("AMUX_MIGRATION_GUARD_TEST_CHILD", "1")
            .env_remove("AMUX_ALLOW_LIVE_DB");
            if allow {
                cmd.env("AMUX_ALLOW_LIVE_DB", "1");
            }
            let output = cmd.output().unwrap();
            eprintln!(
                "allow={allow} {}{}",
                String::from_utf8_lossy(&output.stdout),
                String::from_utf8_lossy(&output.stderr)
            );
            assert!(
                output.status.success(),
                "guard subprocess failed: allow={allow}"
            );
        }
        return;
    }
    let home = std::env::var_os("HOME").expect("HOME is required to express the live-path guard");
    let live_path = PathBuf::from(home).join(".amux/amux.db");
    let exe = std::env::current_exe().unwrap();
    assert!(
        exe.components()
            .any(|p| matches!(p.as_os_str().to_str(), Some("debug" | "release"))),
        "this must actually execute a cargo-built artifact: {}",
        exe.display()
    );
    // The supplied path is ONLY guard input. All SQL goes to this in-memory
    // connection; neither this test nor apply_all_guarded opens the supplied path.
    let mut conn = Connection::open_in_memory().unwrap();
    assert_eq!(schema_objects(&conn), 0);
    let result = apply_all_guarded(&mut conn, &live_path);
    if std::env::var_os("AMUX_ALLOW_LIVE_DB").is_some() {
        result.expect("explicit opt-in must permit the guarded migration");
        assert!(schema_objects(&conn) > 0);
        let count: i64 = conn
            .query_row("SELECT COUNT(*) FROM _amux_migrations", [], |r| r.get(0))
            .unwrap();
        assert!(count > 0, "must have actually applied embedded migrations");
        eprintln!("opt-in control: {count} migrations applied IN MEMORY");
    } else {
        let error = result
            .expect_err("a cargo build must refuse pending live migrations")
            .to_string();
        assert!(
            error.contains("refusing to apply") && error.contains("LIVE database"),
            "{error}"
        );
        assert!(
            error.contains("0013_search") && error.contains("AMUX_ALLOW_LIVE_DB=1"),
            "{error}"
        );
        assert!(error.contains(&live_path.display().to_string()), "{error}");
        assert_eq!(
            schema_objects(&conn),
            0,
            "refusal must precede every migration/schema write"
        );
        eprintln!("refusal control: schema_objects=0; {error}");
        let scratch = tempfile::tempdir().unwrap();
        apply_all_guarded(&mut conn, &scratch.path().join("scratch.db")).unwrap();
        assert!(
            schema_objects(&conn) > 0,
            "scratch-path control must actually migrate"
        );
        // Already-applied migrations never require opt-in, even with a live label.
        apply_all_guarded(&mut conn, &live_path).unwrap();
    }
}
