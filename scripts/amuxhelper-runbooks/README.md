# Amuxhelper runbooks

Amuxhelper (`scripts/amuxhelper-poll.sh`) is a plain script, not an agent. It has
no judgment and cannot improvise — the only thing it can ever do is run a
script that already exists in this directory, named exactly by a board card.
That is the whole safety story: the set of possible actions is fixed here,
reviewed like any other code change, not invented at runtime by a card's text.

## How a card reaches amuxhelper

**Only a human (verified local member), never a worker, can route a card to
amuxhelper.** Tested live: a worker session gets `cross_board_create_forbidden`
/ `cross_board_reassignment_forbidden` from the board API for both creating
a card with `session=amuxhelper` and reassigning an existing card to it — by
design (`board.rs`: "a verified worker may only name itself as the
destination"). This is a real security property, not a gap to route around:
no agent can quietly hand real infrastructure-executing work to amuxhelper on
its own authority. A human does it from the dashboard, or an agent proposes
the exact card (title, `AMUXHELPER_RUNBOOK`, `AMUXHELPER_ARGS`, type `chore`)
for a human to create/reassign.

1. Create or reassign a card to `session=amuxhelper`, status `todo`, **type `chore`**
   (amuxhelper's claim/close calls ack that type's specific gate criteria;
   any other type's gate is unhandled and the claim will fail loudly).
2. Its `desc` names the runbook and its args, one line each, nothing else
   read from the card body:

   ```
   AMUXHELPER_RUNBOOK: flip-versioning
   AMUXHELPER_ARGS: bucket=gs://mvs-snapshots
   ```

   Multiple args are comma-separated: `key=val,key2=val2`. No spaces around
   `=` or `,` — the parser is deliberately dumb.

3. `scripts/amuxhelper-poll.sh` runs on a timer (see `amuxhelper-poll.plist`).
   Each tick: claim the card (`todo -> doing`, the normal lease), run the
   named runbook with `AMUXHELPER_ARG_<KEY>` env vars, then:
   - exit 0 -> `amux board done --evidence-stdin` (the runbook's own output
     is the evidence)
   - exit nonzero -> `amux board block --on "..."` (status stays wherever it
     was; the card is excluded from `ready` until a human looks at it)
   - unknown runbook name, or a name that doesn't resolve inside this
     directory -> refused before anything runs, `block`, never a guess

Nothing here retries and nothing here chains a runbook's output into a
decision. One command, one outcome, logged.

## Writing a new runbook

- `scripts/amuxhelper-runbooks/<name>.sh`, executable, `set -euo pipefail`.
- Read args from `AMUXHELPER_ARG_<KEY>` env vars (uppercased, `-` -> `_`).
  **Validate every arg yourself** — amuxhelper does not know what a sane
  bucket name or role looks like for your runbook, you do. Refuse (nonzero
  exit, clear stderr message) rather than guess.
- Idempotent: this may run more than once against the same target (a stale
  lock recovery, a re-approved card) and must not compound.
- Bounded: amuxhelper wraps every run in a timeout (`AMUXHELPER_TIMEOUT_S`,
  default 60s). Don't start something that can't finish in that window.
- No further delegation: a runbook must not itself invoke an LLM, spawn a
  worker, or read board state to decide what else to do. If the task needs
  judgment, it does not belong here — it belongs on a human's or an agent's
  board, not amuxhelper's.
- Adding a runbook is a normal reviewed commit. There is no "propose a
  runbook from a card" path, on purpose.

## Starter set (2026-09-15)

- `flip-versioning.sh` — enable GCS object versioning on an allow-listed bucket.
- `grant-bucket-role.sh` — grant one IAM role to one principal on one allow-listed bucket.
- `apply-staging-rbac.sh` — `kubectl apply` a specific, named RBAC manifest, staging only.

**Credentials are not amuxhelper's problem to solve.** Every runbook here
assumes the identity running amuxhelper already has whatever `gcloud`/`kubectl`
auth it needs — the same way `rust-auto-build.sh` assumes a signing identity
is already configured. If that identity isn't set up yet, a runbook fails
loudly (nonzero exit, card gets `block`ed with the real error) rather than
silently doing nothing.
