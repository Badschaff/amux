import type { APIRequestContext } from '@playwright/test';
import { test as base } from './fixtures';

type Cleanup = { worker: string; auth: Record<string, string>; uiToken: string; card: string };

// A separate fixture teardown gets its own budget after a failed/timed-out test.
// Throwing here adds a teardown failure instead of replacing the original error
// with a finally-block assertion. Only this test's exact generated worker is held.
export const test = base.extend<{ workerCleanup: Cleanup }>({
  workerCleanup: [async ({ request }, use, testInfo) => {
    const owned: Cleanup = { worker: '', auth: {}, uiToken: '', card: '' };
    await use(owned);
    if (!owned.worker) return;
    const evidence: Record<string, unknown> = {
      kind: 'e2e-worker-cleanup', measured: true, n_considered: 1,
      worker: owned.worker, primary_errors: testInfo.errors.map(e => e.message), steps: [],
    };
    const steps = evidence.steps as unknown[];
    const errors: string[] = [];
    const record = async (label: string, operation: () => ReturnType<APIRequestContext['get']>) => {
      const response = await operation();
      steps.push({ action: label, status: response.status(), body: (await response.text()).slice(0, 2000) });
      return response;
    };
    try {
      if (!/^e2e-life-[a-z0-9-]+-\d+$/.test(owned.worker)) throw new Error('Refusing cleanup outside the generated lifecycle namespace');
      const path = `/api/sessions/${encodeURIComponent(owned.worker)}`;
      const current = await record('read-worker', () => request.get(path, { headers: owned.auth, timeout: 5000 }));
      if (current.status() !== 404) {
        if (current.status() !== 200) throw new Error(`Worker read returned HTTP ${current.status()}`);
        const deleted = await record('guarded-delete-worker', () => request.post(`${path}/delete`, {
          headers: { ...owned.auth, 'X-Amux-UI-Token': owned.uiToken }, data: {}, timeout: 10000,
        }));
        if (!deleted.ok()) throw new Error(`Guarded worker delete returned HTTP ${deleted.status()}`);
        const absent = await record('confirm-worker-absent', () => request.get(path, { headers: owned.auth, timeout: 5000 }));
        if (absent.status() !== 404) throw new Error(`Worker remains after delete: HTTP ${absent.status()}`);
      }
    } catch (error) { errors.push(String(error)); }
    if (owned.card) {
      try {
        const response = await record('delete-fixture-card', () => request.delete(`/api/board/${encodeURIComponent(owned.card)}`, {
          headers: { ...owned.auth, 'X-Amux-Worker': owned.worker }, timeout: 5000,
        }));
        if (!response.ok() && response.status() !== 404) throw new Error(`Fixture card delete returned HTTP ${response.status()}`);
      } catch (error) { errors.push(String(error)); }
    }
    Object.assign(evidence, { verdict: errors.length ? 'failed' : 'removed_or_already_absent', errors });
    console.log(JSON.stringify(evidence));
    await testInfo.attach('worker-lifecycle-cleanup', { body: JSON.stringify(evidence), contentType: 'application/json' });
    // Use the existing client-debug primitive so isolated amux server logs carry
    // the same verdict as the CI artifact. A failed beacon is visible too.
    try {
      const beacon = await request.post('/api/client-debug', { headers: owned.auth, data: evidence, timeout: 3000 });
      if (!beacon.ok()) console.warn(`e2e-worker-cleanup beacon HTTP ${beacon.status()}`);
    } catch (error) { console.warn(`e2e-worker-cleanup beacon unavailable: ${String(error)}`); }
    if (errors.length) throw new Error(`Lifecycle cleanup failed for ${owned.worker}: ${errors.join('; ')}; see worker-lifecycle-cleanup attachment`);
  }, { timeout: 30000 }],
});
