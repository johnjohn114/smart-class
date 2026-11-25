// Supabase 設定：把下面兩項換成你自己的專案資料。
const SUPABASE_URL = "https://fsoowongtavlsrwvzbze.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_nAKu843QXRNajjS5F6EYGA_xxn9UlLb";

// 訪客登入由 Supabase Auth 處理；不得在前端設定檔保存共用密碼。

// 正式 Supabase 維護資料表、RPC 與 Edge Functions 尚未部署前，保持關閉。
// 完成後端部署與驗證後，才改為 true。
const MAINTENANCE_FEATURE_ENABLED = false;

// 載入共用維護狀態提示；各頁面由 maintenance-client.js 自動判斷所屬範圍。
(function loadMaintenanceClient() {
  if (document.querySelector('script[data-maintenance-client]')) return;

  const currentScript = document.currentScript;
  if (!currentScript || !currentScript.src) return;

  const clientScript = document.createElement('script');
  clientScript.src = new URL('maintenance-client.js?v=0.1.2', currentScript.src).href;
  clientScript.async = true;
  clientScript.dataset.maintenanceClient = 'true';
  document.head.appendChild(clientScript);
})();
