# Installer committed source and private artifacts — AF-783

The installer could compile a peer's uncommitted source and immediately install
it. The first correction, e7a34fa2, pinned source to one committed Git snapshot.
Independent review confirmed that selection but demonstrated a remaining P1:
another build could replace shared `target/release` executables after compilation
and before either publication read. The source log could therefore name the right
commit while the installed bytes belonged to someone else's draft.

The correction keeps the shared Cargo dependency cache, but invokes `cargo rustc`
for the server and Rust CLI separately, with `--emit=link=<private executable>`.
Rustc writes each final linked output directly to an invocation-private directory
while Cargo owns its build lock. There is no post-build copy from shared release
paths. A fixed ASCII `/tmp/amux-install-link.XXXXXX` prefix avoids commas in the
rustc emit-option grammar. Source selection still pins HEAD once, rejects an
unmerged index or unavailable Git, uses a clean detached worktree and its committed
safe-cargo wrapper, preserves relative-target resolution and cleans temporary
source/compiler directories.

The installer creates a private stage on the destination filesystem. The helper
records a manifest containing the pinned commit, SHA256 and size of both private
executables. The installer verifies originals, prepares both publication copies,
and verifies both copies against that manifest before changing either installed
path. `os.replace` then atomically replaces each installed executable. A mismatched
second artifact cannot leave the first installed as a side effect of validation.
A later rename failure records the exact already-published names; this is two
atomic file replacements, not a transactional pair or a lock against a separate
subsequent auto-builder deployment.

Source choices and artifact record/verify/publish events persist in
`AMUX_HOME/logs/server-install.log`. Mismatch events retain the artifact name,
expected and actual identities, and pinned commit. Missing or malformed artifacts
refuse with a diagnostic, and a publication failure records partial progress.
Audit write failures remain visible on stderr. This is a computed filesystem
safety boundary, not a model judgment or a new amux primitive.

## Evidence

The actual installer executes through both Rust binary publications in eleven
disposable Git repositories. A compiler fixture derives executable sentinels from
the files it actually reads. The install fixture copies bytes into temporary
paths; a committed fake Bash installer exits 91 after both Rust publications,
before hooks, services or databases. Refusal cases start with two old installed
sentinels and must preserve both. Fault injection replaces only shared output
names at compiler return, before the first install read and between the two copies.
A separate case alters the private CLI after preparing the server copy and must
refuse the pair. Injection markers/readbacks and stage cleanup are asserted.

Final eleven-case suite against the complete exact e7a34fa2 installer/helper tree:
`AMUX_INSTALLER_SOURCE_ROOT=<exact e7 snapshot> python3 scripts/test-install-committed-source.py`
-> **66 passed, 13 failed**. This is the source-only baseline, not the older d2bd
baseline. Final corrected suite -> **79 passed, 0 failed**. The preceding ten-case
artifact population was **48/4 red**, **52/0 green**; the initial source-only
seven-case population was **15/18 red** against d2bd45a4 and **33/0 green** at e7.
These are different populations, retained rather than relabeled.

A tiny real Cargo crate independently tested the compiler mechanism against the
same shared target: `cargo rustc --release --bin amux-installer-artifact-probe --
--emit=link=<private path with spaces>` -> exit 0, exact private output executable
printed `COMMITTED-PRIVATE-OUTPUT`. An earlier `-o` experiment returned exit 0 but
produced a hash-suffixed path and warnings; it was rejected and is not the shipped
approach. The corrected helper then compiled the actual amux server and Rust CLI from
pinned e7a34fa2 source using the shared target -> **exit 0**. Both direct private
outputs were nonempty executable Mach-O files; manifest verification -> **exit 0**.
This run used the draft corrected helper with pinned production Rust sources,
not a production installation and not a claim to have compiled a later commit.
Raw build/identity evidence: `real-private-build.log`, `real-private-verify.log`,
`real-private-artifacts/manifest.json` under the same evidence directory.

Raw artifacts: `scratch/af783-evidence/artifact-final-red.log`,
`artifact-final-green.log`, `artifact-red.log`, `artifact-green.log`,
`compiler-prototype.log`, `compiler-emit-prototype.log`. The existing CI check runs
the updated fixture, and VERIFY.md describes its passing result and limits.

No production installer, service or database mutation was used as a negative
control. Rust executable publication is the scope here; templates, Bash CLI and
service configuration follow their existing installation paths. A same-user actor
that deliberately tampers with private paths or installer scripts is outside this
shared-target race model. Source selection excludes drafts, but does not assert
that every committed change has already passed its separate release gates.

Originating SESSION remains board-drive (AMUX-2637), with historical identity
unresolved. Publishing attribution and independent review are not its agreement.
Keep AF-783 and its ledger entry pending actual originating-session validation and
all resolved verification gates.
