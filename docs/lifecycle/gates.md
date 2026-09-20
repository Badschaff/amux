# Gates: Evidence Requirements Before Done and Verified

Reference: `crates/amux-core/src/verification.rs:VerifierKind`, `board.rs:apply_transition:gate_check`.

## What Gates Block

Every transition checks `gate_check(task, new_status, effective_gates, evidence)`.
Gates block **done** (requires evidence per type) and **verified** (requires independent proof).

## Verifier Kinds (cost-ranked by line 76)

| Rank | Kind | Cost | Evidence | Suggested Command |
|------|------|------|----------|-------------------|
| 0 | Command | Free | exit code + output | `cmd; echo $?` |
| 1 | HttpCheck | Free | status code | `curl -s -w '%{http_code}' <url>` |
| 2 | FileExists | Free | stat result | `test -e <path>` |
| 3 | Temporal | Free | date proof | `date -d @<timestamp>` |
| 4 | PlaywrightAssertion | Cheap | screenshot artifact | (no one-liner) |
| 5 | ModelJudgment | Expensive | transcript | (runs last only if deterministic checks pass) |

## Evidence Requirements

**Evidence shape** (`verification.rs:Evidence`, line 181):
- `kind`: EvidenceKind matching verifier (CommandOutput, HttpResponse, FileStat, TemporalCheck, PlaywrightArtifact, ModelTranscript)
- `description`: one-liner ("cargo test: 214 passed")
- `artifact`: path/URL to proof (test log, screenshot, run transcript)
- `produced_at`: timestamp (caller-supplied, never clock-read)
- `source`: SelfReported (default, weakest) | Independent | Corroborated

**Invariant 28** (Evidence Independence): verification cannot rely solely on evidence produced by the actor being verified. Use Independent or Corroborated source for auditable gates.

## Type-Specific Gates

Default gates derive from item type; `gate` field on card overrides. See `board.rs:apply_transition` line 770 (approve to Done) and line 795 (Done to Verified).

**Terminal statuses** are immutable once reached. Verification failure reverts Done → Doing to revoke the claim, not discard the work.
