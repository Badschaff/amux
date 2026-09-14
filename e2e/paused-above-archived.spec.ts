import {test, expect} from './fixtures';

// Ethan, 2026-09-14: "put the paused accordion immediately above the archived
// accordion". Checked in the real page with the render the dashboard ships: the
// Paused footer must be the element directly before Archived in the sidebar,
// below the worker cards, and visually stacked on top of it at every width.
test('the Paused accordion renders immediately above the Archived accordion, below the worker cards', async ({page}, info) => {
  const workers = [
    {name: 'live-worker', provider: 'claude', running: true, status: 'active', lifecycle: 'active', dir: '/tmp'},
    {name: 'resting-worker', provider: 'claude', running: false, status: 'idle', lifecycle: 'paused', dir: '/tmp'},
    {name: 'old-worker', provider: 'claude', running: false, status: 'idle', lifecycle: 'archived', archived: true, dir: '/tmp'},
  ];
  await page.addInitScript(() => localStorage.setItem('amux_walkthrough_done', '1'));
  await page.route(/\/api\/sessions(?:\?.*)?$/, r => r.fulfill({json: workers}));
  await page.goto('/');
  await page.waitForFunction(() => typeof (window as any).render === 'function');
  await page.evaluate(ws => { eval('sessions=' + JSON.stringify(ws) + '; render();'); }, workers);

  const paused = page.locator('#paused-section .paused-footer');
  const archived = page.locator('#archived-section .archived-footer');
  await expect(paused).toContainText('1 paused');
  await expect(archived).toBeVisible();

  // DOM order: cards, then paused, then archived, with nothing in between.
  const order = await page.evaluate(() => {
    const p = document.getElementById('paused-section')!;
    return {
      afterCards: p.previousElementSibling?.id,
      beforeArchived: p.nextElementSibling?.id,
    };
  });
  expect(order).toEqual({afterCards: 'cards', beforeArchived: 'archived-section'});

  // Visual order: Paused sits above Archived and below the live worker card.
  const pb = await paused.boundingBox();
  const ab = await archived.boundingBox();
  const card = await page.locator('#cards').boundingBox();
  expect(pb && ab && card).toBeTruthy();
  expect(pb!.y + pb!.height).toBeLessThanOrEqual(ab!.y);
  expect(card!.y).toBeLessThan(pb!.y);
  // Nothing wider than the viewport on a phone.
  const vw = page.viewportSize()!.width;
  expect(pb!.x + pb!.width).toBeLessThanOrEqual(vw + 1);

  await page.screenshot({path: info.outputPath('paused-above-archived.png'), fullPage: true});
});
