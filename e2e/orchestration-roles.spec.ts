import {test, expect, allowUnusedRoute} from './fixtures';

const workspace={name:'workspace',dir:'/tmp/project',running:true,status:'idle',lifecycle:'active'};
const result={ok:true,epic:'E-1',orchestrator:{name:'coordinator',started:true,profile:{provider:'codex',model:'gpt-5'}},workers_started:2,workers_failed:0,failed:[],children:[]};

test.beforeEach(async ({page})=>{
  await page.addInitScript(()=>localStorage.setItem('amux_walkthrough_done','1'));
  // Browser fixtures may use the installed server shell. No mutating request
  // reaches it; the launch route below is an explicit request/response fixture.
  await page.route('**/api/**',r=>r.request().method()==='GET'?r.fallback():r.fulfill({status:409,json:{error:'read-only browser fixture'}}));
  allowUnusedRoute(page,'**/api/**'); // Other routes may handle every request.
});

test('independent profiles survive a failed launch and reload with an exact retry',async ({page})=>{
  await page.route('**/api/sessions',r=>r.fulfill({json:[workspace,{...workspace,name:'paused',lifecycle:'paused',running:false},{...workspace,name:'child',ephemeral:true}]}));
  // Unavailable discovery must preserve explicit model selection, not silently
  // replace either role with the other provider's defaults.
  await page.route('**/api/models',r=>r.fulfill({status:503,json:{error:'catalog unavailable'}}));
  const requests:any[]=[];
  await page.route('**/api/board/launch',async r=>{
    requests.push(r.request().postDataJSON());
    if(requests.length===1) await r.fulfill({status:201,json:{...result,orchestrator:{...result.orchestrator,started:false,error:'Provider failed to start'},workers_started:1,workers_failed:1,failed:[{name:'second',error:'Launch interrupted'}]}});
    else await r.fulfill({status:201,json:result});
  });
  await page.goto('/');
  await page.locator('#tab-board').click();
  await page.locator('.launch-header').click();
  await page.locator('#launch-session').selectOption('workspace');
  await expect(page.locator('#launch-session option[value="paused"]')).toHaveCount(0);
  await expect(page.locator('#launch-session option[value="child"]')).toHaveCount(0);
  await page.locator('#launch-input').fill('1. Repair the parser\n2. Verify the rendered output');
  await page.locator('#launch-orchestrator-provider').selectOption('codex');
  await page.locator('#launch-orchestrator-model').fill('gpt-5');
  await page.locator('#launch-worker-model').fill('haiku');
  await page.locator('#launch-overrides summary').click();
  await page.locator('#launch-override-model-1').fill('sonnet');
  await page.locator('#launch-override-provider-1').selectOption('gemini');
  await expect(page.locator('#launch-override-model-1')).toHaveValue('');
  await page.locator('#launch-override-model-1').fill('gemini-2.5-flash');
  await page.locator('#launch-btn').scrollIntoViewIfNeeded();
  await page.screenshot({path:test.info().outputPath('launch-role-profiles.png'),fullPage:true});
  const overflow=await page.evaluate(()=>document.documentElement.scrollWidth-innerWidth);
  expect(overflow).toBeLessThanOrEqual(1);
  await page.locator('#launch-btn').click();
  await expect(page.locator('#launch-status')).toContainText('Provider failed to start');
  await expect(page.locator('#launch-btn')).toHaveText('Retry launch');
  await expect(page.locator('#launch-input')).toHaveValue('1. Repair the parser\n2. Verify the rendered output');
  await expect(page.locator('#launch-input')).toBeDisabled();
  expect(requests[0].orchestrator).toEqual({provider:'codex',model:'gpt-5'});
  expect(requests[0].launch_id).toMatch(/^[a-f0-9-]{36}$/);
  expect(requests[0].provider).toBe('claude');expect(requests[0].model).toBe('haiku');
  expect(requests[0].priorities).toEqual(['Repair the parser',{text:'Verify the rendered output',profile:{provider:'gemini',model:'gemini-2.5-flash'}}]);
  await page.reload();
  await page.locator('#tab-board').click();
  await page.locator('.launch-header').click();
  await expect(page.locator('#launch-btn')).toHaveText('Retry launch');
  await expect(page.locator('#launch-session')).toHaveValue('workspace');
  await page.locator('#launch-btn').click();
  await expect(page.locator('#launch-status')).toContainText('Orchestrator ready. 2/2');
  expect(requests).toHaveLength(2);expect(requests[1]).toEqual(requests[0]);
  await expect(page.locator('#launch-input')).toHaveValue('');
  await expect(page.locator('#launch-input')).toBeEnabled();
  expect(await page.evaluate(()=>JSON.parse(localStorage.getItem('amux_launch_roles_v1')!).pending)).toBeNull();
});

