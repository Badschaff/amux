import { test, expect } from './fixtures';

test.use({ serviceWorkers: 'block' });

test('snapshot count reaches the disk view without prescribing backup deletion', async ({ page }, info) => {
  const mutations: string[] = [];
  await page.route('**/api/reclaim/**', async route => {
    const req = route.request();
    if (req.method() !== 'GET') {
      mutations.push(req.method() + ' ' + req.url());
      return route.fulfill({ status: 409, json: { error: 'this fixture permits reads only' } });
    }
    const path = new URL(req.url()).pathname;
    let body: unknown;
    if (path.endsWith('/scan/latest')) {
      body = {
        scan: { id: 'snapshot-fixture', status: 'done', snapshot_count: 24,
          df_free: 800 * 1024 ** 3, df_total: 1800 * 1024 ** 3 },
        // An old stored scan must not revive its historical bad guidance.
        findings: [{ id: 1, category: 'snapshot', bytes: 0, file_count: 24,
          detail: 'deleting files will not increase your free space; Thin them first' }],
        totals: [], skipped: [],
      };
    } else if (path.endsWith('/quarantine')) {
      body = { batches: [] };
    } else if (path.includes('/tree')) {
      body = { root: null, children: [] };
    } else {
      throw new Error('Unexpected reclaim GET: ' + path);
    }
    await route.fulfill({ json: body });
  });
  await page.goto('/');
  await page.waitForFunction(() => typeof (window as any).switchView === 'function');
  await page.evaluate(() => (window as any).switchView('disk'));
  const note = page.locator('#reclaim-content .reclaim-warn').filter({ hasText: '24' });
  await expect(note).toBeVisible();
  await expect(page.locator('#reclaim-content')).not.toContainText('thinlocalsnapshots');
  await expect(note).toContainText('24 local snapshots observed');
  await expect(note).toContainText('may retain blocks');
  await expect(note).toContainText('does not show how much space');
  await expect(page.locator('#reclaim-content')).not.toContainText('deleting files will not increase');
  const box = await note.boundingBox();
  const viewport = page.viewportSize()!;
  expect(box).not.toBeNull();
  expect(box!.x).toBeGreaterThanOrEqual(0);
  expect(box!.x + box!.width).toBeLessThanOrEqual(viewport.width + 1);
  expect(box!.y).toBeGreaterThanOrEqual(0);
  expect(box!.y + box!.height).toBeLessThanOrEqual(viewport.height + 1);
  const screenshot = info.outputPath('snapshot-context.png');
  await page.screenshot({ path: screenshot });
  await info.attach('snapshot-context', { path: screenshot, contentType: 'image/png' });
  expect(mutations).toEqual([]);
});
