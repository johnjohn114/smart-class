'use strict';

const assert = require('node:assert/strict');
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
    await page.locator('#maintenanceTab').evaluate(el => el.classList.remove('hidden'));

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
    assert.equal(new URL(paginationCalls[0], window.location.origin).searchParams.has('cursor'), false);
    assert.equal(
      new URL(paginationCalls[1], window.location.origin).searchParams.get('cursor'),
      'opaque-cursor-page-two',
      'next page must send the opaque cursor unchanged'
    );
    assert.equal(new URL(paginationCalls[2], window.location.origin).searchParams.has('cursor'), false);
    assert.deepEqual(errors, [], 'admin runtime errors: ' + errors.join('; '));
    await page.close();
  }

  console.log('Browser compatibility checks passed (homepage + admin feature gate).');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
}).finally(async () => {
  if (browser) await browser.close();
  if (server) server.kill('SIGTERM');
});
