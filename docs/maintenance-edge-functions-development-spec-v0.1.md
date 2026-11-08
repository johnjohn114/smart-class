# Maintenance System Edge Functions 開發規格與 RPC 權限矩陣 v0.1

> 日期：2026-11-08  
> 分支：`feature/maintenance-system`  
> 狀態：開發前規格；尚未建立 Edge Functions/RPC，尚未執行 SQL，未部署。  
> 本文件依據 API 規格 v0.5、連線架構 v0.4、權限審查 v0.2 彙整。若有衝突，以最新 API 規格及安全決議為準；未決事項不得自行猜測。

## 1. 開發範圍

第一階段只建立以下五支 Edge Functions 與五個對應 public RPC：

| Edge Function | RPC | 用途 |
|---|---|---|
| `maintenance-status` | `maintenance_status_public` | 公開維護狀態 |
| `maintenance-admin-list` | `maintenance_admin_list` | 管理員查詢事件 |
| `maintenance-event-create` | `maintenance_event_create` | 建立事件 |
| `maintenance-event-update` | `maintenance_event_update` | 修改事件 |
| `maintenance-event-action` | `maintenance_event_action` | 排程、取消、完成 |

本階段不包含前端維護遮罩整合、管理介面 UI、緊急復原工具或正式部署。

## 2. 共通 Edge Function 執行流程

### 2.1 請求處理順序

1. 檢查 HTTP method 與必要 headers。
2. 處理 CORS preflight；只允許正式網站所需的明確 origin，不使用任意 origin 通配搭配 credentials。
3. 解析並驗證 JSON；拒絕無效 JSON、非 object payload、未知欄位及超出大小限制的 body。
4. 管理端點取得 Authorization bearer token，透過 Supabase Auth `getUser(token)` 驗證有效使用者。
5. 使用 publishable/anon key 建立 Supabase client，並將原始使用者 bearer token 傳入 RPC request。
6. 呼叫唯一對應的 RPC；不得由 Edge Function 分拆多個 table CRUD 來模擬交易。
7. 將 RPC 結果轉換成固定 JSON response。
8. 將可預期錯誤映射為規格中的 HTTP status/code；未知錯誤只回傳通用 500，不輸出 stack trace、SQL、schema 或 secret。

### 2.2 共通禁止事項

- 不得在 Edge Function 使用 service_role 代表使用者呼叫管理 RPC。
- 不接受 client 提供的 actor_id、user_id、role、isAdmin 或 email 作為授權依據。
- 不在 log 記錄 bearer token、API key、完整敏感 request body 或 internal_note。
- 不把管理員檢查只放在 Edge Function；資料庫 RPC 必須再次授權。
- 不自行重試非冪等寫入；寫入重送必須沿用相同 idempotency key。
- 不回傳 Postgres 原始錯誤訊息。

### 2.3 回應格式

成功：
```json
{ "ok": true, "data": {} }
```

失敗：
```json
{ "ok": false, "error": { "code": "FORBIDDEN", "message": "無權執行此操作" } }
```

回應必須設定適當的 JSON content type；CORS headers 依核准 origin 清單設定。

## 3. 各 Edge Function 契約

### 3.1 maintenance-status

- 認證：允許匿名；若提供 bearer token，驗證後可供資料庫判斷 admin_bypass 顯示狀態。
- API gateway：匿名端點需設定 `verify_jwt=false`，函式仍須自行安全處理可選 bearer token；不得把可選 token 當成管理授權。
- RPC：只呼叫 `maintenance_status_public`。
- 輸入：可選 scope；必須是七個已定義 code 之一。無 scope 時只查全站狀態。
- 輸出：僅 API 規格 4.1 列出的公開白名單欄位。
- 禁止：任何管理寫入、audit 查詢、internal_note 或 actor 資料回傳。
- 注意：anon private schema USAGE/SELECT + RLS 尚未完成真實測試；測試未通過不得核准 migration。

### 3.2 maintenance-admin-list

- 認證：有效使用者 JWT；`verify_jwt=true`。
- RPC：只呼叫 `maintenance_admin_list`。
- 輸入：status、scope、is_global、from、to、limit、cursor；limit 預設 20、最大 100。
- 輸出：管理事件清單、scope、status、version、created_at、updated_at、internal_note、next_cursor。
- 權限：RPC 內再次檢查 `auth.uid() IS NOT NULL AND public.is_admin()`。
- 非管理員：回 403，不得回傳任何事件內容。

### 3.3 maintenance-event-create

- 認證：有效使用者 JWT；`verify_jwt=true`。
- RPC：只呼叫 `maintenance_event_create`。
- 必填：title、message、is_global、scope_codes、starts_at、ends_at、status、reason、idempotency_key；internal_note 可空。
- status 僅允許 draft/scheduled。
- 輸入需驗證時間、scope/global 關係、欄位白名單與明確長度上限。
- RPC 交易負責衝突檢查、事件、scope links、audit、idempotency。
- 回傳 event_id、建立後摘要、version。
- 長度上限尚未定稿，未定稿前不可寫死成正式契約或開始 migration。

