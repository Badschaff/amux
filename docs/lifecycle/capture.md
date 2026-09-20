# Capture: From Prompt to Board Card

Reference: `crates/amux-server/src/api/board_lifecycle.rs`, `board_intake.rs`.

## Delivery Flow

When a prompt lands in a session:

1. **Intake gate** (`board_lifecycle.rs:stage_owner_command`, line 38)
   - Check: is feature enabled, is model available, is meaningful (not informational query or ack), is from non-isolated session
   
2. **Candidate search** (`board_intake.rs:candidates`, line 131)
   - Query non-archived, non-terminal cards matching the prompt's keywords
   - Rank by title hits (×8 weight), body hits, session match (+2 weight)
   - Return top N candidates for semantic comparison

3. **Semantic comparison** (`board_lifecycle.rs:Decision`, line 73)
   - Model judges: `create` new card, `append`/`update` existing open card, or `verify` closed card
   - Confidence must be ≥0.85; reason required
   - Model timeout: 20s default (line 32, `AMUX_INTAKE_MODEL_TIMEOUT_MS`)
   - Skip if prompt has structured metadata (`STRUCTURED_KEYS`, line 146)

4. **Decomposition** (`board_lifecycle.rs:Step`, line 54)
   - If kind = "tasks", model decomposes into 1..32 steps
   - Each step: key, title, description, item type, action (create/append/update/verify), acceptance criteria
   - Validate: no empty keys/criteria, unique titles, valid actions, dependencies form DAG

5. **Card creation**
   - New card: title, description, type (code/escalation/etc.), status=todo, session owner
   - Stored: source=capture, prompt digest, evidence nil, acceptance_criteria JSON array
   - Linked: acceptance criteria as durable entities, dependencies as edges

**Result**: One card per step, all visible on board immediately, gated by their type's default gate.
