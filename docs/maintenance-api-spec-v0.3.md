> **已被 v0.4 取代（2026-11-08）**：本文件提到的 SUPABASE_DB_URL + Postgres driver 與 private table 無任何 authenticated grants 的說法已不再採用。最新執行模型為使用者 JWT + public SECURITY INVOKER RPC + private schema + RLS，詳見 [maintenance-connection-architecture-v0.4.md](./maintenance-connection-architecture-v0.4.md)。請勿依本文件的舊連線描述實作。

# 維護系統 API 規格 v0.3（安全審核修正版）

> 尚未實作、尚未部署。與資料庫設計 v0.3 配套。
> 不代表任何 endpoint 已存在。

## 共通安全規則

- 管理 API `verify_jwt=true`，並在函式內以 `auth.getUser()` 驗證使用者，再以同一使用者 JWT 呼叫現有 `public.is_admin()`。
- `is_admin_user()` 不用於新功能，因目前 anon 也有 EXECUTE。
- 管理操作的 actor_id 一律由驗證後 user.id 取得。
- 前端傳入的 role、isAdmin、actor_id、email 一律不作授權依據。
- 公開 status API 設 `verify_jwt=false`；可選擇驗證有效 bearer token 判斷管理員 bypass。無效 token 不取得 bypass。
- 管理員 bypass 不跳過 API 驗證。
- Edge Function 僅在伺服器端使用 `SUPABASE_DB_URL`。DB 連線用 Postgres driver，transaction pooler／適當連線模式、pool max 1、prepared statements off、SSL required。不得把 DB URL 或密碼放進前端。
- 維護表在 `private` schema，不暴露 Data API，不授予 anon/authenticated 直接表權限。
- 所有 DB 查詢固定、參數化；不接受任意 SQL。
- JSON 回應：成功 `{ "ok": true, "data": ... }`；錯誤 `{ "ok": false, "error": { "code": "...", "message": "..." } }`。

## 1. `maintenance-status`

公開唯讀。輸入可選 scope code。
- scope code 必須是七個已確認代碼之一。
- 不帶 scope 時只回傳全站維護資訊，不推測局部頁面所屬範圍。
- 帶 scope 時回傳全站事件及該 scope 的局部事件。
- 只回傳 title、message、is_global、scope codes、starts_at、ends_at、server_time 等公開欄位。
- 不回傳 internal_note、actor、audit snapshots、idempotency data。
- 若 token 有效且 is_admin() 為 true，可回傳 admin_bypass=true；此欄位僅供 UI 顯示，不授權任何管理操作。

## 2. `maintenance-admin-list`

JWT + admin required。
- 篩選 status、scope、is_global、from、to、limit、cursor。
- 回傳事件、scope、status、version、建立／更新時間及 internal_note。
- internal_note 僅限通過 admin check 的呼叫者。

## 3. `maintenance-event-create`

JWT + admin required。
輸入：title、message、internal_note、is_global、scope_codes、starts_at、ends_at、status、reason、idempotency_key。
- starts_at < ends_at。
- is_global=true 時 scope_codes 必須空陣列。
- is_global=false 時至少一個有效且 enabled 的 scope code。
- 初次建立以 draft 或 scheduled 為主；scheduled 必須通過衝突檢查。
- event、scope links、audit、idempotency 同一 DB transaction。

## 4. `maintenance-event-update`

JWT + admin required。
輸入：event_id、expected_version、允許更新欄位、reason、idempotency_key。
- 僅允許白名單欄位。
- expected_version 不符回傳 409 VERSION_CONFLICT。
- 若更新時間、scope 或 is_global，重新檢查排程衝突。
- 已取消／完成事件不可一般更新回 scheduled。
- 更新與 audit 同交易。

## 5. `maintenance-event-action`

JWT + admin required。
初步 actions：schedule、cancel、complete。
- 狀態轉換不合法回 409。
- schedule 重新檢查排程衝突。
- cancel／complete 記錄時間、原因與稽核快照。
- 所有 action 都支援 idempotency key 與 expected_version。
- start_now、extend、end_early 暫不開放，待產品規則確認。

## 排程衝突

半開區間 `[starts_at, ends_at)`：
- global/global、global/local、local/global 重疊均衝突。
- local/local 僅 scope 交集非空且時間重疊才衝突。
- draft、cancelled、completed 不佔用排程；scheduled 佔用。
- 鎖、衝突檢查、事件寫入、audit、idempotency 在單一 DB transaction 內完成。

## 錯誤碼

- 400 INVALID_REQUEST
- 401 UNAUTHENTICATED
- 403 FORBIDDEN
- 404 NOT_FOUND
- 409 CONFLICT / VERSION_CONFLICT / IDEMPOTENCY_KEY_REUSED
- 422 VALIDATION_ERROR
- 429 RATE_LIMITED
- 500 INTERNAL_ERROR

## 仍待定稿

- 事件開始後允許修改哪些欄位。
- 七個 scope 的每頁／每個共用 API 映射。
- 各 scope 維護時採封鎖、唯讀或提示。
- audit 保留期限。
- DB connection pooler 的實際設定及本地測試方法。

**本規格未實作，沒有建立 Edge Functions 或修改正式資料庫。**
