# Installer committed-source build — AF-783

The recorded bug remains in the pre-fix installer at d2bd45a4: its Rust build runs
inside SCRIPT_DIR, then installs binaries produced from that mutable checkout.
An uncommitted source or migration can therefore become executable production code
without its author's commit. The automatic builder already uses a detached
snapshot; this is the separate manual installer entry point.

The installer now calls scripts/build-install-from-head.sh. The helper resolves
HEAD once, refuses an unresolved index or unavailable commit, creates a private
detached worktree at that exact commit, and runs its committed safe-cargo.sh with
build --release --workspace --locked. It retains the shared target directory and
cleans the private source worktree on success or failure. Relative targets resolve
against the original checkout before changing directories. Existing installation,
configuration and service paths continue to refer to the original checkout.

The source decision is printed and persisted in AMUX_HOME/logs/server-install.log.
It names the exact commit and whether uncommitted files were excluded. Refusals,
compilation failures and cleanup/audit failures have distinct diagnostic lines.
There is no fallback to uncommitted bytes and no model decision for this mechanical
source-selection constraint.

Validation executes the actual install.sh in seven disposable Git fixtures. The
compiler fixture builds its output from the source files it actually reads, and a
controlled install executable records the first binary's bytes then exits91 before
any real publication, service, hook or database mutation. Fixtures cover clean,
dirty plus untracked migration, HEAD advancing during compilation, relative target,
unmerged index, absent Git and build failure while stale outputs already exist.

The same final suite with AMUX_INSTALLER_UNDER_TEST pointing at a byte-identical
copy of d2bd45a4:install.sh ->15 passed,18 failed. In particular, dirty peer source
and the untracked sentinel reach publication, and a changing HEAD retargets the
old build's input. Current source ->33 passed,0 failed. The initial five-case
control was11/13 and initial corrected run24/0; those are earlier populations,
not relabeled as the final seven-case matrix. Syntax checks pass. The new fixture
is included in checks.yml, and VERIFY.md names its command and limitations.

Artifacts: scratch/af783-evidence/final-red.log, green.log, pre-fix-install.sh.
No real server installation was performed by these fixtures. They prove source
selection and publication-boundary bytes, not an independent real Rust compiler
or live server deployment. The existing shared-target build-to-copy concurrency
window is unchanged and is not certified by this fixture. This correction does
not claim all installer payloads (templates, Bash CLI, service files) are pinned;
its scope is the recorded Rust binary build hazard.

Originating SESSION remains board-drive (AMUX-2637), with identity unresolved.
Publishing commit attribution is not origin agreement. AF-783 and its ledger entry
must remain pending that actual agreement and the resolved verification gates.
