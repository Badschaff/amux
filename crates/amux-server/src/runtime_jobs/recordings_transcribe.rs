//! `recordings-transcribe` (AMUX-4624): turns recordings synced from the
//! dashboard's Record tab into transcripts with a local whisper.cpp model.
//!
//! The work list is the recordings folder itself: a sidecar whose transcript
//! still owes work (see `api::recordings::needs_transcription`). So a restart,
//! a crash mid-transcription, or a model installed after the recordings were
//! made all resolve on the next tick with nothing to reconcile. An upload
//! triggers a tick at once; the interval is the safety net.

/// Every 30 min by default; `AMUX_RECORDINGS_TRANSCRIBE_SECS=0` disables it.
///
/// Long on purpose. The tick does the transcription itself, so the registry
/// times it honestly, and the registry calls a tick in flight past
/// `2.5 x interval + 15 s` hung. At 120 s that line is 5 min 15 s, which one
/// half-hour recording crosses. At 30 min it is 75 min. Latency does not
/// depend on this: boot, every upload and the Re-transcribe button all
/// trigger a tick immediately.
pub fn spawn(state: crate::api::AppState) -> super::PeriodicTask {
    let name = super::registry::ids::RECORDINGS_TRANSCRIBE;
    let secs = std::env::var(super::per_job_disable_var(name))
        .ok()
        .and_then(|v| v.trim().parse::<u64>().ok())
        .filter(|s| *s > 0)
        .unwrap_or(1800);
    super::spawn_periodic(name, secs, move || {
        let state = state.clone();
        async move { crate::api::recordings::transcribe_pending(state).await }
    })
}
