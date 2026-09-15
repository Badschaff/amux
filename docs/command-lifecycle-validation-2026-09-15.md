# Command lifecycle validation — September 15, 2026

Three fresh Claude Haiku 4.5 workers were used, one at a time. All three are
paused. The command controller remains opt-in: automatic intake did not meet
the rollout bar. These scores describe demonstrated components, not a claim
that an arbitrary command now drains unattended.

| Iteration | Score / 10 | Observed result |
| --- | --- | --- |
| 1 | 2 | Previous live controller produced correct files and continued to another board task. Commands were not consistently retained, decomposition was missing, and refinement left stale canonical requirements. |
| 2 | 3 | Durable intake and canonical refinement worked; the execution worker stalled because its fresh idle composer aged out without a current-lifetime hook. No report files were produced. |
| 3 | 5 | Concurrent requests were acknowledged in about 35 ms; the duplicate made zero planner calls. Both attempts on the original were rejected. Separately identified, operator-created board fixtures verified seed reuse, correct files, dependent-task pickup, and pause/resume. These fixtures do not count as successful automatic intake. |

The third score awards one point each for duplicate suppression, existing-output
verification, continuation, terminal gates, and standing authority/pause. It
awards zero for automatic decomposition, refinement, dependency planning,
parallel planning, and successful bounded interpretation recovery.

## Token measurement

The two measured planning calls in iteration 2 consumed 51,837 input/cache tokens
and 5,152 output tokens together. The third iteration's two calls consumed
10,346 input/cache tokens and 1,630 output tokens, with zero thinking tokens.
That is about **80% less input/cache and 68% less output per measured call**.
Iteration 2 made three calls but one failed call lacked usage telemetry; this
comparison covers measured calls only. It is not a successful-work throughput
comparison or an invoice measurement.

Read-only planners now use compact candidates and omit unrelated memory files.
Working agents retain their project context. Deterministic reconciliation,
unchanged reminders, pending duplicates, and receipt recovery do not invoke a
model. Empty worker restarts produced zero model responses during live setup.

The third worker's separate execution fixtures recorded 22 response rows,
182 fresh input tokens, 1,072,084 cache-read tokens, 42,766 cache-write tokens,
and 6,579 output tokens. Those are working-agent costs, not planning overhead.

## Failures and changes

- Fixed the quiet-start deadlock; a live idle composer stayed admissible beyond
  the old timeout, and board work subsequently dispatched.
- Persist requests before planning and acknowledge asynchronously. Two concurrent
  deliveries with different transport IDs reused one interpretation receipt.
- Reuse durable advancement reminders until requirements or worker lifetime
  change. Failed/voided delivery is not counted as successful notification.
- The third planner confused a new verification task with the `verify` reuse
  operation, then invented canonical IDs during repair. Both were rejected and
  remain visibly pending. The final contract explains the distinction, reports
  every identity error together, and retains all raw attempt responses. This
  final wording change passed deterministic regression tests; no fourth paid
  worker trial was run, so its live effectiveness is unproven.
- The global `AMUX_APPROVAL_TYPES=budget,customer_outbound` policy is enabled.
  Worker/group overrides retain their documented precedence. Existing historical
  Needs You cards were not blindly relabeled or closed.

## Execution and pause evidence

After automatic intake failed, LHR0-7 and LHR0-8 were explicitly introduced as
execution fixtures on the same third worker. A transcript shows seed.json was
read before output writes. An independent evaluator checked names.txt,
counts.json, summary.md, the unchanged seed SHA-256, and check.txt containing
`PASS`. LHR0-8 depended on LHR0-7 and began without another chat request.

During LHR0-8's foreground heartbeat loop, Pause stopped the worker after six
writes. Its file and modification time remained unchanged for over 25 seconds.
Resume completed verification; both fixture cards reached Done before the
worker was paused again.

## Board activity visibility

Studio-plg was executing while the runtime reported `active-card-invalid`: its
observed claim was SP-787, which was in Backlog, and no current Doing task was
attributable. The generic Working badge concealed this distinction. The board
now keeps a current-activity strip visible across filters and highlights the
exact confirmed task. An invalid observed claim is shown separately in amber as
the last linked task; it is never silently promoted to a confirmed claim.

Task switches while remaining Active, SSE updates, worker detail list/kanban,
and Pause refresh the same activity projection. The change reuses AMUX-3004,
an older card for this display problem whose Done record still described an
unresolved question and had no verification evidence.

Browser checks passed in Chromium at 1280px and 390px, with API fixtures and all
writes refused. They created no workers or provider calls. Run
`node tests/board-activity-browser.mjs` against a local dashboard shell. The test
overlays the checkout's JS/CSS and checks missing links, exact-card emphasis,
same-status SSE task changes, filters, worker scope, and Pause.

The deployed build `187b6318` was subsequently checked with real API data and
unmodified served assets at both widths. Studio had moved to a valid SP-918
claim; its title and Working now state appeared on both boards. This live
screenshot check also exposed pre-existing mobile list rows shrinking below
their wrapped content. Rows now retain their content height, and the shared
component diagnostic reports `board-row-content-overflow` to client-debug if
that failure returns. The browser regression restores the old shrink rule
temporarily and confirms that the diagnostic detects it.

## Validation scope and remaining work

A detached full server run passed 2,501 unit tests plus integrations and doctests.
The one excluded test reads live host admission/swap rather than an isolated
fixture. Subsequent changes passed targeted lifecycle, delivery, board-drive,
approval-policy, board API and workspace Clippy checks. Dashboard syntax, SPA
lint, generated-state checks and the browser scenarios also passed.

The prior audit covered all 15 active workers: 635 open cards, including 485
Backlog and 89 Needs You. This implementation has not migrated that historical
backlog, automatically reassigned cross-worker ownership, or added a new parallel
executor pool. Existing WIP and lease limits still apply. A visible invalid task
link is useful observability, not proof that attribution has been repaired.
