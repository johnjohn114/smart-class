# 26.11.2 Firebase 推播部署步驟

此版目前已加入 Android FCM 接收程式、管理員公告推播開關、裝置 token 登錄程式與 Supabase Edge Function 原始碼。要正式送達手機，仍須完成以下一次性部署設定。

## 1. 執行資料庫 SQL

在 Supabase Dashboard → SQL Editor，執行本專案的 `FCM_PUSH_SETUP_26.11.2.sql`。

此 SQL 只新增公告推播欄位與裝置 token 表，不會刪除或覆蓋現有公告。

## 2. 建立 Firebase 服務帳戶金鑰

在 Firebase Console → 專案設定 → 服務帳戶：
1. 確認 Firebase 專案是 `announcement-zone`。
2. 產生新的私密金鑰 JSON。
3. 將 JSON 安全保存在自己的電腦；不要提交到 GitHub、不要放入 Android APK、不要貼到聊天室。

## 3. 設定 Supabase Edge Function Secrets

在 Supabase Dashboard → Edge Functions → Secrets，新增：
- `FIREBASE_SERVICE_ACCOUNT_JSON`：完整服務帳戶 JSON 原文。
- `SUPABASE_URL` 與 `SUPABASE_SERVICE_ROLE_KEY`：若部署環境尚未提供，才需設定。

服務帳戶需要具備 Firebase Cloud Messaging 發送權限。不要將 service role key 或 Firebase 私鑰放入網站前端或 Android App。

## 4. 部署 Edge Function

使用 Supabase CLI，在專案目錄執行：

```bash
supabase functions deploy send-announcement-push
```

此函式會驗證呼叫者 Supabase 登入狀態與 `profiles.role = admin`，只對已發布且已勾選推播的公告發送，並以 `push_sent_at` 避免重複廣播。

## 5. 編譯及裝置測試

- 安裝 26.11.2 APK，登入訪客帳號並允許 Android 通知權限。
- 確認 `device_push_tokens` 出現該裝置 token。
- 後台新增測試公告，勾選推播並發布。
- 測試 App 在前景、背景、關閉後的通知接收，以及點擊通知是否開啟對應公告。
- 再測試取消勾選推播時只發布公告、不發送手機通知。

## 目前限制與注意事項

- 本版 token 登錄目前針對 Android 原生 App；純瀏覽器網站不會註冊 FCM token。
- 管理員編輯既有公告不會再次推播；只有新增公告時才會觸發發送。
- 若沒有任何裝置完成登入及允許通知，函式會回報沒有已註冊裝置。
- Edge Function 與 SQL 必須部署後，推播流程才會真正生效。
