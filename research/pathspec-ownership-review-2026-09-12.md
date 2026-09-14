# Ownership review after a refused pathspec commit

AF-746 bounded follow-up to ts-gke's complete report. The reported final commit was a correct 66-line append; the pre-override index comparison did not establish that fact. No foreign repository or reported commit was modified.

`git commit <path>` constructs a temporary index for its hooks. After refusal, the ordinary index can still contain no entry changed on that path. The old cached-diff hint therefore returned identical empty output for an append and an unrelated rewrite.

The installed-hook regression runs actual refused Git pathspec commits in a disposable repository. Both append and rewrite subcases confirm that HEAD stays unchanged and the ordinary cached diff remains empty afterward. It then executes the command printed by the hook and requires the candidate content to remain visible. The old hook failed both subcases; after correction all seven fixture tests pass, including recorded-peer and blind-cotenant protection.

The hint uses `git diff HEAD` for a pathspec retry because HEAD is the commit's baseline. Origin can differ from that baseline. Ordinary staged commits retain `git diff --cached`, with an explicit requirement to stage intended changes first. Empty output, missing HEAD or command failure is not a completed ownership check. This changes guidance, not override authorization or guard verdicts. New block-log fields count the paths requiring candidate review; they do not assert that a person performed that review.

Validation artifacts: scratch/ios-simulator-review/pathspec-hint-before.log and pathspec-hint-after.log. Server hint checks, publication and installation evidence are recorded on AF-746 as they complete.

Validation before commit: `python3 scripts/git-hooks/test_observed_ownership.py` -> seven passed, including two real pathspec candidate subcases; the old hint failed both. `scripts/safe-cargo.sh test -p amux-server --lib api::git_guard::tests -- --test-threads=1` -> 76 passed, zero failed. `bash scripts/test-staged-guard-render.sh` -> five passed, zero failed; `bash scripts/test-staged-guard-coedit.sh` -> 12 passed, zero failed. Hook version is 17 so installed-copy inventory can distinguish the changed guidance. Exact logs use the `scratch/ios-simulator-review/pathspec-hint-` prefix.
