/**
 * Smart Class - Maintenance Client
 * Version: 0.1.2
 *
 * Shared public-page maintenance notice.
 * This module does not block page features or perform admin mutations.
 */
(function () {
  'use strict';

  if (window.MaintenanceClient) return;

  const CORE_SCOPE = 'site_core';
  const VALID_SCOPES = new Set([
    'site_core',
    'announcements_info',
    'events_competitions',
    'video_content',
    'membership_growth',
    'store_support',
    'downloads_app'
  ]);
  const PAGE_SCOPE_MAP = {
  "index.html": "announcements_info",
  "news.html": "announcements_info",
  "calendar.html": "events_competitions",
  "competitions.html": "events_competitions",
  "videos.html": "video_content",
  "my.html": "membership_growth",
  "coupons.html": "membership_growth",
  "products.html": "store_support",
  "checkout.html": "store_support",
  "support.html": "store_support",
  "downloads.html": "downloads_app",
  "app-updates.html": "downloads_app",
  "settings.html": "downloads_app"
};
  const BANNER_ID = 'maintenanceStatusBanner';
  const REQUEST_TIMEOUT_MS = 8000;

  function getConfig() {
    if (
      typeof SUPABASE_URL === 'undefined' ||
      typeof SUPABASE_ANON_KEY === 'undefined' ||
      !SUPABASE_URL ||
      !SUPABASE_ANON_KEY
    ) {
      throw new Error('Supabase 尚未設定');
    }

    return {
      url: String(SUPABASE_URL).replace(/\/$/, ''),
      key: SUPABASE_ANON_KEY
    };
  }

  function getPageScope() {
    const pageName = window.location.pathname.split('/').pop() || 'index.html';
    const requested =
      document.body?.dataset.maintenanceScope ||
      window.MAINTENANCE_SCOPE ||
      PAGE_SCOPE_MAP[pageName] ||
      CORE_SCOPE;

    return VALID_SCOPES.has(requested) ? requested : CORE_SCOPE;
  }

  function getOptionalAdminToken() {
    // Never read visitor_access_token. The backend independently verifies admin status.
    try {
      return window.localStorage.getItem('access_token') || '';
    } catch (_error) {
      return '';
    }
  }

  async function fetchStatus(scope) {
    const config = getConfig();
    const controller = new AbortController();
    const timeoutId = window.setTimeout(
      () => controller.abort(),
      REQUEST_TIMEOUT_MS
    );

    try {
      const headers = {
        apikey: config.key,
        Accept: 'application/json'
      };
      const token = getOptionalAdminToken();

      if (token) headers.Authorization = 'Bearer ' + token;

      const endpoint =
        config.url +
        '/functions/v1/maintenance-status?scope=' +
        encodeURIComponent(scope);

      const response = await fetch(endpoint, {
        method: 'GET',
        headers,
        cache: 'no-store',
        signal: controller.signal
      });
      const payload = await response.json().catch(() => null);

      if (!response.ok || !payload || payload.ok !== true) {
        throw new Error(
          payload?.error?.message ||
          '維護狀態查詢失敗（HTTP ' + response.status + '）'
        );
      }

      if (!payload.data || typeof payload.data !== 'object') {
        throw new Error('維護狀態回應格式不正確');
      }

      return payload.data;
    } finally {
      window.clearTimeout(timeoutId);
    }
  }

  function ensureBanner() {
    let banner = document.getElementById(BANNER_ID);
    if (banner) return banner;

    if (!document.getElementById('maintenanceClientStyles')) {
      const style = document.createElement('style');
      style.id = 'maintenanceClientStyles';
      style.textContent =
        '#' + BANNER_ID + '{box-sizing:border-box;width:100%;margin:0;padding:14px 18px;' +
        'background:#fff3cd;color:#664d03;border-bottom:1px solid #ffecb5;' +
        'font-size:15px;line-height:1.6;position:relative;z-index:9999}' +
        '#' + BANNER_ID + '[hidden]{display:none}' +
        '#' + BANNER_ID + ' strong{display:block;margin-bottom:3px}';
      document.head.appendChild(style);
    }

    banner = document.createElement('aside');
    banner.id = BANNER_ID;
    banner.setAttribute('role', 'status');
    banner.setAttribute('aria-live', 'polite');
    banner.hidden = true;
    document.body.prepend(banner);
    return banner;
  }

  function showBanner(title, message) {
    const banner = ensureBanner();
    const heading = document.createElement('strong');
    const detail = document.createElement('span');

    heading.textContent = title;
    detail.textContent = message;
    banner.replaceChildren(heading, detail);
    banner.hidden = false;
  }

  function hideBanner() {
    const banner = document.getElementById(BANNER_ID);
    if (banner) banner.hidden = true;
  }

  function chooseActiveStatus(results) {
    const active = results.filter(item => item && item.is_maintenance === true);

    active.sort((a, b) => {
      if (Boolean(a.is_global) !== Boolean(b.is_global)) {
        return Number(Boolean(b.is_global)) - Number(Boolean(a.is_global));
      }

      const aCore = Array.isArray(a.scopes) && a.scopes.includes(CORE_SCOPE);
      const bCore = Array.isArray(b.scopes) && b.scopes.includes(CORE_SCOPE);
      return Number(bCore) - Number(aCore);
    });

    return active[0] || null;
  }

  async function check() {
    const pageScope = getPageScope();
    const scopes = [...new Set([CORE_SCOPE, pageScope])];
    const settled = await Promise.allSettled(scopes.map(fetchStatus));
    const results = settled
      .filter(item => item.status === 'fulfilled')
      .map(item => item.value);
    const failures = settled.filter(item => item.status === 'rejected');

    // Only the server-provided flag, derived from public.is_admin(), grants bypass.
    if (results.some(item => item.admin_bypass === true)) {
      hideBanner();
      return {
        ok: failures.length === 0,
        maintenance: false,
        adminBypass: true,
        partialFailure: failures.length > 0
      };
    }

    const active = chooseActiveStatus(results);
    if (active) {
      showBanner(
        active.title || '網站維護通知',
        active.message || '目前部分服務正在維護，請稍後再試。'
      );
      return {
        ok: failures.length === 0,
        maintenance: true,
        data: active,
        partialFailure: failures.length > 0
      };
    }

    if (failures.length > 0) {
      showBanner(
        '維護狀態暫時無法完整確認',
        '網站目前仍可正常瀏覽，部分服務狀態尚未取得，請稍後再確認。'
      );
      failures.forEach(item =>
        console.warn('[Maintenance] 狀態查詢失敗：', item.reason)
      );
      return { ok: false, maintenance: false, partialFailure: true };
    }

    hideBanner();
    return { ok: true, maintenance: false };
  }

  function start() {
    if (!document.body) return;
    check().catch(error => {
      // Fail-open: this status client never blocks normal page rendering.
      console.warn('[Maintenance] 模組執行失敗：', error);
      showBanner(
        '維護狀態暫時無法確認',
        '網站目前仍可正常瀏覽，請稍後再確認服務狀態。'
      );
    });
  }

  window.MaintenanceClient = { check, start };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start, { once: true });
  } else {
    start();
  }
})();
