import {test, expect} from './fixtures';

test('Stop persists once during an outage and clears after acknowledgement', async ({page}, testInfo) => {
  let allowStop = false;
  let running = true;
  let stopCalls = 0;
  const beacons: any[] = [];
  await page.addInitScript(() => localStorage.setItem('amux_walkthrough_done', '1'));
  await page.route(/\/api\/events(?:\?.*)?$/, route => route.fulfill({contentType:'text/event-stream', body:'data: {"type":"ping"}\n\n'}));
  await page.route(/\/api\/sessions(?:\?.*)?$/, route => route.fulfill({json:[{name:'stop-fixture', running, status:running ? 'active' : 'stopped', dir:'/tmp/stop-fixture'}]}));
  await page.route('**/api/client-debug', route => {beacons.push(route.request().postDataJSON()); return route.fulfill({json:{ok:true}});});
  await page.route('**/api/sessions/stop-fixture/stop', route => {
    stopCalls++;
    if (!allowStop) return route.fulfill({status:503, json:{error:'injected store contention'}});
    running = false;
    return route.fulfill({status:202, json:{ok:true,message:'stopping'}});
  });
  await page.goto('/');
  await page.waitForFunction(() => typeof (window as any).doStop === 'function');
  await page.evaluate(() => {
    void (window as any).doStop('stop-fixture');
    void (window as any).doStop('stop-fixture');
  });
  await expect.poll(() => stopCalls).toBeGreaterThan(0);
  const queue = () => page.evaluate(() => JSON.parse(localStorage.getItem('amux_offline_queue') || '[]'));
  await expect.poll(async () => (await queue()).length).toBe(1);
  // A second UI surface uses fetch directly, while the first intent is pending.
  await page.evaluate(async () => {await fetch('/api/sessions/stop-fixture/stop', {method:'POST'});});
  await expect.poll(async () => (await queue()).length).toBe(1);
  await expect.poll(() => beacons.some(b => b.verdict === 'stop_intent_coalesced')).toBe(true);
  await page.screenshot({path:testInfo.outputPath('stop-pending.png'),fullPage:true});
  allowStop = true;
  await page.evaluate(() => (window as any).runSyncBanner(true));
  await expect.poll(async () => (await queue()).length).toBe(0);
  await expect(page.locator('.card').filter({hasText:'stop-fixture'})).toContainText('stopped');
  await page.screenshot({path:testInfo.outputPath('stop-confirmed.png'),fullPage:true});
});