test('a completed launch receipt clears its saved retry without claiming new starts',async ({page})=>{
  await page.route('**/api/sessions',r=>r.fulfill({json:[workspace]}));
  await page.route('**/api/board/launch',r=>r.fulfill({status:201,json:{...result,complete:true,orchestrator:{...result.orchestrator,started:false,complete:true},workers_started:0}}));
  await page.addInitScript(()=>localStorage.setItem('amux_launch_roles_v1',JSON.stringify({fields:{input:'Repair parser',session:'workspace'},pending:{launch_id:'saved-request',parent_session:'workspace',orchestrator:{model:'opus'},priorities:['Repair parser']}})));
  await page.goto('/');
  await page.locator('#tab-board').click();
  await page.locator('.launch-header').click();
  await expect(page.locator('#launch-btn')).toHaveText('Retry launch');
  await page.locator('#launch-btn').click();
  await expect(page.locator('#launch-status')).toHaveText('Orchestration already completed. Epic: E-1');
  await expect(page.locator('#launch-input')).toBeEnabled();
  await expect(page.locator('#launch-input')).toHaveValue('');
});

test('orchestration shows coordinator and child models plus the coordinator own work',async ({page})=>{
  const workers=[{name:'coordinator',orchestrator:true,role:'orchestrator',lifecycle:'active',running:true,profile:{provider:'codex',model:'gpt-5'}},
    {name:'child',ephemeral:true,ephemeral_parent:'coordinator',lifecycle:'active',running:true,profile:{provider:'claude',model:'haiku'},worktree_active:true,branch:'amux/fanout/child'}];
  await page.route('**/api/sessions',r=>r.fulfill({json:workers}));
  await page.route('**/api/board/orchestrations',r=>r.fulfill({json:{measured:true,n_considered:3,workers,ephemeral_workers:['child'],cards:[
    {id:'E',title:'Release orchestration',type:'epic',status:'doing',session:'coordinator',execution_terminal:false},
    {id:'C',title:'Repair parser',type:'code',status:'doing',session:'child',epic:'E',execution_terminal:false},
    {id:'O',title:'Resolve the release contract',type:'investigation',status:'todo',session:'coordinator',execution_terminal:false},
  ]}}));
  await page.goto('/');
  await page.locator('#tab-orchestrations').click();
  const epic=page.locator('[data-orch-id="E"]');
  await expect(epic).toContainText('Orchestrator · codex · gpt-5');
  await expect(epic).toContainText('0/2');
  await epic.locator('.orch-node-chevron').click();
  await expect(epic).toContainText('Fan-out · claude · haiku');
  await expect(epic).toContainText('Resolve the release contract');
  await expect(epic).toContainText('amux/fanout/child');
  await expect(page.locator('[data-orch-id="worker:coordinator"]')).toHaveCount(0);
  expect(await page.evaluate(()=>document.documentElement.scrollWidth-innerWidth)).toBeLessThanOrEqual(1);
  await page.screenshot({path:test.info().outputPath('orchestration-role-tree.png'),fullPage:true});
});
