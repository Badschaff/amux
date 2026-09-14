# Sticky session fixture discovery race

AF-766 addresses the final ecd36b56 CI failure: the first GET /api/sessions in the sticky runtime-board HTTP fixture retries the explicit structural discovery refusal, but the second, idle-state read bypassed that policy. GitHub job103697705922 failed at workers.rs2537 with500 and the exact discovery-change response;2376 library tests passed,1failed,8ignored. This is distinct from AF-757's real-worker quota signal contamination.

A one-shot middleware refusal is armed only for the idle read, then requests reach the real router again. Before correction the existing fixture failed0/1 with the exact CI response at the idle assertion. This makes the formerly timing-dependent boundary deterministic without weakening any active, blocked, conflicting-claim, decomposed or idle board-truth assertion.

Both reads now use one fixture helper with at most five attempts. Only500 plus the exact structural-change message retries. Negative HTTP controls retain an unrelated500 after one read and retain persistent structural churn after five reads. Each retry writes a fixture_session_discovery_retry JSON diagnostic with phase,attempt,max_attempts,measured and count to the test log. The existing production warning and fail-closed stale-response behavior are unchanged.

No live worker, global epoch control, HOME or fleet configuration is changed by this correction. The fixture's old named-worker contamination remains separately tracked by AF-757. Evidence under scratch/af748-board-drain/sticky-idle-race-*.log; clean gates and independent review are recorded on AF-766.

Author validation: corrected worker HTTP group with four threads passed30 and failed5. Both the deterministic sticky fixture and new failure/bounded-churn control pass. The five failures are unchanged worker-start admission503 cases on this host (about49.7GBswap against the8GBthreshold); this is not a full-green suite claim. Pre-fix deterministic idle refusal failed0/1 with the exact CI response. The earlier final CI had only the idle-race failure in its2377-test library population.
