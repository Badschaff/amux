import {test,expect,Page} from './fixtures';

test.use({viewport:{width:375,height:667},serviceWorkers:'block'});

async function openWarning(page:Page) {
  await page.addInitScript(()=>localStorage.setItem('amux_walkthrough_done','1'));
  await page.route('**/api/offline-origin',r=>r.fulfill({json:{proxied:false,good_origin:'https://amux.io'}}));
  await page.goto('/');
  await page.waitForFunction(()=>typeof (window as any).openBoardAdd==='function');
  await page.evaluate(()=>(window as any).openBoardAdd('todo'));
  await expect(page.locator('#board-edit-overlay')).toHaveClass(/active/);
  await page.evaluate(()=>(window as any)._swOfferGoodOrigin());
  await expect(page.locator('#sw-fail-bar')).toBeVisible();
}

async function measure(page:Page) {
  return page.evaluate(()=>{
    const button=document.querySelector('.be-save')!,a=button.getBoundingClientRect();
    const bar=document.querySelector('#sw-fail-bar')!,b=bar.getBoundingClientRect();
    const points=[[a.left+4,a.top+4],[a.right-4,a.top+4],[a.left+4,a.bottom-4],[a.right-4,a.bottom-4],[a.left+a.width/2,a.top+a.height/2]];
    return {measured:true,n_considered:points.length,hits:points.map(([x,y])=>button.contains(document.elementFromPoint(x,y))),
      button:a.toJSON(),warning:b.toJSON(),published:parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--sw-fail-h')),
      layout:(window as any)._modalLayoutCheck()};
  });
}

test('real offline warning resizes while Save stays fully tappable and persists the edit',async({page,request},info)=>{
  await openWarning(page);
  const title='warning-save-'+info.project.name+'-'+Date.now(),desc='Preserve this complete edit while the offline warning is visible.';
  await page.fill('#be-title',title);await page.fill('#be-desc',desc);
  const measurements=[];
  for(const size of [{width:375,height:667},{width:320,height:568},{width:402,height:350}]){
    await page.setViewportSize(size);
    let value: Awaited<ReturnType<typeof measure>>;
    // Viewport and ResizeObserver updates are asynchronous. Require the same
    // sample to prove actual dialog measurement, settled layout and all hits.
    await expect.poll(async()=>{
      value=await measure(page);
      return value.hits.every(Boolean)&&value.button.top>=0&&value.button.left>=0&&value.button.right<=size.width
        &&value.button.bottom<=value.warning.top&&Math.abs(value.published-value.warning.height)<1
        &&value.layout.measured&&value.layout.n_considered>0&&value.layout.clipped.length===0;
    }).toBe(true);
    measurements.push({size,...value!});
  }
  await page.setViewportSize({width:375,height:667});
  await expect.poll(async()=>(await measure(page)).hits.every(Boolean)).toBe(true);
  await page.screenshot({path:info.outputPath('warning-and-save.png')});
  const response=page.waitForResponse(r=>r.url().endsWith('/api/board')&&r.request().method()==='POST');
  await page.locator('.be-save').click();const created=await response;expect(created.status()).toBe(201);const card=await created.json();
  await expect(page.locator('#board-edit-overlay')).not.toHaveClass(/active/);
  const token=await page.evaluate(()=>(window as any)._AMUX_AUTH_TOKEN);
  const stored=await request.get('/api/board/'+card.id,{headers:{Authorization:'Bearer '+token}});expect(stored.ok()).toBe(true);
  expect(await stored.json()).toMatchObject({id:card.id,title,desc});
  await page.locator('#sw-fail-bar button').last().click();await expect(page.locator('#sw-fail-bar')).toHaveCount(0);
  await expect.poll(()=>page.evaluate(()=>getComputedStyle(document.documentElement).getPropertyValue('--sw-fail-h').trim())).toBe('0px');
  console.log('WARNING DIALOG',JSON.stringify({measured:true,n_considered:measurements.length,measurements,persisted:card.id}));
  await info.attach('warning-dialog-measurements',{body:JSON.stringify(measurements),contentType:'application/json'});
});

test('CONTROL: obsolete keyboard height covers a footer and emits a measured warning diagnostic',async({page},info)=>{
  await openWarning(page);
  await expect.poll(async()=>(await measure(page)).hits.every(Boolean)).toBe(true);
  const beacon=page.waitForRequest(r=>r.url().endsWith('/api/client-debug')&&r.postDataJSON()?.kind==='modal-layout-clipped'&&r.postDataJSON()?.clipped?.includes('board-edit-overlay:footer-covered-by-warning'));
  await page.addStyleTag({content:'.amux-dialog-viewport > .board-edit-box {max-height:calc(var(--dialog-viewport-height,100dvh) - 40px)!important}'});
  await page.evaluate(()=>window.dispatchEvent(new Event('resize')));
  const data=(await beacon).postDataJSON();expect(data.measured).toBe(true);expect(data.n_considered).toBeGreaterThan(0);
  const broken=await measure(page);expect(broken.hits.every(Boolean)).toBe(false);expect(broken.layout.clipped).toContain('board-edit-overlay:footer-covered-by-warning');
  await page.screenshot({path:info.outputPath('warning-covers-save-control.png')});
  await info.attach('covered-footer-diagnostic',{body:JSON.stringify({broken,data}),contentType:'application/json'});
});
