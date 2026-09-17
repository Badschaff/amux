import {test, expect} from './fixtures';

// Ethan, 2026-09-16, with a screenshot of the peek Board tab on a phone:
// "I should be able to scroll this down. It should not be fixed."
//
// The worker-activity banner ("Working · task link missing or out of date")
// was pinned above the board. `_renderBoardActivity` inserts the strip as a
// SIBLING BEFORE its host, and on this panel the host `#peek-issues-list` is the
// element carrying `overflow-y: auto`, so the strip landed in the non-scrolling
// flex parent and held fixed vertical space on a 375px screen.
//
// Asserted as MOVEMENT rather than as a CSS property: the requirement is that
// the thing scrolls away, and `position` alone would pass for a banner that is
// still stuck for some other reason (a parent that does not scroll, a height
// that leaves nothing to scroll).
test('the worker activity banner scrolls away with the board instead of staying pinned', async ({page}) => {
  await page.addInitScript(() => localStorage.setItem('amux_walkthrough_done', '1'));
  // A RUNNING worker whose runtime truth is active with an UNLINKED card is
  // exactly the state that renders the banner in the screenshot.
  await page.route(/\/api\/sessions(?:\?.*)?$/, r => r.fulfill({json: [{
    name: 'scrolltest', running: true, status: 'active', dir: '/tmp',
    runtime_board: {measured: true, runtime_status: 'active', observed_card_id: 'SCROLL-1', status: 'unlinked'},
  }]}));
  await page.route(/\/api\/sessions\/scrolltest\/peek\?/, r =>
    r.fulfill({json: {name: 'scrolltest', live: 'working', history: ''}}));
  await page.route('**/api/sessions/scrolltest/subagents', r =>
    r.fulfill({json: {session: 'scrolltest', subagents: []}}));
  // Enough cards that the list is genuinely taller than a phone screen; with
  // nothing to scroll the assertion below would pass vacuously.
  await page.route(/\/api\/board(?:\?.*)?$/, r => r.fulfill({json:
    Array.from({length: 40}, (_, i) => ({
      id: `SCROLL-${i + 1}`, title: `Scrollable card ${i + 1} with a long enough title to wrap`,
      status: 'backlog', session: 'scrolltest', type: 'chore', created: 1, updated: 1,
    }))}));

  await page.goto('/');
  await page.evaluate(() => (window as any).openPeek('scrolltest'));
  await page.locator('#peek-tab-issues').click();
  const banner = page.locator('#peek-issues-list-activity');
  await expect(banner).toBeVisible();

  const panel = page.locator('#peek-issues-panel');
  const before = (await banner.boundingBox())!.y;
  // PRECONDITION: there is something to scroll. Without this the test passes on
  // a board short enough that nothing moves, which is the vacuous green.
  const scrollable = await panel.evaluate(el => el.scrollHeight - el.clientHeight);
  expect(scrollable, 'the panel must have overflow for this test to mean anything').toBeGreaterThan(50);

  await panel.evaluate(el => { el.scrollTop = el.scrollHeight; });
  await expect.poll(async () => (await banner.boundingBox())?.y ?? before).not.toBe(before);
  const after = (await banner.boundingBox())!.y;
  expect(after, `banner stayed at y=${before} after scrolling; it is pinned`).toBeLessThan(before);
});
