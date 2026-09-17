import { test, expect } from './fixtures';

/**
 * AMUX-4695, the client half. The server half is pinned by Rust cells in
 * api::history; what those cannot see is whether the bar OFFERS a value, and
 * whether picking one actually reaches the server.
 *
 * The property worth guarding is the dead control: the chips are built from the
 * server's facets, so the bar can only ever offer a value that selects at least
 * one message. A hardcoded menu would show "Place" on a fleet where no message
 * has ever carried one.
 */

const COUNTS = { all: 3, human: 3, devices: { Mac: 2, iPhone: 1 } };

async function open(page: any) {
  const seen: string[] = [];
  await page.route('**/api/history?*', async (route: any) => {
    const url = new URL(route.request().url());
    seen.push(url.search);
    if (url.searchParams.has('counts')) return route.fulfill({ json: COUNTS });
    const device = url.searchParams.get('device');
    const rows = [
      { id: 70001, text: 'from the mac', type: 'user', session: 'ctx', ts: Date.now(), client_meta: { device: 'Mac' } },
      { id: 70002, text: 'from the phone', type: 'user', session: 'ctx', ts: Date.now(), client_meta: { device: 'iPhone' } },
      { id: 70003, text: 'no metadata at all', type: 'user', session: 'ctx', ts: Date.now() },
    ].filter(r => !device || (r.client_meta && r.client_meta.device === device));
    await route.fulfill({ json: rows });
  });
  await page.goto('/');
  await page.waitForFunction(() => typeof (window as any).openCmdHistoryModal === 'function');
  // OPEN THE REAL MODAL rather than just calling the fetch. A chip that renders
  // under another view's overlay is not a chip the user can tap, and the first
  // run of this test proved the difference: the button was visible, enabled and
  // stable, and `<div class="empty">` from #session-view intercepted the click.
  await page.evaluate(async () => {
    const w = window as any;
    w.openCmdHistoryModal();
    await w._cmdHistFetch();
  });
  await page.locator('#cmd-history-modal').waitFor({ state: 'visible' });
  return seen;
}

test('the context bar offers only values that exist, and picking one filters server-side', async ({ page }) => {
  const seen = await open(page);

  const chips = page.locator('#cmd-history-ctx-filter button');
  await expect(chips).toHaveCount(2);
  await expect(chips.nth(0)).toContainText('Mac');
  await expect(chips.nth(0)).toContainText('2');
  await expect(chips.nth(1)).toContainText('iPhone');

  // NO DEAD CONTROL. The server sent no `places` facet because nothing carries
  // one, so the bar must not invent a Place chip.
  const bar = await page.locator('#cmd-history-ctx-filter').innerText();
  expect(bar.toLowerCase()).not.toContain('place');

  // Picking one must reach the SERVER, not filter the loaded page. That is the
  // whole reason this filter is server-side (AMUX-4666: a client-side filter
  // over one page reports "1 message" of 207).
  seen.length = 0;
  await chips.nth(0).click();
  await expect.poll(() => seen.some(s => s.includes('device=Mac')), { timeout: 5000 }).toBe(true);

  // And tapping the active chip clears it, so the filter has an exit that does
  // not cost a second control at 375px.
  seen.length = 0;
  await page.locator('#cmd-history-ctx-filter button', { hasText: 'Mac' }).first().click();
  await expect.poll(() => seen.length > 0, { timeout: 5000 }).toBe(true);
  expect(seen.every(s => !s.includes('device=')), `cleared: ${seen.join(' | ')}`).toBe(true);
});

test('a fleet whose messages carry no context sees no filter bar at all', async ({ page }) => {
  await page.route('**/api/history?*', async (route: any) => {
    const url = new URL(route.request().url());
    if (url.searchParams.has('counts')) {
      // No `devices`, no `places`: the server omits a facet nothing has.
      return route.fulfill({ json: { all: 1, human: 1 } });
    }
    await route.fulfill({ json: [{ id: 70010, text: 'plain', type: 'user', session: 'ctx', ts: Date.now() }] });
  });
  await page.goto('/');
  await page.waitForFunction(() => typeof (window as any).openCmdHistoryModal === 'function');
  await page.evaluate(async () => {
    const w = window as any;
    w.openCmdHistoryModal();
    await w._cmdHistFetch();
  });
  await page.locator('#cmd-history-modal').waitFor({ state: 'visible' });

  await expect(page.locator('#cmd-history-ctx-filter button')).toHaveCount(0);
  // And it takes no vertical space, so the list does not shift down for a
  // control that is not there.
  const h = await page.locator('#cmd-history-ctx-filter').evaluate((n: HTMLElement) => n.getBoundingClientRect().height);
  expect(h).toBeLessThanOrEqual(1);
});
