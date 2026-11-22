'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { setTimeout: delay } = require('node:timers/promises');
const { chromium } = require('playwright');

const BASE_URL = process.env.BROWSER_TEST_BASE_URL || 'http://127.0.0.1:4173';
let server;
let browser;

async function waitForServer(url) {
  for (let attempt = 0; attempt < 40; attempt += 1) {
    try {
      const response = await fetch(url);
      if (response.ok) return;
    } catch (_) {
      // The local server may still be starting.
    }
    await delay(250);
  }
  throw new Error('Local static server did not become ready');
}

async function createPageErrors(page) {
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.route('https://*.supabase.co/**', route => route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: '[]',
  }));
  return errors;
}

(async () => {
  server = spawn('python3', ['-m', 'http.server', '4173', '--bind', '127.0.0.1'], {
    stdio: 'ignore',
  });
  await waitForServer(BASE_URL);
  browser = await chromium.launch({ headless: true });

  // Public homepage: preserve the existing page shell and do not call the
  // maintenance endpoint while the feature flag is disabled.
  {
    const page = await browser.newPage();
    const errors = await createPageErrors(page);
    const maintenanceRequests = [];
    page.on('request', request => {
      if (request.url().includes('/functions/v1/maintenance-status')) {
        maintenanceRequests.push(request.url());
      }
    });

    await page.goto(BASE_URL + '/index.html', { waitUntil: 'domcontentloaded' });
    await page.locator('#home').waitFor({ state: 'visible' });
    assert.equal(await page.locator('#heroTitle').count(), 1);
    assert.equal(await page.locator('#news').count(), 1);
    assert.equal(await page.locator('#about').count(), 1);
    assert.equal(await page.locator('#features').count(), 1);
    assert.equal(await page.locator('#contact').count(), 1);
    assert.equal(await page.locator('script[src^="app.js"]').count(), 1);
    await page.waitForTimeout(300);
    assert.deepEqual(maintenanceRequests, [], 'maintenance API must stay unused while disabled');
    assert.deepEqual(errors, [], 'homepage runtime errors: ' + errors.join('; '));
    await page.close();
  }

  // Admin page: original login remains available and the maintenance tab stays
  // hidden until the feature flag is explicitly enabled.
  {
    const page = await browser.newPage();
    const errors = await createPageErrors(page);
    await page.goto(BASE_URL + '/admin.html', { waitUntil: 'domcontentloaded' });
    await page.locator('#login').waitFor({ state: 'visible' });
    assert.equal(await page.locator('#email').count(), 1);
    assert.equal(await page.locator('#password').count(), 1);
    assert.equal(await page.locator('#loginButton').count(), 1);
    assert.equal(await page.locator('[data-tab="maintenanceTab"]').isHidden(), true);
    assert.equal(await page.locator('#dashboard').evaluate(el => el.classList.contains('hidden')), true);

    // Pending idempotency keys survive a reload in the same tab, but successful
    // operations clear them so a later intentional retry receives a fresh key.
    const firstKey = await page.evaluate(async () => {
      return await maintenanceIdempotencyKey('maintenance-event-create', {
        title: 'browser-test-only',
        reason: 'compatibility-check'
      });
    });
    await page.reload({ waitUntil: 'domcontentloaded' });
    const persistedKey = await page.evaluate(async () => {
      return await maintenanceIdempotencyKey('maintenance-event-create', {
        title: 'browser-test-only',
        reason: 'compatibility-check'
      });
    });
    assert.equal(persistedKey, firstKey, 'idempotency key should persist across reload');
    await page.evaluate(async () => {
      await maintenanceClearIdempotencyKey('maintenance-event-create', {
        title: 'browser-test-only',
        reason: 'compatibility-check'
      });
    });
    const freshKey = await page.evaluate(async () => {
      return await maintenanceIdempotencyKey('maintenance-event-create', {
        title: 'browser-test-only',
        reason: 'compatibility-check'
      });
    });
    assert.notEqual(freshKey, firstKey, 'cleared idempotency key should be regenerated');

    // Reveal only the maintenance panel inside this isolated browser test so
    // its real controls can be exercised. The production feature flag and tab
    // remain disabled; no Supabase request is made.
    await page.evaluate(() => {
      document.querySelector('#login')?.classList.add('hidden');
      document.querySelector('#dashboard')?.classList.remove('hidden');
      document.querySelector('#maintenanceTab')?.classList.remove('hidden');
    });

    // Exercise the actual cursor pager without enabling the production feature
    // or contacting Supabase. The request stub returns two deterministic pages.
    await page.evaluate(async () => {
      window.__maintenanceListCalls = [];
      window.maintenanceAdminRequest = async path => {
        window.__maintenanceListCalls.push(path);
        const url = new URL(path, window.location.origin);
        const cursor = url.searchParams.get('cursor');
        if (!cursor) {
          return {
            events: [{ id: 'page-one', title: 'Page one', message: '', scopes: [] }],
            next_cursor: 'opaque-cursor-page-two'
          };
        }
        if (cursor === 'opaque-cursor-page-two') {
          return {
            events: [{ id: 'page-two', title: 'Page two', message: '', scopes: [] }],
            next_cursor: null
          };
        }
        throw new Error('Unexpected pagination cursor: ' + cursor);
      };
      await loadMaintenanceEvents({ reset: true });
    });

    assert.equal(await page.locator('#maintenanceEventList').getAttribute('class') !== null, true);
    assert.match(await page.locator('#maintenancePagination').innerText(), /第 1 頁/);
    assert.equal(await page.locator('#maintenancePrevPage').isDisabled(), true);
    assert.equal(await page.locator('#maintenanceNextPage').isDisabled(), false);

    await page.locator('#maintenanceNextPage').click();
    await page.getByText('第 2 頁').waitFor();
    assert.match(await page.locator('#maintenanceEventList').innerText(), /Page two/);
    assert.equal(await page.locator('#maintenancePrevPage').isDisabled(), false);
    assert.equal(await page.locator('#maintenanceNextPage').isDisabled(), true);

    await page.locator('#maintenancePrevPage').click();
    await page.getByText('第 1 頁').waitFor();
    assert.match(await page.locator('#maintenanceEventList').innerText(), /Page one/);
    const paginationCalls = await page.evaluate(() => window.__maintenanceListCalls);
    assert.equal(paginationCalls.length, 3, 'first, next, and previous page requests should run');
    assert.equal(new URL(paginationCalls[0], BASE_URL).searchParams.has('cursor'), false);
    assert.equal(
      new URL(paginationCalls[1], BASE_URL).searchParams.get('cursor'),
      'opaque-cursor-page-two',
      'next page must send the opaque cursor unchanged'
    );
    assert.equal(new URL(paginationCalls[2], BASE_URL).searchParams.has('cursor'), false);
    assert.deepEqual(errors, [], 'admin runtime errors: ' + errors.join('; '));
    await page.close();
  }


  // Public maintenance notice: the enabled flag and active status are
  // simulated locally; this never contacts the hosted Supabase project.
  {
    const page = await browser.newPage();
    const errors = await createPageErrors(page);
    const configPath = path.resolve(__dirname, '../../config.js');
    const configSource = fs.readFileSync(configPath, 'utf8');
    const disabledFlag = 'const MAINTENANCE_FEATURE_ENABLED = false;';
    assert.ok(configSource.includes(disabledFlag), 'expected default-off maintenance feature flag');
    await page.route('**/config.js**', route => route.fulfill({
      status: 200,
      contentType: 'application/javascript',
      body: configSource.replace(disabledFlag, 'const MAINTENANCE_FEATURE_ENABLED = true;')
    }));
    await page.route('https://*.supabase.co/functions/v1/maintenance-status**', route => route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        ok: true,
        data: {
          is_maintenance: true,
          is_global: true,
          title: '瀏覽器測試維護通知',
          message: '網站目前進行測試維護。',
          scopes: []
        }
      })
    }));
    await page.goto(BASE_URL + '/index.html', { waitUntil: 'domcontentloaded' });
    const banner = page.locator('#maintenanceStatusBanner');
    await banner.waitFor({ state: 'visible' });
    assert.match(await banner.innerText(), /瀏覽器測試維護通知/);
    assert.match(await banner.innerText(), /網站目前進行測試維護/);
    assert.deepEqual(errors, [], 'public maintenance banner runtime errors: ' + errors.join('; '));
    await page.close();
  }

  // Enabled maintenance flow: override the feature flag only in this isolated
  // browser context and keep every API operation in an in-memory test double.
  {
    const page = await browser.newPage();
    const errors = await createPageErrors(page);
    const configPath = path.resolve(__dirname, '../../config.js');
    const configSource = fs.readFileSync(configPath, 'utf8');
    const disabledFlag = 'const MAINTENANCE_FEATURE_ENABLED = false;';
    assert.ok(configSource.includes(disabledFlag), 'expected default-off maintenance feature flag');
    await page.route('**/config.js**', route => route.fulfill({
      status: 200,
      contentType: 'application/javascript',
      body: configSource.replace(disabledFlag, 'const MAINTENANCE_FEATURE_ENABLED = true;')
    }));
    await page.route('https://*.supabase.co/functions/v1/maintenance-status**', route => route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        ok: true,
        data: {
          is_maintenance: true,
          is_global: true,
          title: '測試維護通知',
          message: '這是隔離瀏覽器測試，不會影響正式網站。',
          scopes: []
        }
      })
    }));
    page.on('dialog', dialog => dialog.accept());

    await page.goto(BASE_URL + '/admin.html', { waitUntil: 'domcontentloaded' });
    // Reveal the dashboard before asserting tab visibility: the tab is nested
    // inside #dashboard, which is hidden until an admin logs in.
    await page.evaluate(() => {
      document.querySelector('#login')?.classList.add('hidden');
      document.querySelector('#dashboard')?.classList.remove('hidden');
    });
    await page.locator('[data-tab="maintenanceTab"]').waitFor({ state: 'visible' });
    await page.evaluate(() => {
      window.__maintenanceEvents = [];
      window.__maintenanceCalls = [];
      window.maintenanceAdminRequest = async (endpoint, options = {}) => {
        const method = options.method || 'GET';
        const body = options.body || null;
        window.__maintenanceCalls.push({ endpoint, method, body });
        if (endpoint.startsWith('maintenance-admin-list?')) {
          return { events: window.__maintenanceEvents, next_cursor: null };
        }
        if (endpoint === 'maintenance-event-create') {
          const event = {
            id: 'browser-event-' + (window.__maintenanceEvents.length + 1),
            version: 1,
            status: 'draft',
            title: body.title,
            message: body.message,
            internal_note: body.internal_note,
            is_global: body.is_global,
            scopes: body.scope_codes,
            starts_at: body.starts_at,
            ends_at: body.ends_at
          };
          window.__maintenanceEvents.push(event);
          return { event };
        }
        if (endpoint === 'maintenance-event-update') {
          const event = window.__maintenanceEvents.find(item => item.id === body.event_id);
          if (!event) throw new Error('test event not found for update');
          Object.assign(event, {
            title: body.title,
            message: body.message,
            internal_note: body.internal_note,
            version: event.version + 1
          });
          return { event };
        }
        if (endpoint === 'maintenance-event-action') {
          const event = window.__maintenanceEvents.find(item => item.id === body.event_id);
          if (!event) throw new Error('test event not found for action');
          event.status = body.action === 'schedule' ? 'scheduled' :
            body.action === 'cancel' ? 'cancelled' : 'completed';
          event.version += 1;
          return { event };
        }
        throw new Error('Unexpected maintenance endpoint: ' + endpoint);
      };
    });

    await page.locator('[data-tab="maintenanceTab"]').click();
    await page.locator('#maintenanceTitle').fill('瀏覽器測試維護事件');
    await page.locator('#maintenanceMessage').fill('測試訪客維護通知');
    await page.locator('#maintenanceStartsAt').fill('2027-01-10T10:00');
    await page.locator('#maintenanceEndsAt').fill('2027-01-10T11:00');
    await page.locator('[data-maintenance-scope="site_core"]').check();
    await page.locator('#maintenanceReason').fill('隔離瀏覽器建立測試');
    await page.locator('#saveMaintenanceEvent').click();
    await page.getByText('瀏覽器測試維護事件').waitFor();

    let calls = await page.evaluate(() => window.__maintenanceCalls);
    const createCall = calls.find(call => call.endpoint === 'maintenance-event-create');
    assert.ok(createCall, 'create action should call the maintenance create endpoint');
    assert.equal(createCall.body.status, 'draft');
    assert.equal(createCall.body.is_global, false);
    assert.deepEqual(createCall.body.scope_codes, ['site_core']);
    assert.equal(createCall.body.starts_at, '2027-01-10T02:00:00.000Z',
      'Taipei start time should be converted to UTC correctly');
    assert.equal(createCall.body.ends_at, '2027-01-10T03:00:00.000Z',
      'Taipei end time should be converted to UTC correctly');

    await page.locator('[data-maintenance-edit="browser-event-1"]').click();
    await page.locator('#maintenanceTitle').fill('瀏覽器測試維護事件（已修改）');
    await page.locator('#maintenanceMessage').fill('修改後的訪客訊息');
    await page.locator('#maintenanceReason').fill('隔離瀏覽器修改測試');
    await page.locator('#saveMaintenanceEvent').click();
    await page.getByText('瀏覽器測試維護事件（已修改）').waitFor();
    calls = await page.evaluate(() => window.__maintenanceCalls);
    assert.ok(calls.some(call => call.endpoint === 'maintenance-event-update' &&
      call.body.title === '瀏覽器測試維護事件（已修改）'),
    'edit action should submit the changed event');

    await page.locator('#maintenanceReason').fill('隔離瀏覽器排程測試');
    await page.locator('[data-maintenance-action="schedule"][data-maintenance-id="browser-event-1"]').click();
    await page.getByText('已排程', { exact: false }).waitFor();

    // Simulate the scheduled event reaching its end time without waiting in CI.
    await page.evaluate(async () => {
      window.__maintenanceEvents[0].ends_at = '2020-01-01T00:00:00.000Z';
      await loadMaintenanceEvents({ reset: true });
    });
    await page.locator('#maintenanceReason').fill('隔離瀏覽器完成測試');
    await page.locator('[data-maintenance-action="complete"][data-maintenance-id="browser-event-1"]').click();
    await page.getByText('已完成', { exact: false }).waitFor();

    // A second event exercises the cancellation path independently.
    await page.locator('#maintenanceTitle').fill('瀏覽器測試取消事件');
    await page.locator('#maintenanceMessage').fill('取消流程測試');
    await page.locator('#maintenanceStartsAt').fill('2027-01-11T10:00');
    await page.locator('#maintenanceEndsAt').fill('2027-01-11T11:00');
    await page.locator('[data-maintenance-scope="site_core"]').check();
    await page.locator('#maintenanceReason').fill('隔離瀏覽器取消流程建立');
    await page.locator('#saveMaintenanceEvent').click();
    await page.getByText('瀏覽器測試取消事件').waitFor();
    await page.locator('#maintenanceReason').fill('隔離瀏覽器取消測試');
    await page.locator('[data-maintenance-action="schedule"][data-maintenance-id="browser-event-2"]').click();
    await page.getByText('已排程', { exact: false }).waitFor();
    await page.locator('#maintenanceReason').fill('隔離瀏覽器取消測試');
    await page.locator('[data-maintenance-action="cancel"][data-maintenance-id="browser-event-2"]').click();
    await page.getByText('已取消', { exact: false }).waitFor();

    calls = await page.evaluate(() => window.__maintenanceCalls);
    for (const endpoint of [
      'maintenance-event-create',
      'maintenance-event-update',
      'maintenance-event-action'
    ]) {
      assert.ok(calls.some(call => call.endpoint === endpoint),
        'expected browser interaction to call ' + endpoint);
    }
    assert.deepEqual(errors, [], 'enabled maintenance browser runtime errors: ' + errors.join('; '));
    await page.close();
  }

  console.log('Browser compatibility checks passed (homepage + admin feature gate + maintenance lifecycle).');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
}).finally(async () => {
  if (browser) await browser.close();
  if (server) server.kill('SIGTERM');
});
