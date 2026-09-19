# Fan-out lifecycle

Fan-out execution uses the existing board, worker configuration and git worktree lifecycle. Orchestrations is a compact read-only projection (`GET /api/board/orchestrations`), not another task store. Its response declares measurement and the number of rows considered, includes full child boards and standalone ephemeral workers, and omits long prompt/history fields. Worker lifecycle controls pause classification; the shared type-specific terminal predicate controls progress. Code Done is not Verified. The compact response includes configuration-derived worker metadata; the page renders it immediately and reuses the normal single-flight status refresh without waiting for cold runtime probes.

## Ownership and execution

The canonical provisioner creates independent workers with board delegation disabled and backlog draining enabled. The worker owns all follow-up tasks on its board, not just the initial assignment. Normal prerequisites are implemented there; peer artifacts may be referenced without adding a cross-worker scheduling dependency. Real authorization and column gates remain enforced. Existing explicitly paused/archived/isolated workers stay excluded.

A fan-out starts only in its own durable `amux/fanout/<worker>` branch and `~/.amux/worktrees/<worker>` directory. A failed checkout refuses launch. Restart reuses that workspace; stop and pause never dispose files, index or commits. Explicit deletion remains a separate action.

## Automatic integration

The worker configures its repository check through `PATCH /api/sessions/<worker>/config` with `worktree_verify` (a shell command). New children inherit their parent's configured command. No model is called to discover commands or poll for progress.

At a confirmed turn boundary, integration becomes eligible only when the entire nonarchived child board is type-terminal or implemented in Review/Done with evidence, and all prerequisite edges are resolved. The harness then:

1. Captures the board revisions and clean immutable branch head.
2. Fetches main and creates a separate temporary merge candidate.
3. Runs the configured checks on the combined candidate, with git hooks enabled.
4. Rechecks lifecycle, board revisions, candidate and worker checkout.
5. Uses a normal, non-force push to remote main and verifies ancestry by fetch.

One candidate runs at a time. A remote race refuses the push and retains all work. Pause or changed board admission cancels validation and its subprocess group; validation output is bounded. Conflicts and failed checks return a deduplicated instruction to that same worker. Successful integration does not manufacture board evidence, acknowledge acceptance criteria, or bypass Verified gates. Retirement requires the whole board's terminal gates and an unchanged clean integrated head; the workspace is retained.

## Existing workspaces

At a provider boundary, healthy legacy worktrees can acquire their own branch without changing files. Their original creation base was never recorded. The worker must inspect its unmerged commits and explicitly supply a reviewed exact `worktree_base` through the same configuration API. The base must be an ancestor of both HEAD and origin/main. The harness never guesses that unrelated old history belongs in main.

An empty index over a populated commit is reported as an interrupted checkout and preserved. Missing workspaces require preservation of the running worker's changes before restart. Recovery stays with that worker and does not create a peer-board dependency or an ordinary Needs You item.

## Verification

`fanout_workspace::tests` exercises two independent workspaces, restarts with dirty files, main advancing concurrently, merge conflicts, failing checks, cancellation of validation descendants, incomplete checkout preservation, and whole-board admission. `api::orchestrations::tests` checks full child-board projection, scoped visibility, omitted history, and type-specific terminal states. `e2e/orchestrations.spec.ts` checks live endpoint rendering and deterministic failure/retry, orphan, pause, active-card and mobile layout cases.
