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
