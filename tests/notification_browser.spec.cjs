const { chromium } = require('playwright');
const assert = require('node:assert/strict');

const baseUrl = 'http://127.0.0.1:4173';
const supabaseHost = 'https://fsoowongtavlsrwvzbze.supabase.co';
const memberId = 'preview-member-001';
let rows = [
  { id: 'notice-unread', user_id: memberId, type: '一般', title: '預覽未讀通知', content: '這是一則模擬的未讀通知。', created_at: '2026-11-22T09:00:00Z', read_at: null },
  { id: 'notice-read', user_id: memberId, type: '比賽', title: '預覽已讀通知', content: '這是一則模擬的已讀通知。', created_at: '2026-11-21T09:00:00Z', read_at: '2026-11-21T10:00:00Z' },
];

(async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage();
    await page.addInitScript(() => localStorage.setItem('visitor_access_token', 'preview-only-token'));

    // Every Supabase request is intercepted here. This test never contacts the real project.
    await page.route('https://fsoowongtavlsrwvzbze.supabase.co/**', async route => {
      const request = route.request();
      const url = new URL(request.url());
      const method = request.method();
      let body = null;
      let status = 200;

      if (url.pathname === '/auth/v1/user') {
        body = { id: memberId, email: 'preview@example.invalid' };
      } else if (url.pathname === '/rest/v1/notifications') {
        const userFilter = url.searchParams.get('user_id');
        const unreadOnly = url.searchParams.get('read_at') === 'is.null';
        const readOnly = url.searchParams.get('read_at') === 'not.is.null';
        if (method === 'GET') {
          body = rows.filter(row =>
            (!userFilter || userFilter === 'eq.' + memberId) &&
            (!unreadOnly || !row.read_at) &&
            (!readOnly || !!row.read_at)
          );
        } else if (method === 'PATCH') {
          const idFilter = url.searchParams.get('id');
          const patch = request.postDataJSON();
          rows = rows.map(row => {
            const memberMatches = !userFilter || userFilter === 'eq.' + memberId;
            const idMatches = !idFilter || idFilter === 'eq.' + row.id;
            const unreadMatches = url.searchParams.get('read_at') !== 'is.null' || !row.read_at;
            return memberMatches && idMatches && unreadMatches ? { ...row, ...patch } : row;
          });
          body = null;
        } else if (method === 'DELETE') {
          rows = rows.filter(row => {
            const memberMatches = !userFilter || userFilter === 'eq.' + memberId;
            return !(memberMatches && !!row.read_at);
          });
          body = null;
        } else {
          status = 405;
          body = { message: 'Method not allowed in preview mock' };
        }
      } else if (url.pathname.startsWith('/rest/v1/')) {
        body = [];
      } else {
        status = 404;
        body = { message: 'Unknown preview route' };
      }

      await route.fulfill({
        status,
        contentType: 'application/json',
        body: body === null ? '' : JSON.stringify(body),
      });
    });

    await page.goto(baseUrl + '/my.html', { waitUntil: 'domcontentloaded' });
    await page.locator('a[data-target="myNotificationsPanel"]').click();
    await page.getByText('預覽未讀通知').waitFor();
    await page.getByText('預覽已讀通知').waitFor();
    assert.match(await page.locator('#notificationSummary').innerText(), /共 2 則通知.*未讀 1 則/);

    await page.locator('#notificationFilter').selectOption('unread');
    await page.getByText('預覽未讀通知').waitFor();
    assert.equal(await page.getByText('預覽已讀通知').count(), 0);

    await page.locator('#notificationFilter').selectOption('read');
    await page.getByText('預覽已讀通知').waitFor();
    assert.equal(await page.getByText('預覽未讀通知').count(), 0);

    await page.locator('#notificationFilter').selectOption('all');
    await page.locator('button.markRead[data-notice="notice-unread"]').click();
    await page.waitForFunction(() => document.querySelector('#notificationSummary')?.textContent.includes('未讀 0 則'));
    assert.ok(rows.find(row => row.id === 'notice-unread').read_at);

    page.once('dialog', dialog => dialog.accept());
    await page.locator('#deleteReadNotifications').click();
    await page.getByText('目前沒有通知。').waitFor();
    assert.equal(rows.length, 0);

    console.log('PASS: mocked member login, notification loading, filters, mark-read, and delete-read flow.');
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
