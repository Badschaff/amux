import { test, expect, type Page } from './fixtures';

const worker = 'terminal-recovery';

async function boot(page: Page) {
  let frame = 'Initial terminal output';
  let requests = 0;
  const beacons: any[] = [];
  await page.addInitScript(() => localStorage.setItem('amux_walkthrough_done', '1'));
  // These cells exercise terminal polling, not server-version adoption. A
  // candidate app.js on a pinned API binary must not reload at its older v ping
  // halfway through the 15s body deadline and erase the fault specimen.
  await page.route(/\/api\/events(?:\?.*)?$/, route => route.fulfill({
    contentType:'text/event-stream', body:'data: {"type":"ping"}\n\n',
  }));
  await page.route(/\/api\/sessions(?:\?.*)?$/, route => route.fulfill({json:[{
    name: worker, running: true, status: 'active', dir: '/tmp/terminal-recovery',
  }]}));
  await page.route(`**/api/sessions/${worker}/subagents`, route => route.fulfill({json:{session:worker,subagents:[]}}));
  await page.route('**/api/client-debug', route => {
    beacons.push(route.request().postDataJSON());
    return route.fulfill({json:{ok:true}});
  });
  await page.route(`**/api/sessions/${worker}/peek?*`, route => {
    requests++;
    const etag = '"' + frame + '"';
    // WebKit's route.fulfill rejects 304. Carry the conditional response over
    // its transport as 200 and restore the exact status at the fetch boundary.
    if (route.request().headers()['if-none-match'] === etag) return route.fulfill({headers:{'X-Test-Not-Modified':'1'},body:''});
    return route.fulfill({headers:{ETag:etag},json:{name:worker,live:frame,output:frame}});
  });
  await page.goto('/');
  await page.waitForFunction(() => typeof (window as any).openPeek === 'function');
  await page.evaluate(name => (window as any).openPeek(name), worker);
  await expect(page.locator('#peek-body')).toContainText(frame);
  await expect.poll(() => requests).toBeGreaterThanOrEqual(2);
  await page.evaluate(() => {
    const original = window.fetch.bind(window);
    window.fetch = async (input, init) => {
      const response = await original(input, init);
      return response.headers.has('X-Test-Not-Modified') ? new Response(null, {status:304}) : response;
    };
  });
  return { setFrame(value: string) { frame = value; }, beacons };
}

test('a response body that stalls after headers times out and polling recovers without refresh', async ({page}) => {
  test.setTimeout(35000);
  const state = await boot(page);
  await page.evaluate(() => {
    const original = window.fetch.bind(window);
    let armed = true;
    (window as any).__bodyStalled = false;
    (window as any).__bodyAborted = false;
    // Model the transport boundary: fetch resolves at headers; the body stays
    // open until the request's real AbortSignal cancels it. No app timer is mocked.
    window.fetch = async (input, init) => {
      if (armed && String(input).includes('/peek?')) {
        armed = false;
        (window as any).__bodyStalled = true;
        const stream = new ReadableStream({start(controller) {
          controller.enqueue(new TextEncoder().encode('{"name":'));
          init!.signal!.addEventListener('abort', () => {
            (window as any).__bodyAborted = true;
            controller.error(new DOMException('Request aborted', 'AbortError'));
          }, {once:true});
        }});
        return new Response(stream, {headers:{'Content-Type':'application/json',ETag:'"Recovered terminal output"'}});
      }
      return original(input, init);
    };
  });
  await page.waitForFunction(() => (window as any).__bodyStalled);
  state.setFrame('Recovered terminal output');
  await expect.poll(() => page.evaluate(() => (window as any).__bodyAborted), {timeout:19000}).toBe(true);
  await expect(page.locator('#peek-body')).toContainText('Recovered terminal output', {timeout:6000});
  await expect.poll(() => state.beacons.some(b => b.kind === 'peek-poll' && b.action === 'refresh-failed' && b.phase === 'body')).toBe(true);
});

test('selection outside the terminal cannot freeze its updates', async ({page}) => {
  const state = await boot(page);
  await page.locator('#peek-title').evaluate(el => {
    const range = document.createRange(); range.selectNodeContents(el);
    const selection = window.getSelection()!; selection.removeAllRanges(); selection.addRange(range);
  });
  state.setFrame('Output while worker title is selected');
  await expect(page.locator('#peek-body')).toContainText('Output while worker title is selected', {timeout:6000});
});

test('a cancelled touch cannot leave the terminal selection latch stuck', async ({page}) => {
  const state = await boot(page);
  await page.locator('#peek-body').dispatchEvent('touchstart');
  await page.locator('#peek-body').dispatchEvent('touchcancel');
  state.setFrame('Output after cancelled touch');
  await expect(page.locator('#peek-body')).toContainText('Output after cancelled touch', {timeout:6000});
  await expect.poll(() => state.beacons.some(b => b.action === 'selection-recovered' && b.reason === 'touchcancel')).toBe(true);
});

test('a selection begun during a response does not consume a frame that was never painted', async ({page}) => {
  const state = await boot(page);
  await page.evaluate(() => {
    const original = window.fetch.bind(window);
    let armed = true;
    window.fetch = async (input, init) => {
      const response = await original(input, init);
      if (armed && String(input).includes('/peek?') && response.status === 200) {
        armed = false;
        const json = response.json.bind(response);
        response.json = async () => {
          const data = await json();
          const el = document.getElementById('pk-live')!;
          const range = document.createRange(); range.selectNodeContents(el);
          const selection = window.getSelection()!; selection.removeAllRanges(); selection.addRange(range);
          (window as any).__selectedDuringFrame = true;
          return data;
        };
      }
      return response;
    };
  });
  state.setFrame('Frame that arrived during selection');
  await page.waitForFunction(() => (window as any).__selectedDuringFrame);
  // Preserve the reader's selected text until they explicitly clear it.
  await expect(page.locator('#peek-body')).toContainText('Initial terminal output');
  await page.evaluate(() => {window.getSelection()!.removeAllRanges(); document.dispatchEvent(new Event('selectionchange'));});
  await expect(page.locator('#peek-body')).toContainText('Frame that arrived during selection', {timeout:6000});
});
