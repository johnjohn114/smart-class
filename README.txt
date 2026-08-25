【商業簡介網站｜8 項功能升級版】

這一版是以你上傳的「商業簡介網站_登入修正版(1).zip」為基礎修改。

已加入：
1. 首頁最新消息只顯示最新 3 則，並有「更多消息」頁面。
2. 訪客使用管理員建立的 Supabase Auth 帳號登入。
3. 公告刪除改成檢查 HTTP 回應與 RLS，並加入編輯功能。
4. 商品頁面＋後台新增／編輯／上架／下架／刪除商品。
5. 公告支援置頂與預定發布時間。
6. 公告分類：最新消息／活動／蛋仔／Minecraft伺服器更新。
7. 訪客改回「每個訪客共用同一組統一密碼」，但每位訪客仍有自己的 Email／Auth 使用者 ID。
8. 客服：訪客送出訊息，後台可查看並回覆。
9. 我的優惠券：每張優惠券綁定指定訪客，訪客只能看到自己的優惠券；後台可發給單一訪客或全部訪客。

【第一次設定】
1. 把你原本可用的 config.js 放回本資料夾，覆蓋目前範例檔。
2. 在 Supabase SQL Editor 執行 schema_upgrade.sql。
3. 部署 Edge Functions：
   supabase functions deploy create-visitor
   supabase functions deploy reset-visitor-password
   
5. Edge Function 需要 Supabase 自動提供的 SUPABASE_URL、SUPABASE_ANON_KEY、SUPABASE_SERVICE_ROLE_KEY。
6. schema_upgrade.sql 會把當下已存在的 Auth 使用者建立成 admin。若有多個既有使用者，請手動把真正管理員設成 admin，例如：
   update public.profiles p set role='admin' from auth.users u where p.id=u.id and u.email='你的管理員Email';
7. 新建立的訪客會由 Edge Function 建立為 visitor。

【重要安全提醒】
- 不要把 service_role key 放進 config.js 或任何前端 JS。
- config.js 只放 Supabase URL 與 anon/publishable key。
- 訪客密碼由 Supabase Auth 管理，不會存進 visitor_accounts。
- 如果你在 Supabase 啟用了 Email 驗證，Edge Function 建立訪客時會直接 email_confirm=true；這符合「由管理員建立帳號」的需求。

【本機測試】
可用任何靜態網站伺服器開啟資料夾，例如：
python -m http.server 8000
然後開 http://127.0.0.1:8000/index.html

沒有你的實際 Supabase URL/Key 與資料庫環境時，我可以測試前端檔案、JS 語法、頁面載入與結構，但不能假裝已測試你的真實登入、RLS、Edge Function 和資料庫。


【本次修正版：訪客帳號 CORS】
如果建立訪客時出現「Failed to fetch」或 create-visitor 的 CORS 錯誤，
請務必把這兩個 Function 重新部署，不能只更新前端 ZIP：

supabase functions deploy create-visitor
supabase functions deploy reset-visitor-password

新版 Function 已處理 OPTIONS 預檢請求，並加入：
Access-Control-Allow-Methods: POST, OPTIONS
Access-Control-Allow-Headers: authorization, x-client-info, apikey, content-type

部署完成後重新整理 GitHub Pages，再測試「後台 → 訪客帳號 → 建立訪客」。

注意：如果你是直接在 Supabase Dashboard 編輯 Edge Function，
請把本 ZIP 裡對應的 index.ts 完整貼入並重新 Deploy。

【統一訪客密碼】
後台「訪客帳號」輸入一組統一密碼後建立新訪客；若要把既有訪客全部改成新的統一密碼，輸入新密碼後按「將此密碼套用到所有訪客」。

【優惠券】
執行 schema_upgrade.sql 後會建立 coupons。後台「優惠券」可發給單一訪客或全部訪客；前台「我的優惠券」只查詢目前登入訪客自己的資料。


本次整合：
- 公告連結
- Google 表單風格自製表單
- 前台前 8 個功能保留在外，其餘移入「更多功能」
- 達人榜公布時間改由資料庫 trigger 自動使用 now()
- 後台刪除訪客帳號（需部署 delete-visitor）
- 快速連結管理保留

本版依最新需求取消表單功能；已移除表單前台、後台與表單 SQL 區塊。保留快速連結、公告連結、達人榜發布、訪客刪除與前台更多功能下拉選單。


本次修改：達人榜分類管理新增「新增／修改／刪除」。預設 Minecraft、蛋仔保留；已被比賽使用的自訂分類不允許直接刪除，避免歷屆成績失去分類。
