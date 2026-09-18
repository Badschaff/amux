import { type Locator } from '@playwright/test';
import { expect, type Page } from './fixtures';

// A synthetic one-finger drag by (dx, dy) from the middle of `target`.
// Plain Events carrying a `touches` array, because WebKit refuses
// `new Touch()` ("Illegal constructor") and Playwright WebKit has no CDP to
// inject trusted touches through. The dashboard reads touches[0].clientX/Y
// and touches.length, which this supplies. Positive dy is a finger moving
// DOWN the screen, the gesture that drags earlier output into view.
export async function touchDrag(target: Locator, dx: number, dy: number) {
  await target.evaluate((el, [mx, my]) => {
    const r = el.getBoundingClientRect();
    const x0 = r.left + r.width / 2, y0 = r.top + r.height / 2;
    const fire = (type: string, x: number, y: number) => {
      const ev = new Event(type, { bubbles: true, cancelable: true });
      const points = type === 'touchend' ? [] : [{ identifier: 1, target: el, clientX: x, clientY: y }];
      Object.defineProperty(ev, 'touches', { value: points });
      Object.defineProperty(ev, 'changedTouches', { value: [{ identifier: 1, target: el, clientX: x, clientY: y }] });
      el.dispatchEvent(ev);
    };
    fire('touchstart', x0, y0);
    for (let i = 1; i <= 4; i++) fire('touchmove', x0 + mx * i / 4, y0 + my * i / 4);
    fire('touchend', x0 + mx, y0 + my);
  }, [dx, dy]);
}

// Browser contract probe, not a native swipe claim. Playwright mobile WebKit
// has no mouse.wheel; native Simulator journeys separately exercise swipes.
export async function readEarlier(page: Page, touch: boolean) {
  const body = page.locator('#peek-body');
  const before = await body.evaluate(el => el.scrollTop);
  if (touch) {
    // Reader intent on touch is a finger travelling DOWN the screen, which is
    // what drags earlier output into view. This used to be a tap, and a tap
    // only worked because its compat mousedown stopped following on its own,
    // so a plain tap in the terminal parked a real reader too (AMUX-4802).
    // Dispatch the drag's events, then position the specimen.
    await touchDrag(body, 0, 40);
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
    method: touch ? 'synthetic_downward_drag_then_position' : 'wheel', native_swipe: false,
    before, after: await body.evaluate(el => el.scrollTop) }));
}
