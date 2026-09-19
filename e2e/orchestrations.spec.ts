// Orchestrations tab: the UI flow from Board -> Orchestrations -> fan-out.
//
// Exercises the full pipeline that the "Launch priorities" bar and the
// Orchestrations kanban render. Creates an epic via the board API, verifies
// it appears in the Orchestrations tab with its children, and checks that
// filter pills and accordion expansion work.
import { test, expect } from './fixtures';

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('amux_walkthrough_done', '1'));
});

// Helper: create a board card via the API.
async function createCard(
  request: any,
  auth: Record<string, string>,
  data: Record<string, unknown>,
) {
  const res = await request.post('/api/board', { headers: auth, data });
  expect(res.ok(), `create card failed: ${res.status()}`).toBeTruthy();
  return res.json();
}

// Helper: link a child card to an epic via PATCH.
async function linkChild(
  request: any,
  auth: Record<string, string>,
  childId: string,
  epicId: string,
) {
  const res = await request.patch(`/api/board/${childId}`, {
    headers: auth,
    data: { epic: epicId },
  });
  expect(res.ok(), `link child failed: ${res.status()}`).toBeTruthy();
}

test.describe('orchestrations tab', () => {
  test('launched epic appears in orchestrations with children', async ({ page, request }) => {
    await page.goto('/');
    const token = await page.evaluate(() => (window as any)._AMUX_AUTH_TOKEN);
    const auth = {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      'X-Amux-Session': 'e2e-orch-test',
    };

    const epicTitle = `e2e-orch-${Date.now()}`;
    const epic = await createCard(request, auth, {
      title: epicTitle,
      type: 'epic',
      status: 'doing',
      session: 'e2e-orch-test',
    });
    const epicId = epic.id;

    // Children must be owned by the same session as the auth header to avoid
    // cross-board refusal. Link them to the epic via PATCH afterward.
    const childTitles = ['Build the widget', 'Test the widget', 'Deploy the widget'];
    for (const title of childTitles) {
      const child = await createCard(request, auth, { title, status: 'todo' });
      await linkChild(request, auth, child.id, epicId);
    }

    // Navigate to the Orchestrations tab
    await page.click('text=Orchestrations');
    await expect(page.locator('#orch-list')).toBeVisible({ timeout: 10_000 });

    // The epic should appear in the list
    await expect(page.locator('#orch-list')).toContainText(epicTitle, { timeout: 10_000 });

    // Filter pills should be present and show counts
    const filterBar = page.locator('#orch-filters');
    await expect(filterBar).toBeVisible();
    await expect(filterBar.locator('button')).toHaveCount(5);

    // Click the epic accordion to expand it
    const epicRow = page.locator(`[data-orch-id="${epicId}"]`).or(
      page.locator('#orch-list').locator(`text=${epicTitle}`),
    );
    await epicRow.first().click();

    // Children should be visible after expansion
    for (const title of childTitles) {
      await expect(page.locator('#orch-list')).toContainText(title, { timeout: 5_000 });
    }
  });

  test('orchestrations tab loads and renders', async ({ page }) => {
    await page.goto('/');
    // Switch to the Orchestrations tab via the tab button rather than deeplink,
    // since the tab button is the user's primary path.
    await page.click('text=Orchestrations');
    await expect(page.locator('#orch-list')).toBeVisible({ timeout: 10_000 });

    // The tab should render content (either the empty state message or epics
    // from prior tests sharing the server).
    const orchList = page.locator('#orch-list');
    await expect(orchList).not.toBeEmpty({ timeout: 5_000 });
  });

  test('epic card detail shows subtasks', async ({ page, request }) => {
    await page.goto('/');
    const token = await page.evaluate(() => (window as any)._AMUX_AUTH_TOKEN);
    const auth = {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      'X-Amux-Session': 'e2e-detail-test',
    };

    const epicTitle = `e2e-detail-epic-${Date.now()}`;
    const epic = await createCard(request, auth, {
      title: epicTitle,
      type: 'epic',
      status: 'doing',
    });

    const childNames = ['Cache invalidation', 'Rate limiter', 'Circuit breaker'];
    for (const title of childNames) {
      const child = await createCard(request, auth, { title, status: 'todo' });
      await linkChild(request, auth, child.id, epic.id);
    }

    // Open the card detail by navigating to the board view and using the
    // deeplink format #issue=<id>. Navigate to / first to get the app shell
    // loaded, then change the hash.
    await page.evaluate((id) => {
      location.hash = '#issue=' + encodeURIComponent(id);
    }, epic.id);

    // Wait for the board detail overlay to appear. The epic title is in an
    // input/textarea (#bd-title) so we check its value, not textContent.
    const titleInput = page.locator('#board-detail-overlay #bd-title');
    await expect(titleInput).toHaveValue(epicTitle, { timeout: 10_000 });

    // The subtasks section renders child titles as text (not inputs).
    for (const title of childNames) {
      await expect(page.locator('#board-detail-overlay')).toContainText(title, { timeout: 5_000 });
    }
  });

  test('filter pills narrow the orchestration list', async ({ page, request }) => {
    await page.goto('/');
    const token = await page.evaluate(() => (window as any)._AMUX_AUTH_TOKEN);
    const auth = {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      'X-Amux-Session': 'e2e-filter-test',
    };

    // Create an active orchestration (status: doing)
    const activeTitle = `e2e-active-${Date.now()}`;
    const activeEpic = await createCard(request, auth, {
      title: activeTitle,
      type: 'epic',
      status: 'doing',
    });
    const activeChild = await createCard(request, auth, {
      title: 'active child',
      status: 'doing',
    });
    await linkChild(request, auth, activeChild.id, activeEpic.id);

    // A queued epic is active work, not a paused worker.
    const pausedTitle = `e2e-paused-${Date.now()}`;
    const pausedEpic = await createCard(request, auth, {
      title: pausedTitle,
      type: 'epic',
      status: 'todo',
    });
    const pausedChild = await createCard(request, auth, {
      title: 'paused child',
      status: 'todo',
    });
    await linkChild(request, auth, pausedChild.id, pausedEpic.id);

    // Navigate to orchestrations
    await page.click('text=Orchestrations');
    await expect(page.locator('#orch-list')).toBeVisible({ timeout: 10_000 });

    // Both epics should appear
    await expect(page.locator('#orch-list')).toContainText(activeTitle, { timeout: 5_000 });
    await expect(page.locator('#orch-list')).toContainText(pausedTitle, { timeout: 5_000 });

    // Click the "Active" filter pill
    await page.click('.orch-filter-pill[data-filter="active"]');
    await expect(page.locator('#orch-list')).toContainText(activeTitle, { timeout: 5_000 });

    await expect(page.locator('#orch-list')).toContainText(pausedTitle);
    // No worker was paused; an epic's To Do status must not imply a pause.
    await page.click('.orch-filter-pill[data-filter="paused"]');
    await expect(page.locator('#orch-list')).not.toContainText(pausedTitle);

    // Click "All" to restore
    await page.click('.orch-filter-pill[data-filter="all"]');
    await expect(page.locator('#orch-list')).toContainText(activeTitle, { timeout: 5_000 });
    await expect(page.locator('#orch-list')).toContainText(pausedTitle, { timeout: 5_000 });
  });
});


