#!/usr/bin/env node
// Actual native Safari proof on an owned simulator; fixture input never reaches the fleet.
import assert from 'node:assert/strict';
import http from 'node:http';
import https from 'node:https';
import fs from 'node:fs/promises';
const base = new URL(process.env.AMUX_IOS_TEST_URL || 'https://localhost:18854');
assert(['localhost', '127.0.0.1', '[::1]'].includes(base.hostname));
assert(Number(base.port) >= 18000 || process.env.AMUX_IOS_ALLOW_LIVE === '1',
  'Live driver requires explicit AMUX_IOS_ALLOW_LIVE=1; all page input uses a private local fixture');
const session = process.env.AMUX_SESSION || 'ios-test';
const journal = process.env.AMUX_IOS_JOURNAL;
assert(journal, 'AMUX_IOS_JOURNAL must identify this test server’s driver journal');
const run = Date.now().toString(36);
let presses = 0, started = false, device;
const results = [];
function request(url, method = 'GET', body) {
  url = new URL(url);
  return new Promise((resolve, reject) => {
    const req = (url.protocol === 'https:' ? https : http).request(url, {
      method, rejectUnauthorized: false, headers: {'content-type': 'application/json'},
    }, res => {
      const chunks = [];
      res.on('data', b => chunks.push(b));
      res.on('error', reject);
      res.on('end', () => {
        try { resolve({status: res.statusCode, data: JSON.parse(Buffer.concat(chunks))}); }
        catch (error) { reject(error); }
      });
    });
    const timer = setTimeout(() => req.destroy(new Error('Test request deadline 200s')), 200000);
    req.on('close', () => clearTimeout(timer)); req.on('error', reject);
    req.end(body === undefined ? undefined : JSON.stringify(body));
  });
}
async function api(verb, body, expected = 200) {
  const path = '/api/browser/ios/' + verb + (body === undefined ? '?session=' + encodeURIComponent(session) : '');
  const r = await request(new URL(path, base), body === undefined ? 'GET' : 'POST', body === undefined ? undefined : {...body, session});
  assert.equal(r.status, expected, JSON.stringify(r.data)); return r.data;
}
async function ownedDriver() {
  const d = JSON.parse(await fs.readFile(journal, 'utf8'));
  assert.equal(d.owner, session); assert.equal(d.udid, device); return d;
}
async function wd(d, path, method = 'GET', body) {
  const r = await request(`http://127.0.0.1:${d.port}/session/${d.id}${path}`, method, body);
  assert.equal(r.status, 200, JSON.stringify(r.data)); return r.data.value;
}
const evaluate = async script => (await api('action', {action: 'eval', script})).data.result;
async function until(script, predicate) {
  for (let i = 0; i < 30; i++) {
    const v = await evaluate(script); if (predicate(v)) return v;
    await new Promise(r => setTimeout(r, 100));
  }
  throw new Error('Fixture condition did not settle: ' + script);
}
function pass(name) { results.push(name); console.log('PASS ' + name); }
const fixture = http.createServer((req, res) => {
  if (req.url === '/press') { presses++; res.writeHead(200, {'content-type': 'application/json'}); res.end('{}'); return; }
  res.writeHead(200, {'content-type': 'text/html', 'cache-control': 'no-store'});
  res.end(`<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><title>Owned iOS test</title>
    <style>body{padding:30px;font:20px system-ui}button,input,a{font:inherit;display:block;margin:20px 0;padding:15px;min-height:44px}</style>
    <h1>Simulator recovery ${run}</h1><input id="text" aria-label="Fixture text">
    <button id="counter" onclick="fetch('/press');document.querySelector('#value').textContent=document.querySelector('#text').value">Copy fixture text</button>
    <output id="value"></output><a id="second" href="/?tab=second" target="_blank">Open second fixture tab</a>
    <script>window.fixtureRun=${JSON.stringify(run)}</script>`);
});
await new Promise(r => fixture.listen(0, '127.0.0.1', r));
const page = `http://127.0.0.1:${fixture.address().port}/?tab=first`;
const before = (await request(new URL('/health', base))).data;
try {
  const targets = await api('targets'); device = targets.targets.find(t => t.state === 'Booted')?.udid;
  assert(device, 'A booted simulator is required');
  const status = await api('status');
  assert(!status.running && !status.owned, 'Stop the previous owned audit before starting this isolated run');
  await api('start', {udid: device, url: page}); started = true;
  await until('window.fixtureRun', v => v === run);
  assert.equal(await evaluate('document.visibilityState'), 'visible');
  await api('action', {action: 'input', selector: '#text', text: 'native fixture'});
  await api('action', {action: 'click', selector: '#counter'});
  await until('document.querySelector("#value").textContent', v => v === 'native fixture');
  assert.equal(presses, 1); pass('Go aligns the visible tab; native typing and tap reach its fixture');
  await api('action', {action: 'click', selector: '#second'});
  let d = await ownedDriver();
  let hidden = false;
  for (let attempt = 0; attempt < 10 && !hidden; attempt++) {
    const contexts = await wd(d, '/execute/sync', 'POST', {script: 'mobile: getContexts', args: []});
    for (const c of contexts.filter(c => c.bundleId === 'com.apple.mobilesafari')) {
      await wd(d, '/context', 'POST', {name: c.id});
      const info = await evaluate('({fixture:window.fixtureRun,visible:document.visibilityState})');
      console.log('TAB PROBE ' + JSON.stringify({attempt, id:c.id, fixture:info.fixture===run, visible:info.visible}));
      if (info.fixture === run && info.visible === 'hidden') { hidden = true; break; }
    }
    if (!hidden) await new Promise(r => setTimeout(r, 200));
  }
  assert(hidden, 'The native link must leave a hidden fixture tab for the refusal test');
  const refusal = await api('action', {action: 'click', selector: '#counter'}, 409);
  assert.match(refusal.error, /No input was dispatched/); assert.equal(presses, 1);
  pass('Hidden debugger tab refuses native input without pressing either fixture button');
  await api('start', {udid: device, url: page});
  assert.equal(await evaluate('document.visibilityState'), 'visible');
  d = await ownedDriver();
  console.log('IDLE: leaving WebDriver untouched for 65 seconds');
  await new Promise(r => setTimeout(r, 65000));
  assert.equal((await api('status')).running, true);
  assert.equal((await ownedDriver()).id, d.id);
  pass('Owned session survives more than the previous 60-second idle expiry');
  await wd(d, '', 'DELETE');
  const recovered = await api('start', {udid: device, url: page});
  assert.equal(recovered.recovered_expired_session, true);
  assert.notEqual((await ownedDriver()).id, d.id);
  assert.equal(await evaluate('document.visibilityState'), 'visible');
  assert.equal(presses, 1, 'Recovery must not replay the previous input or button command');
  pass('Explicit Go replaces a proven dead session without Stop or input replay');
  const after = (await request(new URL('/health', base))).data;
  assert.equal(after.build, before.build, 'Server build changed during the audit');
  console.log('RESULT ' + JSON.stringify({measured: true, n_considered: results.length, commit: after.commit, build: after.build, results}));
} finally {
  if (started) await api('stop', {}).catch(e => console.error('Owned cleanup pending: ' + e.message));
  fixture.closeAllConnections(); await new Promise(r => fixture.close(r));
}
