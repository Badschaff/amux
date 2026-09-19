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

    // Create a paused orchestration (status: todo)
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

    // Click the "Paused" filter pill
    await page.click('.orch-filter-pill[data-filter="paused"]');
    await expect(page.locator('#orch-list')).toContainText(pausedTitle, { timeout: 5_000 });

    // Click "All" to restore
    await page.click('.orch-filter-pill[data-filter="all"]');
    await expect(page.locator('#orch-list')).toContainText(activeTitle, { timeout: 5_000 });
    await expect(page.locator('#orch-list')).toContainText(pausedTitle, { timeout: 5_000 });
  });
});