test('whole child boards, orphan fan-outs, real pauses and worktree state are visible', async ({ page }) => {
  const cards = [
    { id:'E', title:'Customer reliability epic', type:'epic', status:'doing', session:'parent', execution_terminal:false },
    { id:'A', title:'Assignment implementation', type:'code', status:'done', session:'child', epic:'E', execution_terminal:false },
    { id:'B', title:'Follow-up without an epic link', type:'code', status:'doing', session:'child', execution_terminal:false },
    { id:'C', title:'Orphan board work', type:'code', status:'backlog', session:'orphan', execution_terminal:false },
    { id:'P', title:'Preserved paused work', type:'code', status:'verified', session:'paused-child', execution_terminal:true },
    { id:'R', title:'Retired worker outcome', type:'code', status:'verified', session:'retired', execution_terminal:true },
  ];
  await page.route('**/api/board/orchestrations', r => r.fulfill({json:{measured:true,n_considered:20000,cards,ephemeral_workers:['retired'],workers:[{name:'retired',ephemeral:true,lifecycle:'expired',running:false}]}}));
  await page.route('**/api/sessions', r => r.fulfill({json:[
    {name:'child',ephemeral:true,lifecycle:'active',running:true,status:'active',task_board_id:'B',worktree_active:true,branch:'amux/fanout/child',worktree_integration:{status:'requires_work',detail:'Validation failed: fix on this worker'}},
    {name:'orphan',ephemeral:true,lifecycle:'active',running:false,status:'idle'},
    {name:'paused-child',ephemeral:true,lifecycle:'paused',running:false,status:'paused'},
  ]}));
  const fullHistory: string[]=[];
  page.on('request',r=>{if(r.url().includes('/api/board?all=1&slim=0')) fullHistory.push(r.url());});
  await page.goto('/');
  await page.locator('#tab-orchestrations').click();
  const root=page.locator('[data-orch-id="E"]');
  await expect(root).toContainText('0/2'); // Code Done still needs its terminal gate.
  await root.locator('.orch-node-header').click();
  await expect(root).toContainText('Follow-up without an epic link');
  await expect(root.locator('.working-now')).toContainText('Working now');
  await expect(root).toContainText('amux/fanout/child');
  await expect(root).toContainText('requires work');
  await expect(page.locator('[data-orch-id="worker:orphan"]')).toBeVisible();
  await page.click('.orch-filter-pill[data-filter="paused"]');
  await expect(page.locator('#orch-list')).toContainText('paused-child');
  await expect(page.locator('#orch-list')).not.toContainText('Customer reliability epic');
  expect(fullHistory).toEqual([]);
  await page.click('.orch-filter-pill[data-filter="expired"]');
  await expect(page.locator('#orch-list')).toContainText('retired');
  await expect(page.locator('#orch-list')).not.toContainText('paused-child');
  await page.click('.orch-filter-pill[data-filter="all"]');
  const width=await page.evaluate(()=>({w:innerWidth,body:document.documentElement.scrollWidth}));
  expect(width.body).toBeLessThanOrEqual(width.w+1);
  await page.screenshot({path:test.info().outputPath('orchestrations.png'),fullPage:true});
});

