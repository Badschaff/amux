# Mobile header fit (AF-779)

The seven mobile controls now share one 56px row (57px including the border), with 44px tap targets. Twelve pixels of edge padding fits the seven targets at 320px; spare width is distributed between them. Compact labels now cover the full 600px mobile breakpoint. Removed redundant body top padding, retaining the safe area. Existing icons and desktop layout remain intact.

Parent 9550ba05 failed the new height assertion at 320px: 106px, expected <=57. Existing tests accepted wrapping there and applied compact styles only through 480px. The shipped header geometry check now reports `header-row-wrapped` through its existing measured `mobile-header-clipped` client-debug beacon. A deliberately narrowed wrapping header proves the beacon reaches server logs.

Candidate validation: `playwright test -c e2e/af779.local.config.ts mobile-header-visibility.spec.ts --workers=3` -> 9 passed. This temporary config starts private prebuilt API servers and the fixture serves exact candidate HTML/JS/CSS, retaining asset hashes. All six mobile widths (320,375,402,480,481,600) assert one row, bounds, 44px targets, center hit-testing, Settings and Add menus. Theme/desktop coverage and badge/ancestor-clipping controls remain. The new diagnostic test initially assumed six visible controls in an empty fleet; actual empty state has five, and the assertion now reflects that measured population.

`node scratch/af779-evidence/native.mjs` with the isolated API and candidate asset proxy -> 6 passed, 0 failed on real iOS 26.5 Safari/XCUITest: light/dark geometry and actual Notifications, Settings, Add and Active menu taps. API process build 6009bd6c3599f71c stable before/after; API source 9550ba05, not claimed to contain candidate embedded assets. Native and browser screenshots were opened and inspected. Native device width 402; narrower widths tested with Chromium/WebKit. No physical-device claim.

Raw logs, harness, geometry and screenshots: scratch/af779-evidence/. Candidate assets only; no shared checkout drafts included. Full CI and independent peer verification are separate from these focused results.
