# Terminal browser fixture contracts (AF-772)

The full AF-768 CI run at 3c174603 completed all 1,011 tests and reported 80 unexpected outcomes. This bounded correction repairs four terminal specs; it does not clear the remaining browser failures or the AF-748 board drain.

## Changes and failure signals

- Match the first worker history page by endpoint, worker, offset and a positive bounded integer limit. The fixture previously required limit=200 while the shipped client requests 60. Return only the requested rows. Keep the route-hit guard enabled: a missing request remains a failing fixture, not an allowed unused route.
- Preserve the shipped grid tab icon (introduced by 7e0b0ecb), accessible name, title, 44px tap-size and actual menu open/close assertions. AF-752 restored the main header bell/gear; it did not introduce this tab glyph.
- Initialize the standalone tab-menu context as an existing installation with walkthrough complete. No forced click through onboarding or global fixture change.
- Move the existing terminal reader helper into reader-scroll.ts and use it from the bottom-opening test. Mobile WebKit has no mouse.wheel; its browser specimen uses a trusted padding tap then scrollTop positioning, explicitly reported as native_swipe:false. Desktop still uses wheel.
- Wait for the actual scroll listener to leave following and set the reader lock before releasing delayed history. WebKit can expose the new scrollTop before dispatching scroll; the earlier helper only awaited the position. The original buffering and jump-to-bottom assertions remain unchanged.
- Remove the Gemini renderer test's second fleet route registered after navigation. The test explicitly sets its renderer provider; the beforeEach route still supplies the actual fleet request. The unused-route failure remains enabled for all other fixtures.

The e2e output records e2e_reader_scroll with measured, n_considered, method, native_swipe, before and after. Product reader gestures already emit the server-visible peek-poll / bottom-follow-paused beacon with measured population and input. Route misses, invalid pagination, reader-lock failure, buffering and geometry failures remain hard assertions. No product runtime source changed.

## Measured evidence

Artifacts are under scratch/af748-board-drain in the canonical checkout.

- Exact parent 153c57fa, terminal-product history/live seam on ios-safari: 1 failed, expected 3 human rows but got 0 (af772-history-red.log). CI also retains the original unsupported wheel, old Tabs text and onboarding interception failures.
- First corrected Safari run: 44 passed, 1 failed (redundant Gemini route, then removed). First all-project run: 134 passed, 1 failed (delayed-history fixture ran before the scroll listener). Preserve af772-safari.log and af772-matrix.log.
- Corrected delayed-history ordering, ios-safari --repeat-each=3 --workers=1: 3 passed (af772-scroll-order.log).
- Final all-project run: 135 passed, 0 failed (af772-matrix-final.log), with all three projects and all four specs retained. Personally viewed Safari and desktop terminal-navigation.png and mobile open-bottom.png: navigation lands at the message start below the controls; the late-layout specimen keeps LATEST_OUTPUT_END visible. The latter intentionally sets a 240px output height, so its whitespace is fixture setup. Added tab-menu screenshots for the clean exact-commit review run.

## Actual native iOS surface

Real local iPhone 17, iOS 26.5, XCUITest with nativeWebTap=true; source 153c57fa / build 0d6f0c18ec645d28 stable across /health brackets. Opened only amux-frustrations' existing terminal. No worker command, task run or original message was sent.

The first swipe had concurrent log growth, so its absolute-position comparison was inconclusive and retained as a negative control. Paused background polling to establish the reader specimen, used the real native Jump control, then dispatched XCUITest scroll -350. The reader moved from scrollTop 28403 to 28079, stopped following and locked. One explicit GET refresh left scrollTop at 28079. The new sticky badge adds 30px height plus 8px margin; measured scrollHeight rose by exactly 38px. The original raw total-equality verdict therefore failed on an affordance change, not terminal content growth. af772-native-verdict.json accounts for the separately measured badge geometry and rejects the first unstable specimen. All original raw verdicts remain readable.

Viewed af772-native-bottom.png, af772-native-after-swipe.png and af772-native-held.png personally: visible toolbar, grid tab control, earlier terminal content and New output control; no document overflow at 402px. The owned native session was stopped successfully (af772-native-stop.json). This is one native reader journey, not physical-device coverage, every modal or the full amux lifecycle.

## Remaining scope

AF-773 owns worker-lifecycle teardown and masked primary failures. Other AF-768 failures, including interaction receipts, service-worker save-bar visibility and file/modal flows, remain under AF-748. No full CI green or final verification is claimed by this fixture correction.
