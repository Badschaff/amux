# Simulator route catalog omission (AMUX-4468 / AMUX-4469)

AF-748 independent board audit reproduced a diagnostic contradiction on the same
process image: GET /api/browser/ios/targets returned measured=true and ten targets,
while /api/debug/routes enumerated 388 routes with no /api/browser/ios entries.
Fresh route.callers_have_routes results failed for the simulator prefix and its
literal targets caller. These were continuing incidents, not stale board rows.

The handlers were mounted. ROUTE_TABLE omitted all ten of them. The completeness
walk inspected api/mod.rs and browser.rs, but did not descend through browser's
own .nest("/ios", ios::routes()) call. Its green result said nothing about this
second composition level. The prefix extracted from the SPA's URL rewrite had
no matching descendant in the catalog either; there is no new GET /ios root
handler in this correction.

The correction records the ten actual paths and verbs. The test now descends
through literal nested router calls, resolving local/self/super/crate module
paths and preserving the accumulated route prefix. It reads each named function,
reports unreadable modules, bounds recursion, and requires a positive canary for
the newly covered shape. It also reaches the existing sibling browser/import
nest. This remains a source scanner for literal calls, not a Rust AST evaluator
or a promise to resolve arbitrary computed router expressions.

Operational visibility uses the existing invariant incident warnings and request
log route verdicts. The catalog correction makes those consumers describe the
real simulator handlers; it does not suppress the invariant or add an allowlist.

## Validation

- Extended completeness walk on the pre-fix catalog: 0 passed, 1 failed, naming
  exactly the ten omitted simulator paths (ios-route-catalog-red.log).
- Full route_table integration target after correction: 2 passed, 0 failed.
  The other test walks the actual axum router in both directions, checking the
  advertised HTTP method set and refusing a non-advertised method.
- With the new descent disabled via scripts/mutate.sh, the positive canary
  explicitly failed for /api/browser/ios/action: 0 passed, 1 failed. The wrapper
  restored the source (ios-route-traversal-negative.log).
- The initial test draft had a Rust split/rev compile error. It was corrected
  before the behavioral negative control and is not counted as a reproduction.

Private evidence is retained under scratch/af748-board-drain and registered on
AF-748. Post-commit gates and deployment readbacks belong on the linked cards.
No simulator session was started, stopped or navigated for this correction;
the inventory request and route-method tests require no active Safari ownership.
