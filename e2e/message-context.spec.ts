import { test, expect } from './fixtures';

/**
 * AMUX-4694: a message's context, inline and on tap.
 *
 * The property that matters most is the NEGATIVE one. 11,526 of the 11,591
 * stored messages carry no metadata, and every client that sends none adds
 * more, so "no chip" is the default rendering rather than an edge case. A
 * placeholder would therefore be what almost every row shows. `no_meta` below
 * is the cell that would go red if anyone added one.
 */

const WITH_META = {
  id: 91001, text: 'sent from a phone', type: 'user', session: 'ctx-fixture',
  ts: Date.UTC(2026, 8, 16, 22, 34, 3),
  client_meta: {
    device: 'iPhone', platform: 'iPhone', app_ver: '0.9.971',
    tz: 'America/New_York', tz_offset_min: -240,
    local_time: '9/16/2026, 6:34:03 PM',
  },
};
const NO_META = {
  id: 91002, text: 'a message from before the capture shipped', type: 'user',
  session: 'ctx-fixture', ts: Date.UTC(2026, 8, 16, 22, 35, 0),
};

async function renderSurfaces(page: any, rows: any[]) {
  await page.route('**/api/history?*', async (route: any) => {
    const url = new URL(route.request().url());
    await route.fulfill({ json: url.searchParams.has('counts') ? { all: rows.length, human: rows.length } : rows });
  });
  await page.goto('/');
  await page.waitForFunction(() => typeof (window as any)._cmdHistItemHTML === 'function');
  return page.evaluate(async () => {
    const w = window as any;
    const scoped = await w._peekMsgFetch({ level: 'worker', name: 'ctx-fixture' });
    // Both Messages tabs the card names, plus peek, since one renderer feeds
    // all three and a chip wired into only one of them is the bug this shape
    // of test exists to catch.
    const ctxs: Record<string, any> = {
      messages: w._msgCtxMessages(), history: w._msgCtxHistory(), peek: w._msgCtxPeek(),
    };
    const out: Record<string, Record<string, string>> = {};
    for (const [name, ctx] of Object.entries(ctxs)) {
      out[name] = {};
      for (const r of scoped) out[name][String(r.id)] = w._cmdHistItemHTML(r, ctx);
    }
    return out;
  });
}

test('the context chip renders on every message surface, and absence renders nothing', async ({ page }) => {
  const surfaces = await renderSurfaces(page, [WITH_META, NO_META]);

  for (const [name, byId] of Object.entries(surfaces)) {
    const withMeta = byId['91001'];
    const noMeta = byId['91002'];

    expect(withMeta, `${name}: a message WITH metadata must carry the chip`).toContain('msg-ctx-chip');
    expect(withMeta, `${name}: the chip shows the device`).toContain('iPhone');

    // THE CELL THAT GUARDS THE RULE. An absence is not a value.
    expect(noMeta, `${name}: a message with no metadata must render NO chip`).not.toContain('msg-ctx-chip');
    expect(noMeta.toLowerCase(), `${name}: and no placeholder word either`).not.toContain('unknown');

    // DEVICE OR PLACE, NOT BOTH: exactly one chip per row, never two.
    expect((withMeta.match(/msg-ctx-chip/g) || []).length,
      `${name}: one context chip per row`).toBe(1);
  }
});

test('tapping the chip opens the full block with both clocks, and it fits at 375px', async ({ page }) => {
  await renderSurfaces(page, [WITH_META, NO_META]);

  await page.evaluate((row) => {
    const w = window as any;
    const host = document.createElement('div');
    host.id = 'ctx-probe';
    host.innerHTML = w._cmdHistItemHTML(row, w._msgCtxMessages());
    document.body.appendChild(host);
  }, WITH_META);

  const chip = page.locator('#ctx-probe .msg-ctx-chip');
  await expect(chip).toHaveCount(1);
  await chip.click();

  const box = page.locator('.msg-ctx-overlay .msg-ctx-box');
  await expect(box).toBeVisible();

  const text = (await box.innerText()).replace(/\s+/g, ' ');
  expect(text).toContain('iPhone');          // device
  expect(text).toContain('0.9.971');         // app version
  expect(text).toContain('America/New_York');// timezone
  // The sender's local time BESIDE the server time is the point of carrying a
  // timezone: they differ exactly when the sender was somewhere else.
  expect(text).toContain('sender');
  expect(text).toContain('server');
  expect(text).toContain('6:34:03');         // the sender's own clock, not the server's

  // 375px is the width the card names as decisive.
  const vw = page.viewportSize()!.width;
  const b = (await box.boundingBox())!;
  expect(b.width, 'the block must not overflow the viewport').toBeLessThanOrEqual(vw);
  expect(b.x, 'and must not start off-screen').toBeGreaterThanOrEqual(0);

  const c = (await chip.boundingBox())!;
  expect(c.width, 'the inline chip stays small enough to sit beside the time').toBeLessThan(vw / 2);
});
