# Structured board intake (AF-785)

During AF-780's ledger drain, three explicit issue creates each paid for a semantic comparison. The create endpoint always called plan first, then preserve_structured_request unconditionally replaced that decision when explicit graph/gate/scheduling metadata required a new record. This deterministic branch should not call a model.

plan_create now applies the same metadata/type predicate before invoking a lazy comparison closure. create_item retains its lane lock, source/owner attribution, WIP checks and writer transaction. Ordinary creates still call the original semantic planner, including append/update behavior. No global semantic-intake setting changed.

Regression: first extracted the existing ordering into the caller's shared function, added a comparison spy, and ran it: 0 passed/1 failed, one comparison invocation versus required zero for depends_on. Corrected intake tests: 3 passed/0 failed. The new case covers all12 metadata keys and epic/watch/tripwire, plus empty/plain-request controls that invoke comparison and retain append/target. This measures planner invocation, not a paid provider call. The fixture fails if comparison is moved ahead of the structured branch again.

The structured branch emits an INFO record under amux::board_intake: verdict structured_create, measured true, n_considered1, model_called false, candidate_population_measured false. Plan.measured stays false and model absent because no semantic comparison happened. The ordinary planner is unchanged.

Raw evidence: scratch/frustrations-validation-evidence/structured-intake-red.log and structured-intake.log. Full board API suite:91 passed/0 failed with four threads. Exact clean release gates are recorded alongside this report when completed. No full-drain, full-CI or originating-session retirement claim follows from this bounded correction.
