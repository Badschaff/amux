import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import http from 'node:http';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const cli = require.resolve('@playwright/test/cli');
const fixture = fileURLToPath(new URL('../e2e/worker-lifecycle-fixture.ts', import.meta.url));

// Run the actual Playwright teardown scheduler against an HTTP fault fixture.
// No browser/provider/fleet process is started. The full lifecycle spec owns
// real amux authorization; these controls prove primary/teardown error retention.
async function run(t, { primary = true, allowed = true, absent = false, timeout = false } = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'amux-cleanup-control-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const worker = 'e2e-life-sonnet-control-1001';
  const foreign = 'e2e-life-sonnet-control-1002';
  const workers = new Set([foreign]);
  const requests = [], beacons = [];
  const server = http.createServer(async (req, res) => {
    const chunks = []; for await (const chunk of req) chunks.push(chunk);
    const body = Buffer.concat(chunks).toString();
    requests.push({ method: req.method, path: req.url });
    let status = 200, result = { ok: true };
    if (req.method === 'POST' && req.url === '/api/sessions') {
      workers.add(JSON.parse(body).name);
    } else if (req.method === 'POST' && req.url === '/api/client-debug') {
      beacons.push(JSON.parse(body));
    } else {
      const match = req.url.match(/^\/api\/sessions\/([^/]+)(\/delete)?$/);
      if (!match) status = 404;
      else if (req.method === 'GET') {
        status = workers.has(match[1]) ? 200 : 404; result = { name: match[1] };
      } else if (req.method === 'POST' && match[2] && req.headers['x-amux-ui-token'] === 'fixture-ui') {
        workers.delete(match[1]);
      } else { status = 403; result = { error: 'dashboard UI token required' }; }
    }
    res.writeHead(status, { 'content-type': 'application/json' }); res.end(JSON.stringify(result));
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  const resultPath = path.join(dir, 'result.json');
  fs.writeFileSync(path.join(dir, 'playwright.config.mjs'), `export default ${JSON.stringify({
    testDir: dir, outputDir: path.join(dir, 'test-results'), testMatch: 'control.spec.ts', workers: 1, retries: 0, timeout: 3000,
    reporter: [['json', { outputFile: resultPath }]],
    use: { baseURL: `http://127.0.0.1:${server.address().port}` },
  })};`);
  fs.writeFileSync(path.join(dir, 'control.spec.ts'), `
import { test } from ${JSON.stringify(fixture)};
test('primary and teardown control', async ({ request, workerCleanup }) => {
  Object.assign(workerCleanup, {worker:${JSON.stringify(worker)},auth:{Authorization:'Bearer non-secret-test'},uiToken:${JSON.stringify(allowed ? 'fixture-ui' : 'refused-ui')}});
  ${absent ? '' : `await request.post('/api/sessions', {data:{name:${JSON.stringify(worker)}}});`}
  ${timeout ? "await new Promise(() => {});" : primary ? "throw new Error('ORIGINAL_MID_FLOW_FAILURE');" : ''}
});`);
  const output = await new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [cli, 'test', '-c', path.join(dir, 'playwright.config.mjs')], {
      cwd: dir, env: { ...process.env, FORCE_COLOR: '0' }, stdio: ['ignore', 'pipe', 'pipe'],
    });
    let text = ''; child.stdout.on('data', b => text += b); child.stderr.on('data', b => text += b);
    const timer = setTimeout(() => child.kill('SIGKILL'), 25000);
    child.on('error', reject); child.on('close', code => { clearTimeout(timer); resolve({ code, text }); });
  });
  assert.ok(fs.existsSync(resultPath), output.text);
  const report = JSON.parse(fs.readFileSync(resultPath, 'utf8'));
  assert.equal(report.config.projects[0].outputDir, path.join(dir, 'test-results'));
  const result = report.suites[0]?.specs[0]?.tests[0]?.results[0];
  assert.ok(result, JSON.stringify(report));
  assert.ok(workers.has(foreign), 'cleanup must preserve the other worker');
  assert.ok(requests.every(r => !r.path.includes(foreign)), 'cleanup must never touch the other identity');
  assert.equal(beacons.length, 1, output.text);
  assert.equal(beacons[0].measured, true); assert.equal(beacons[0].n_considered, 1);
  return { ...output, worker, workers, requests, evidence: beacons[0], errors: result.errors.map(e => e.message).join('\n') };
}

test('mid-flow failure remains the only error after guarded fixture removal', async t => {
  const r = await run(t);
  assert.equal(r.code, 1); assert.match(r.errors, /ORIGINAL_MID_FLOW_FAILURE/);
  assert.doesNotMatch(r.errors, /Lifecycle cleanup failed/); assert.equal(r.workers.has(r.worker), false);
  assert.equal(r.evidence.verdict, 'removed_or_already_absent');
  assert.ok(r.requests.some(x => x.method === 'POST' && x.path === `/api/sessions/${r.worker}/delete`));
});
test('cleanup refusal preserves both the primary error and exact HTTP diagnostic', async t => {
  const r = await run(t, { allowed: false });
  assert.equal(r.code, 1); assert.match(r.errors, /ORIGINAL_MID_FLOW_FAILURE/);
  assert.match(r.errors, /Lifecycle cleanup failed.*HTTP 403/); assert.equal(r.workers.has(r.worker), true);
  assert.equal(r.evidence.verdict, 'failed');
  assert.ok(r.evidence.steps.some(x => x.status === 403 && x.body.includes('dashboard UI token required')));
});
test('cleanup refusal alone fails an otherwise successful test', async t => {
  const r = await run(t, { primary: false, allowed: false });
  assert.equal(r.code, 1); assert.match(r.errors, /Lifecycle cleanup failed.*HTTP 403/);
  assert.doesNotMatch(r.errors, /ORIGINAL_MID_FLOW_FAILURE/);
});
test('already absent fixture is measured without issuing an unnecessary delete', async t => {
  const r = await run(t, { primary: false, absent: true });
  assert.equal(r.code, 0, r.errors); assert.equal(r.evidence.verdict, 'removed_or_already_absent');
  assert.equal(r.requests.filter(x => x.path.endsWith('/delete')).length, 0);
});

test('timed-out test retains its timeout while separate teardown removes the fixture', async t => {
  const r = await run(t, { timeout: true });
  assert.equal(r.code, 1); assert.match(r.errors, /timeout of 3000ms exceeded/);
  assert.doesNotMatch(r.errors, /Lifecycle cleanup failed/);
  assert.equal(r.workers.has(r.worker), false); assert.equal(r.evidence.verdict, 'removed_or_already_absent');
});
