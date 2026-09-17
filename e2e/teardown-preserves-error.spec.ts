import { test, expect } from './fixtures';
import { cleanup } from './teardown';

/**
 * AMUX-4737: a failing teardown must not replace the test's own error.
 *
 * The card asks for "a spec that deliberately fails mid-body with a teardown
 * that also fails must report the BODY's error", and says such a cell would
 * have failed against the tree as it stood on 2026-09-15.
 *
 * Driven as plain throw/catch rather than by making a real spec fail, because a
 * cell that must FAIL to pass cannot live in a suite: the runner would report it
 * as a failure, and marking it expected-to-fail would hide the day it starts
 * failing for the wrong reason. The mechanism under test is
 * language-level, so exercising it directly is not a paraphrase.
 */

const REAL = 'THE REAL ERROR, from the body';
const TEARDOWN = 'the teardown also failed';

test('a throwing teardown does not replace the body error', async ({}, testInfo) => {
  let seen: string | undefined;
  try {
    try {
      throw new Error(REAL);
    } finally {
      await cleanup('deliberately broken', async () => { throw new Error(TEARDOWN); }, testInfo);
    }
  } catch (e) {
    seen = (e as Error).message;
  }

  expect(seen, 'the body error must be what escapes').toBe(REAL);

  // The teardown failure is RECORDED, not swallowed. A cleanup problem that
  // vanishes entirely is the opposite mistake, and just as hard to chase.
  const noted = testInfo.annotations.filter(a => a.type === 'teardown-failed');
  expect(noted.length, 'the teardown failure is annotated').toBe(1);
  expect(noted[0].description).toContain(TEARDOWN);
});

test('THE CONTROL: a raw finally really does discard the body error', async () => {
  // Without `cleanup`, the exact shape in the tree on 2026-09-15. If this ever
  // stops holding, the cell above is passing for a reason other than the one it
  // claims, and the whole card was about a mechanism that does not exist.
  let seen: string | undefined;
  try {
    try {
      throw new Error(REAL);
    } finally {
      throw new Error(TEARDOWN);
    }
  } catch (e) {
    seen = (e as Error).message;
  }
  expect(seen, 'a raw throwing finally wins over the body error').toBe(TEARDOWN);
});

test('cleanup lets a successful teardown run normally', async ({}, testInfo) => {
  // A guard that only ever swallows would also pass the cells above while
  // breaking every teardown in the suite.
  let ran = false;
  await cleanup('healthy', async () => { ran = true; }, testInfo);
  expect(ran, 'the teardown body actually executed').toBe(true);
  expect(testInfo.annotations.filter(a => a.type === 'teardown-failed').length,
    'a teardown that worked annotates nothing').toBe(0);
});
