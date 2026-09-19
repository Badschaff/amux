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

  // DOM order: cards, then paused, then archived, with nothing VISIBLE in
  // between.
  //
  // "Nothing visible" rather than "nextElementSibling is archived-section"
  // (AMUX-4869). a2dbd758 added `#expired-section` between them, and
  // `_renderExpiredSection` writes `el.innerHTML = ''` when there are no
  // ephemeral workers to show, which is this fixture. So the requirement Ethan
  // stated is still met on screen while the adjacency check was red, and a
  // guard that fails on an empty structural sibling fails on the refactor
  // rather than on the regression.
  //
  // This is STRICTER than the old check where it matters: if the expired
  // accordion ever renders content here, paused is genuinely no longer
  // immediately above archived, and the walk below says so by name.
  const order = await page.evaluate(() => {
    const p = document.getElementById('paused-section')!;
    const between: string[] = [];
    for (let n = p.nextElementSibling; n && n.id !== 'archived-section'; n = n.nextElementSibling) {
      const el = n as HTMLElement;
      // An element that occupies no space is not between them to a reader.
      if (el.offsetHeight > 0 || (el.textContent || '').trim()) between.push(el.id || el.className);
    }
    return {
      afterCards: p.previousElementSibling?.id,
      archivedFollows: !!p.parentElement?.querySelector('#archived-section'),
      visibleBetween: between,
    };
  });
  expect(order).toEqual({afterCards: 'cards', archivedFollows: true, visibleBetween: []});

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
