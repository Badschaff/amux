# Preserve the offline warning's space during keyboard sizing

AF-777 corrects the shared keyboard rule overriding the board editor's existing warning-height reservation. The backdrop already adds the measured `--sw-fail-h` to bottom padding; the board box must subtract that same obstruction when its max-height uses `--dialog-viewport-height`. This preserves both the visible keyboard viewport and the real warning height without raising the modal above the warning or dismissing it.

The existing modal-layout probe now checks the intersection between the warning and footer buttons, then verifies the actual element at that overlap. A button centre can remain tappable while its lower edge is covered. Such partial coverage reports `board-edit-overlay:footer-covered-by-warning` through the existing measured `/api/client-debug` diagnostic. No dialog contents or credential values enter the signal.

APP_VER and CACHE move together to 0.9.937. State generation finds 1,936 functions / 659 command-capable handlers; generated state output is unchanged.

## Browser evidence

Original published ec76baf7 CI run 34753024521 failed the two Chromium positive `sw-fail-bar.spec.ts` cases. Existing wrong-height controls still reproduced coverage. Their complete records remain under `scratch/af748-board-drain/af773-final-ci-evidence` and `af773-final-ci-failures.json`.

On the owned working tree atop 2b06b400:

`AMUX_E2E_WORKING_TREE=1 npx playwright test --config e2e/playwright.config.ts e2e/sw-fail-bar.spec.ts e2e/sw-warning-dialog.spec.ts e2e/mobile-modal-layout.spec.ts --workers=2` -> **33 passed, 0 failed**. Log: `scratch/af748-board-drain/af777-browser-corrected.log`; artifacts: `af777-browser-corrected-results`.

The six original warning cases and 21 existing modal cases remain. Six new cases cover the real warning renderer, ResizeObserver publication at 375×667 / 320×568 / 402×350, five hit points across Save, a real Save POST with exact stored title/description, real warning dismissal and a broken-keyboard-height control. Each of the three broken controls records the actual measured client-debug diagnostic. Viewport resizing waits for one sample that simultaneously proves dialog measurement, settled geometry and full hit coverage.

The first new-test run was 31 passed / 2 failed (`af777-browser.log`): it sampled a dialog during its entry/resize transition, yielding n_considered=0 or a transient footer gap. The final test retains these requirements in its poll rather than dropping them. The old results remain preserved.

A script-free actual DOM/CSS probe (`af777-css-probe-corrected.json`) shows the original box above the viewport and part of Save under the warning, and the corrected box within its reserved area. Its button centres remained clickable, so it is supporting geometry, not reproduction of the exact CI centre-point failure. The first version accidentally retained the no-JS fallback overlay; that result is retained and is not product evidence.

## Native iOS evidence

`python3 scratch/af748-board-drain/af777-native-warning-visible.py` -> **2 passed, 0 failed** on native XCUITest Safari, iPhone 17 Simulator / iOS 26.5. The isolated server stayed at working-tree source `2b06b4004c9f-dirty`, build `773ac9ec976fe23c`, across both measurements. All five recorded product file hashes remained unchanged (`af777-product-hashes.json`). This is explicit working-tree evidence, not a claim that the eventual integration SHA was tested.

The native journey dismissed the real keyboard, tapped Save, and checked one exact server title/description. It then reopened the editor, dismissed its newly raised keyboard, required the warning within the visible viewport, checked full Save coverage, restored the obsolete height rule as a negative control, observed the actual measured warning-coverage diagnostic, restored the fix and tapped the real warning dismiss button.

Personally opened `af777-native-warning-visible-native-results/warning-and-save.png`, `warning-covers-save-control.png` and `warning-dismissed.png`: the corrected buttons sit entirely above the readable warning; the control visibly covers their lower portions; dismissal restores available editor space. Log: `af777-native-warning-visible-native.log`.

Earlier native attempts remain recorded. The clean-source guard first correctly refused an explicitly dirty working tree before testing. The next run saved the exact card, but reopening raised the keyboard and hid the warning; its negative control could not prove visible warning coverage. Screenshot inspection exposed this test setup issue. The final run requires actual native keyboard dismissal and warning visibility before testing that boundary; no product assertion was dropped.

## Remaining release proof

Clean commit gates, independent review, publication and live readback remain outstanding. This bounded correction does not close the full AF-748 board drain, the AF-768 full browser matrix, or the independent AF-776 native message timeout investigation. It does not establish physical-device or complete lifecycle behavior.
