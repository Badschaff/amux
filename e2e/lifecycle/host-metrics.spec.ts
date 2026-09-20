import { test, expect } from '../fixtures';
import { boot, checkpoint } from './evidence';

test('LC-HOST: measured host analysis, refresh and related navigation work at each viewport', async ({ page }, info) => {
  test.setTimeout(90_000);
  const diagnostics: any[] = [];
  page.on('request', request => {
    if (request.url().endsWith('/api/client-debug') && request.method() === 'POST') {
      const data = request.postDataJSON();
      if (data?.kind === 'host-analysis-contrast') diagnostics.push(data);
    }
  });
  await boot(page);
  const tab = page.locator('#tab-metrics');
  if (!await tab.isVisible()) {
    await page.locator('.tab-customize-wrap > .tab-customize-btn').click();
    await page.locator('#tab-customizer-menu [data-tab-id="metrics"] input[type="checkbox"]').check();
    await page.locator('.tab-customize-wrap > .tab-customize-btn').click();
  }
  await tab.click();
  // The phone worker list is a full-width sidebar. Follow its visible
  // collapse/expand controls before reaching the host-wide mode selector.
  const sidebar = page.locator('#metrics-sidebar');
  await sidebar.getByRole('button', { name: 'Collapse sidebar' }).click();
  await expect(sidebar).toHaveClass(/collapsed/);
  await page.getByRole('button', { name: 'Show workers list' }).click();
  await expect(sidebar).not.toHaveClass(/collapsed/);
  await sidebar.getByRole('button', { name: 'Collapse sidebar' }).click();
  await expect(sidebar).toHaveClass(/collapsed/);
  const response = page.waitForResponse(r => r.url().endsWith('/api/metrics/host'), { timeout: 60_000 });
  await page.locator('#metricsmode-host').click();
  const measured = await response;
  expect(measured.ok()).toBe(true);
  const data = await measured.json();
  expect(data.measured, 'the shipped host probe must actually run').toBe(true);
  expect(data.n_considered).toBeGreaterThan(0);
  expect(data.cpu.count).toBeGreaterThan(0);
  await expect(page.locator('#host-content')).toContainText('Host Analysis');
  await expect(page.locator('#host-content')).toContainText('Top by CPU');
  await checkpoint(page, info, 'host-analysis');
  for (const theme of ['light', 'dark']) {
    if (await page.locator('body').evaluate(el => el.classList.contains('light')) !== (theme === 'light')) {
      await page.locator('#settings-btn').click();
      await page.locator('#settings-menu .settings-tab-btn[data-stab="device"]').click();
      await page.locator('#theme-checkbox + .theme-track').click();
      await page.locator('#settings-btn').click();
      await expect(page.locator('#settings-menu')).not.toHaveClass(/open/);
    }
    const refreshed = page.waitForResponse(r => r.url().endsWith('/api/metrics/host'));
    await page.locator('#host-content').getByRole('button', { name: /Refresh/ }).click();
    expect((await refreshed).ok()).toBe(true);
    await expect(page.locator('#host-content .host-state-chip')).toHaveCount(3);
    // A refresh replaces these nodes. Resolve nodes and computed styles in one
    // browser task: locator handles can be detached before evaluateAll runs.
    const frame = await page.evaluate(() => {
      const elements = Array.from(document.querySelectorAll('#host-content .host-state-chip'));

      const luminance = (color: string) => {
        const channels = color.match(/[\d.]+/g);
        if (!channels || channels.length < 3) throw new Error(`Unmeasured host color in current DOM: ${JSON.stringify(color)}`);
        const [r, g, b] = channels.slice(0, 3).map(Number).map(v => {
          const c = v / 255;
          return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
        });
        return .2126 * r + .7152 * g + .0722 * b;
      };
      const ratios = elements.flatMap(chip => [chip, chip.querySelector('b')!].map(el => {
        const a = luminance(getComputedStyle(el).color), b = luminance(getComputedStyle(chip).backgroundColor);
        return { text: el.textContent, foreground: getComputedStyle(el).color, background: getComputedStyle(chip).backgroundColor, ratio: (Math.max(a, b) + .05) / (Math.min(a, b) + .05) };
      }));
      return { light: document.body.classList.contains('light'), chips: elements.length, ratios };
    });
    await info.attach(`host-contrast-${theme}`, { body: JSON.stringify(frame), contentType: 'application/json' });
    expect(frame.light).toBe(theme === 'light');
    expect(frame.chips).toBe(3);
    expect(frame.ratios).toHaveLength(6);
    console.info(`[host-contrast] theme=${theme} measured=true chips=${frame.chips} samples=${frame.ratios.length} source=current-dom-frame`);
    for (const sample of frame.ratios) expect(sample.ratio, `${theme}: ${sample.text} must be readable`).toBeGreaterThanOrEqual(4.5);
    await expect.poll(() => diagnostics.some(d => d.light === (theme === 'light') && d.verdict === 'readable' && d.n_considered === 6)).toBe(true);
    await checkpoint(page, info, `host-analysis-${theme}`);
  }
  await page.locator('#host-content [title="Open Disk Cleanup"]').click();
  await expect(page.locator('#reclaim-content')).toBeVisible();
  await expect(page.locator('#host-content')).toBeHidden();
  // Disk Cleanup is its own tab since 1a2963c8, so the Metrics mode bar is
  // hidden while it shows. Return through the Metrics tab first (AMUX-4634).
  await tab.click();
  await page.locator('#metricsmode-system').click();
  await expect(page.locator('#metrics-content')).toBeVisible();
  await expect(page.locator('#reclaim-content')).toBeHidden();
});