### 3.4 maintenance-event-update

- 認證：有效使用者 JWT；`verify_jwt=true`。
- RPC：只呼叫 `maintenance_event_update`。
- 必填：event_id、expected_version、reason、idempotency_key，以及至少一個允許更新的欄位。
- 允許更新欄位：title、message、internal_note、is_global、scope_codes、starts_at、ends_at。
- 拒絕 status、actor、audit、version 等受保護欄位；未知欄位回 400。
- RPC 重新驗證時間/scope、version 與排程衝突。
- 已開始事件不得一般修改排程時間或 scope；其他可否修改欄位依 API 規格保守限制。
- 回傳更新後摘要及新 version。

### 3.5 maintenance-event-action

- 認證：有效使用者 JWT；`verify_jwt=true`。
- RPC：只呼叫 `maintenance_event_action`。
- 必填：event_id、expected_version、action、reason、idempotency_key。
- 第一版 action 僅 schedule、cancel、complete。
- complete 僅在資料庫 server time 已達 ends_at 時允許。
- 不接受 start_now、extend、end_early。
- 回傳更新後事件摘要及新 version。

## 4. RPC 權限矩陣

| RPC | SECURITY | EXECUTE | Schema/table 權限 | RPC 內必要檢查 |
|---|---|---|---|---|
| maintenance_status_public | INVOKER | anon、authenticated | anon 僅最小 USAGE/SELECT；公開資料 RLS | scope 白名單、公開欄位白名單 |
| maintenance_admin_list | INVOKER | authenticated | 最小 SELECT + admin RLS | auth.uid 非空、is_admin |
| maintenance_event_create | INVOKER | authenticated | 最小 SELECT/INSERT + admin RLS | admin、輸入、衝突、idempotency |
| maintenance_event_update | INVOKER | authenticated | 最小 SELECT/UPDATE/必要關聯 DML + admin RLS | admin、version、衝突、欄位白名單 |
| maintenance_event_action | INVOKER | authenticated | 最小 SELECT/UPDATE/必要 audit/idempotency DML + admin RLS | admin、狀態轉換、version、idempotency |

