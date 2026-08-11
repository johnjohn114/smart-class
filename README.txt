【管理後台登入修正版】

這一版修正了後台登入程式，並加入清楚的錯誤提示。

最重要：
修復版原本的 config.js 是「範例檔」，不是你的 Supabase 設定。
如果你之前有一個可以正常使用的 config.js，請把那一份複製到本資料夾，覆蓋目前的 config.js。

config.js 必須包含：
const SUPABASE_URL = "https://你的專案.supabase.co";
const SUPABASE_ANON_KEY = "你的 anon/publishable key";
const DEMO_VISITOR_PASSWORD = "你的訪客密碼";

注意：
- 不要放 service_role key。
- 管理員 Email/密碼不是寫在 config.js。
- 管理員帳號是在 Supabase Authentication > Users 建立的。
- 如果 Supabase 開啟 Email 驗證，管理員帳號必須先完成驗證（除非你在 Supabase 設定中允許自動確認）。

使用：
1. 解壓縮本 ZIP。
2. 將你原本可用的 config.js 複製進來並覆蓋。
3. 開 admin.html。
4. 輸入你在 Supabase Authentication > Users 建立的管理員 Email 與密碼。

如果仍然登入不了：
把後台「管理員登入」畫面上的紅色錯誤文字截圖給我，我就能判斷是帳號、Email 驗證、Supabase URL/Key，還是權限問題。