test('loading and failed measurement are explicit and retry recovers', async ({ page }) => {
  let attempts=0;
  await page.route('**/api/board/orchestrations', async r => {
    attempts++;
    if(attempts===1) { await new Promise(resolve=>setTimeout(resolve,600)); await r.fulfill({status:503,json:{measured:false,error:'fixture failure'}}); }
    else await r.fulfill({json:{measured:true,n_considered:0,cards:[]}});
  });
  await page.route('**/api/sessions', r => r.fulfill({json:[]}));
  await page.goto('/');
  await page.locator('#tab-orchestrations').click();
  await expect(page.locator('#orch-list')).toContainText('Loading orchestration boards');
  await expect(page.locator('#orch-list [role="alert"]')).toContainText('Could not load');
  await page.locator('#orch-list').getByRole('button',{name:'Retry'}).click();
  await expect(page.locator('#orch-list')).toContainText('No orchestrations yet');
  expect(attempts).toBe(2);
});


test('board content is visible while live worker status is still pending', async ({ page }) => {
  let release!:()=>void;
  const gate=new Promise<void>(resolve=>{release=resolve;});
  await page.route('**/api/sessions',async r=>{await gate;await r.fulfill({json:[]});});
  await page.route('**/api/board/orchestrations',r=>r.fulfill({json:{measured:true,n_considered:1,cards:[{id:'PENDING',title:'Visible without runtime probes',type:'epic',status:'todo',execution_terminal:false}],workers:[]}}));
  try {
    await page.goto('/');
    await page.locator('#tab-orchestrations').click();
    await expect(page.locator('#orch-list')).toContainText('Visible without runtime probes',{timeout:2000});
  } finally { release(); }
});
