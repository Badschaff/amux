import type { TestInfo } from '@playwright/test';

/**
 * Run cleanup that must NEVER replace the test's own error (AMUX-4737).
 *
 * In JavaScript a `finally` block that throws DISCARDS the exception
 * propagating out of `try`. So when a spec fails mid-body and leaves the UI or
 * the context in a state its teardown cannot handle, the TEARDOWN'S throw
 * becomes the reported error and the real one is gone: not logged, not
 * attached, not recoverable from the trace's error summary.
 *
 * MEASURED COST, 2026-09-16. Two cards sat for two days titled with their
 * teardown's secondary failure and neither named the step that actually broke:
 *
 *   AMUX-4642  "Back click times out"      really linked-record.spec.ts:78
 *   AMUX-4643  "request context closed"    really files-upload.spec.ts:35
 *
 * Both were the same dialog bug. Three wrong diagnoses were produced before the
 * teardown was made non-throwing, at which point the real error appeared
 * immediately. The mask is expensive precisely because it is plausible: "request
 * context closed" reads like a real defect and sends a reader looking for one.
 *
 * THIS IS THE FIXTURE'S OWN RULE, GENERALISED. e2e/fixtures.ts already says it,
 * and does it, for its route assertions:
 *
 *   // THE REAL ERROR WINS. A dead stub after an earlier error is downstream.
 *   if (testInfo.errors.length) return;
 *
 * A teardown failure after a body failure is downstream in exactly the same
 * way. What was missing is a way to say that in a spec's `finally`, where there
 * is no fixture to hold the rule.
 *
 * NOTHING IS SWALLOWED SILENTLY. A teardown failure is recorded as an
 * annotation when a TestInfo is available and always written to stderr, so a
 * genuine cleanup problem is still visible. It just stops outranking the thing
 * the test was actually measuring.
 */
export async function cleanup(
  label: string,
  fn: () => unknown | Promise<unknown>,
  testInfo?: TestInfo,
): Promise<void> {
  try {
    await fn();
  } catch (e) {
    const why = e instanceof Error ? (e.message || String(e)) : String(e);
    // One line, first line only. A teardown stack after a real failure is
    // noise competing with the error that matters.
    const first = why.split('\n')[0];
    const msg = `teardown "${label}" failed and was NOT allowed to replace the test error: ${first}`;
    try {
      testInfo?.annotations.push({ type: 'teardown-failed', description: msg });
    } catch {
      // An annotation push can itself fail once the runner has moved on. That
      // must not resurrect the exact failure mode this function exists to stop.
    }
    // eslint-disable-next-line no-console
    console.warn(msg);
  }
}