所有新 RPC：
- 固定 `search_path = '')，schema/table/function 全限定。
- 建立後先撤銷 PUBLIC EXECUTE，再明確 GRANT。
- 管理 RPC 不授予 anon。
- 不授予 service_role 作為一般使用者操作途徑。
- private schema 不加入 Data API Exposed schemas。
- 每張 private table 啟用 RLS；實際 table grants 必須依 SQL 操作逐項核對，不可使用籠統的 ALL。

**重要限制：** SECURITY INVOKER 的必要 table grants 不會只對 RPC 內部生效。PostgreSQL grants/RLS 不辨識操作是否由 RPC 內部發出；private schema 不暴露於 PostgREST、RLS 與應用程式只提供受控 RPC 是共同安全邊界。不得宣稱 grants 單獨保證「只能透過 RPC」。

## 5. 錯誤映射

| 情況 | HTTP | code |
|---|---:|---|
| 無效 JSON、method、未知欄位 | 400 | INVALID_REQUEST |
| JWT 無效/過期/缺少 | 401 | UNAUTHENTICATED |
| 一般使用者執行管理操作 | 403 | FORBIDDEN |
| 事件不存在 | 404 | NOT_FOUND |
| 排程/狀態衝突 | 409 | CONFLICT |
| version 不符 | 409 | VERSION_CONFLICT |
| idempotency key 對應不同 payload | 409 | IDEMPOTENCY_KEY_REUSED |
| 業務欄位驗證失敗 | 422 | VALIDATION_ERROR |
| 請求頻率過高 | 429 | RATE_LIMITED |
| 未知錯誤 | 500 | INTERNAL_ERROR |

429 的實際限流機制與門檻尚未定稿；不得假設 Supabase Edge Function 自動提供專案所需的業務限流。第一版若未實作限流，文件與驗收不得宣稱此項已完成。

## 6. 測試矩陣

| 測試身分/情境 | status | admin-list | create/update/action |
|---|---|---|---|
| anon | 僅公開狀態 | 401/403 | 401/403 |
| 一般 authenticated | 公開狀態 | 403 | 403 |
| admin JWT | 公開狀態 + 可選 bypass 顯示 | 允許 | 依規則允許 |
| 偽造 actor_id/role | 不影響授權 | 不得提升權限 | 不得改變 audit actor |
| 過期/無效 JWT | 公開 status 可匿名；無效可選 token 不得產生 bypass | 401 | 401 |
| 重複 idempotency key + 同 payload | 不適用 | 不適用 | 回原結果 |
| 重複 key + 不同 payload | 不適用 | 不適用 | 409 |
| expected_version 過期 | 不適用 | 不適用 | 409 |
| 同時建立衝突排程 | 不適用 | 不適用 | 只能有一筆成功 |

測試必須使用 anon、一般 authenticated、admin 的真實測試 JWT，並在隔離環境執行。單元測試不能取代 JWT/RLS 整合測試。

## 7. 開發順序與停止條件

1. 定稿資料表欄位、scope seed、字元長度、audit/idempotency 保留期限與 lock key 策略。
2. 逐一將 RPC 操作轉成 table grants/RLS 矩陣；先做 SQL 靜態審查。
3. 在隔離環境驗證 anon/status、一般 user 拒絕、admin 允許與 private schema exposure。
4. 建立 RPC SQL 草稿並進行安全審查；未通過前不執行正式 Supabase。
5. 依序開發 status、admin-list、create、update、action Edge Functions。
6. 執行 Edge Function 單元測試、JWT/RLS 整合測試、交易/併發/idempotency 測試。
7. 最後才進行正式 migration/部署審核，需另行取得明確授權。

停止條件：
- anon 無法在不擴大資料暴露的前提下讀取公開狀態。
- admin helper 在真實 JWT 下行為不符。
- private schema/grants/RLS 權限邊界不清。
- audit 或 idempotency 無法在同一交易完成。
- 需要 service_role 冒充使用者或需要新增付費資源。
- 任何驗證只能靠正式資料庫試錯。

## 8. 舊 SQL 草案相容性提醒

專案附帶的第一步 SQL 審查筆記曾描述四張維護資料表，並以 service_role 作後端資料表權限配置。這與目前 v0.4/v0.5 決定的「使用者 JWT + SECURITY INVOKER RPC + private schema + RLS，不以 service_role 代表使用者」不是同一套存取模型。

因此該 SQL 草案只能作為歷史設計參考，**不得直接執行或視為已符合目前架構**。在進入 SQL 草稿前，必須先將其四表欄位、trigger、grant、RLS 與目前 API v0.5 的事件/scope/audit/idempotency 模型逐項對照，並記錄差異。不得只因先前曾審查過，就推定 SQL 可直接沿用。

## 9. 本文件未代表的事項

- 沒有建立 Edge Functions 或 RPC。
- 沒有執行 DDL/DML 或 migration。
- 沒有修改正式 Supabase。
- 沒有部署。
- 沒有建立付費資源。
- 沒有完成真實 JWT/RLS 整合測試。


## 10. 已建立的程式檔案（2026-11-08）

已在本分支建立：
- `supabase/functions/_shared/maintenance.ts`：共用 CORS、來源白名單、Auth token 驗證、JSON 驗證、輸入解析、RPC 呼叫與錯誤映射。
- `supabase/functions/maintenance-status/index.ts`
- `supabase/functions/maintenance-admin-list/index.ts`
- `supabase/functions/maintenance-event-create/index.ts`
- `supabase/functions/maintenance-event-update/index.ts`
- `supabase/functions/maintenance-event-action/index.ts`
- `supabase/config.toml)：status 關閉 gateway JWT 強制驗證，其他四支保持 JWT 驗證。
- `supabase/tests/functions/maintenance-validation.test.ts)：請求解析單元測試。
- `docs/maintenance-rpc-sql-contract-v0.1.md)：明確定義呼叫端使用 `p_request jsonb`。

### 尚未完成及阻擋項目

1. GitHub repo 目前讀取不到 `supabase/config.toml`、既有 Edge Functions 及 README；本次建立的是新設定檔，需在合併前確認不會覆蓋其他分支/本機設定。
2. 尚未取得原始 SQL migration 檔。先前上傳的 `啟動第一步檢查.txt` 是審查摘要，並非 SQL 原始碼；四張表實際欄位、constraint、trigger、RLS 與 grants 尚無法逐項核對。
3. 五個 RPC 尚未建立；Edge Functions 預期其 signature 為單一 `p_request jsonb`。需依實際 schema 編寫並審查 SQL。
4. 尚未執行 Deno type check 或 Deno tests；目前只有測試程式已提交，不能標示測試通過。
5. 尚未完成 anon/general-user/admin JWT、RLS、PostgREST、併發、transaction、idempotency 整合測試。
6. 沒有部署，也沒有修改正式 Supabase。

### 設定注意

- `MAINTENANCE_ALLOWED_ORIGINS` 可用逗號分隔正式網站 origin；目前預設只允許 `https://johnjohn114.github.io`。如網站正式 origin 不同，需在部署前明確設定。
- 需要既有 Supabase 環境變數 `SUPABASE_URL` 與 publishable key（優先 `SUPABASE_PUBLISHABLE_KEY`，相容 `SUPABASE_ANON_KEY` 或 `SUPABASE_PUBLISHABLE_KEYS` JSON）。
- 未使用 service_role，不新增付費服務或 secret。
