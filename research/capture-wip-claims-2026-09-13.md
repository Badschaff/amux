# AMUX-3757: use the same WIP holders across board claims

The old automatic-pickup correction did not reach manual PATCH claims. An
unanswered capture in Doing still blocked PATCH, and the ready frontier reported
zero capacity even though automatic pickup exempted that same capture. The
reopened card records AMUX-3958 blocking AMUX-3962; this correction addresses that
manual-claim recurrence, not a claim that the old automatic-pickup fix never worked.

A shared WIP-holder function now serves PATCH, status-update claims, ready
frontier, automatic pickup and identity-backed child restoration. It uses the
canonical capture predicate (including leading whitespace), existing dormant
kind/needs:you exemptions, and the existing unblocked/dependency predicate.
Reshaping a captured prompt into real work makes it hold capacity again. Captures
remain readable and are not discarded by this function. Existing per-consumer
capacity policy is unchanged; the shared part is which cards consume capacity.

A failed holder query or card read is propagated instead of becoming an empty
population. Pickup refuses with wip-unmeasured, and the frontier advertises zero
available capacity with wip.measured=false and why_unmeasured. Existing dependency
resolution semantics remain in doing_is_unblocked. Capture exemptions emit INFO
with considered/capture/holding counts; query failures emit WARN with measured=false
and the cause. A thread-local tracing subscriber test checks the written signals.

Validation before commit:

- Two API fixtures against the previous implementation: 0 passed, 2 failed.
  One exposed PATCH blocking on WC-1; the other exposed zero frontier capacity.
  Both rows are seeded directly so create-time capture folding cannot erase the
  positive specimen before the claim is exercised.
- scripts/test-contended.sh -p amux-server --test board_api: 91 passed, 0 failed.
- scripts/test-contended.sh -p amux-server --lib runtime_jobs::board_drive::tests:
  151 passed, 0 failed, including whitespace, unreadable population and actual
  log-output checks.
- scripts/mutate.sh changed the helper's canonical capture test to creator-only:
  1 passed, 1 failed; the named reshape assertion rejected the erroneous HTTP 200
  (real work must still return 409). Mutation restored.
- Restored focused API fixtures: 2 passed, 0 failed.

Private logs are registered on AF-748 under scratch/af748-board-drain/amux3757-*.
These are source/isolated-router checks, not a fresh production card mutation,
browser interaction, complete server-suite or deployment claim.
