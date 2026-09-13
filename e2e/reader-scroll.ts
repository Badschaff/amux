import { expect, type Page } from './fixtures';

// Browser contract probe, not a native swipe claim. Playwright mobile WebKit
// has no mouse.wheel; native Simulator journeys separately exercise swipes.
export async function readEarlier(page: Page, touch: boolean) {
  const body = page.locator('#peek-body');
  const before = await body.evaluate(el => el.scrollTop);
  if (touch) {
    // A trusted tap on padding supplies reader intent, then position the specimen.
    await body.tap({ position: { x: 5, y: 5 } });
    await body.evaluate(el => { el.scrollTop -= 400; });
  } else {
    await body.hover();
    await page.mouse.wheel(0, -400);
  }
  await expect.poll(() => body.evaluate(el => el.scrollTop)).toBeLessThan(before - 10);
  // scrollTop changes before WebKit dispatches scroll. Delivering a delayed
  // response before that listener runs tests a different ordering.
  await expect.poll(() => page.evaluate('!_peekFollowBottom && _peekScrollLocked')).toBe(true);
  console.log(JSON.stringify({ event: 'e2e_reader_scroll', measured: true, n_considered: 1,
    method: touch ? 'trusted_tap_then_position' : 'wheel', native_swipe: false,
    before, after: await body.evaluate(el => el.scrollTop) }));
}
