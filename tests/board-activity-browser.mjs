// Read-only browser check against a running dashboard shell. API sessions and
// board are fixtures; all writes are refused. No live worker is created.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {chromium} from 'playwright';

const root=path.resolve(import.meta.dirname,'..');
const base=process.env.AMUX_TEST_URL || 'https://localhost:8824';
const source=await fs.readFile(path.join(root,'crates/amux-dashboard/static/app.js'),'utf8');
const css=await fs.readFile(path.join(root,'crates/amux-dashboard/static/app.css'),'utf8');
function worker(name,cardId,extra={}) {
  return {name,provider:'claude',model:'claude-haiku-4-5',active_model:'claude-haiku-4-5',
    status:cardId?'active':'unattributed',running:true,lifecycle:'active',archived:false,
    tags:[],dir:'/tmp/board-activity-fixture',flags:'',desc:'Activity fixture',preview:'',
    task_name:'Fixture work',task_source:'board',task_board_id:cardId||'',
    runtime_board:{measured:true,runtime_status:'active',status:cardId?'linked':'active-card-invalid',
      verdict:cardId?'linked':'active-card-invalid',card_id:cardId,observed_card_id:cardId||'SP-787'},...extra};
}
function card(id,session,status,title) {
  return {id,session,status,title,type:'chore',owner_type:'agent',tags:[],desc:'Local UI fixture',
    depends_on:[],archived:false,created:1,updated:1,pos:0};
}
const board=[card('SP-787','studio-plg','backlog','OpenAPI submission parameters'),
  card('FX-1','linked-worker','doing','First outcome'),card('FX-2','linked-worker','doing','Second outcome'),
  ...Array.from({length:18},(_,i)=>card('WRAP-'+i,'studio-plg','backlog',
    'A long board title must wrap inside its own row when a worker has more tasks than fit on a phone screen'))];
let payload=[worker('studio-plg',null),worker('linked-worker','FX-1'),
  worker('paused-worker','FX-9',{lifecycle:'paused',running:false})];
const browser=await chromium.launch({headless:true});
try {
  for (const width of [1280,390]) {
    const context=await browser.newContext({ignoreHTTPSErrors:true,serviceWorkers:'block',viewport:{width,height:900}});
    await context.addInitScript(() => {
      localStorage.setItem('amux_walkthrough_done','1');
      window.__activityStreams=[];
      window.EventSource=class {
        static OPEN=1; static CLOSED=2; readyState=1;
        constructor(){window.__activityStreams.push(this);}
        close(){this.readyState=2;} addEventListener(){} removeEventListener(){}
      };
    });
    const page=await context.newPage();
    await page.route('**/app.js*',r=>r.fulfill({contentType:'text/javascript',body:source}));
    await page.route('**/app.css*',r=>r.fulfill({contentType:'text/css',body:css}));
    await page.route('**/api/**',r=>{
      const u=new URL(r.request().url());
      if(r.request().method()!=='GET')return r.fulfill({status:409,json:{error:'read-only UI fixture'}});
      if(u.pathname==='/api/sessions')return r.fulfill({json:payload});
      if(u.pathname==='/api/board')return r.fulfill({json:board});
      if(u.pathname==='/api/sync')return r.fulfill({json:{issues:[],sessions:payload}});
      return r.continue();
    });
    await page.goto(base+'/#view=board');
    await page.waitForFunction(()=>typeof renderBoard==='function' && sessions.length===3);
    await page.locator('#tab-board').click();
    await page.evaluate(()=>{boardViewMode='status';boardOwnerFilter='all';renderBoard();});
    await page.locator('#board-columns-activity [data-worker="studio-plg"]').waitFor();
    assert.match(await page.locator('#board-columns-activity [data-worker="studio-plg"]').innerText(),/task link missing or out of date/);
    assert.equal(await page.locator('#board-columns-activity [data-worker="paused-worker"]').count(),0);
    assert.equal(await page.locator('.board-card-live[data-id="FX-1"]').count(),1);
    assert.equal(await page.locator('.board-card-live[data-id="FX-2"]').count(),0);
    assert.equal(await page.locator('.board-card-observed[data-id="SP-787"]').count(),1);
    // Keep runtime active while moving to another exact card: the old active-set
    // signature missed this, and the SSE handler never repainted either board.
    payload=[worker('studio-plg',null),worker('linked-worker','FX-2'),payload[2]];
    await page.evaluate(data=>window.__activityStreams.find(s=>s.onmessage).onmessage({data:JSON.stringify({type:'sessions',payload:data})}),payload);
    await page.waitForFunction(()=>!!document.querySelector('.board-card-live[data-id="FX-2"]'));
    assert.equal(await page.locator('.board-card-live[data-id="FX-1"]').count(),0);
    await page.evaluate(()=>{boardSearchQuery='no-fixture-matches-this';renderBoard();});
    assert.equal(await page.locator('#board-columns .board-card').count(),0);
    assert.match(await page.locator('#board-columns-activity').innerText(),/Second outcome/);
    await page.screenshot({path:`/tmp/amux-board-activity-${width}.png`});
    // Worker detail uses the same state in both list and kanban views.
    await page.evaluate(()=>{openPeek('studio-plg');setPeekTab('issues');});
    await page.locator('#peek-issues-list-activity [data-worker="studio-plg"]').waitFor();
    assert.equal(await page.locator('#peek-issues-list-activity [data-worker="linked-worker"]').count(),0);
    await page.waitForFunction(()=>getComputedStyle(document.getElementById('peek-overlay')).opacity==='1');
    assert.equal(await page.evaluate(()=>_uiComponentCheck().issues.filter(i=>i.endsWith(':board-row-content-overflow')).length),0);
    if(width===390) {
      const broken=await page.addStyleTag({content:'.peek-issue-item {flex-shrink:1 !important;}'});
      assert.ok(await page.evaluate(()=>_uiComponentCheck().issues.some(i=>i.endsWith(':board-row-content-overflow'))),
        'diagnostic must detect the original compressed-row failure');
      await broken.evaluate(el=>el.remove());
    }
    payload=[worker('studio-plg',null,{lifecycle:'paused',running:false}),payload[1],payload[2]];
    await page.evaluate(data=>window.__activityStreams.find(s=>s.onmessage).onmessage({data:JSON.stringify({type:'sessions',payload:data})}),payload);
    await page.waitForFunction(()=>document.getElementById('peek-issues-list-activity').hidden);
    console.log(`PASS ${width}px: missing link visible, exact-card highlight, same-status SSE switch, filtered task retained, worker scope, pause clears activity, wrapped rows contained`);
    await context.close();
    payload=[worker('studio-plg',null),worker('linked-worker','FX-1'),worker('paused-worker','FX-9',{lifecycle:'paused',running:false})];
  }
} finally {await browser.close();}
