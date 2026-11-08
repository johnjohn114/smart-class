# Maintenance SQL 與 API v0.5 相容性盤點 v0.2

> 日期：2026-11-08  
> 分支：`feature/maintenance-system`  
> 性質：依目前可讀取的附件、設計文件、API 規格及 Edge Function 程式進行靜態交叉盤點；不是 Migration，不可執行。  
> 結論：原始 SQL 仍未取得；但 repository 內已有較完整的五表資料模型設計，足以先完成介面需求盤點。

## 0. v0.1 更正紀錄

前版盤點有兩項錯誤，這裡正式更正：

1. 使用者附件 `啟動第一步檢查.txt` 只有「四張資料表」的概括描述，**沒有列出四張表的名稱，也沒有 SQL 原始碼**。前版稱附件列出 `maintenance_state`、`maintenance_events`、`maintenance_scopes`、`maintenance_audit_logs`，沒有來源依據，該清單作廢。
2. Repository 的資料庫設計 v0.1～v0.3 實際描述的是**五張核心資料表**，而非前版所稱的四張表；沒有 `maintenance_state`。全站控制由 `maintenance_events.is_global` 表示。

## 1. 本輪實際可讀取來源

- 使用者附件：`啟動第一步檢查.txt`（62 行、2,839 bytes），內容是先前審查摘要，不是 SQL。
- `docs/maintenance-database-design-v0.1.md`
- `docs/maintenance-database-design-v0.2.md`
- `docs/maintenance-database-design-v0.3.md`
- `docs/maintenance-api-spec-v0.4.md`（文件內標題為 API v0.5）
- `docs/maintenance-connection-architecture-v0.4.md`
- `docs/maintenance-permission-rpc-security-review-v0.2.md`
- `docs/maintenance-rpc-sql-contract-v0.1.md`
- 五支 Edge Function 及共用驗證程式。

Repository 的 `supabase/migrations/` 目前只列出三個既有、與 maintenance 無關的 migration；沒有 maintenance migration。

## 2. 目前設計文件採用的五表模型

| 資料表 | 主要責任 | API/Edge 對應 |
|---|---|---|
| `private.maintenance_scopes` | 七個維護範圍目錄 | scope code/name |
| `private.maintenance_events` | 事件主檔、全站旗標、狀態、時間、version | create/list/update/action/status |
| `private.maintenance_event_scopes` | 事件與 scope 的多對多關聯 | API 的 `scope_codes` 由 RPC 轉成關聯列 |
| `private.maintenance_audit_logs` | 操作稽核、before/after、actor、reason | create/update/action 同交易寫入 |
| `private.maintenance_idempotency` | 重複請求保護 | create/update/action 的 `idempotency_key` |

全站維護不是獨立的 `maintenance_state` table，也不是第八個 scope；使用 `maintenance_events.is_global`。全站事件不應建立 scope links；局部事件至少要有一個有效 scope。

## 3. 欄位與 API/Edge 介面交叉核對

| API/Edge 欄位或規則 | 資料模型對應 | 盤點結果 |
|---|---|---|
| `title`, `message`, `internal_note` | events 同名欄位 | 名稱一致；長度限制仍是暫定值 |
| `is_global` | events.is_global | 一致 |
| `scope_codes` | scopes.code + event_scopes | 需要 RPC 做 code lookup 與關聯列交易寫入 |
| `starts_at`, `ends_at` | events 同名欄位 | v0.2/v0.3 設計與 Edge 程式一致 |
| `status` | events.status | 目前四值：draft/scheduled/cancelled/completed |
| `expected_version` | events.version | RPC 必須讀取並比對，再原子遞增 |
| `created_by`, `updated_by` | events actor 欄位 | 必須由資料庫身分上下文取得，不接受前端 actor |
| `idempotency_key` | idempotency.actor_id/key | actor 由 auth.uid()；request hash 應由可信伺服器端正規化計算 |
| audit `request_id` | audit_logs.request_id NOT NULL | Edge request 不接受 request_id；RPC 必須自行產生或由可信層產生 |
| admin list `from`, `to`, `limit`, `cursor` | events 查詢 | limit 有 1–100 驗證；cursor 的排序鍵、編碼及穩定分頁規則尚未定義 |
| status response whitelist | events + scopes | RPC 必須明確挑選公開欄位，不能回傳 internal_note/actor/audit/idempotency |

### 3.1 更新請求的必要 RPC 行為

Edge Function 的 update parser 接受部分欄位更新。當 request 只改 `is_global`、`scope_codes`、`starts_at` 或 `ends_at` 其中一部分時，Edge parser 無法單獨驗證資料庫原值。

因此 RPC 必須在同一交易內：
1. 以 `event_id` 讀取目前事件及 scope links。
2. 合併 patch 與現有值。
3. 對合併後的最終資料驗證全站/局部規則、時間先後、scope 啟用狀態及衝突。
4. 比對 `expected_version`，成功後才更新 version。
5. 寫入 audit 與 idempotency 結果。

若只驗證 request 中同時出現的欄位，會讓單欄位 patch 可能破壞既有資料一致性。

### 3.2 排程與狀態機

資料庫交易函式必須統一處理 create/update/schedule，並在同一交易中完成鎖定、衝突檢查、event/scope 寫入、audit、idempotency。Edge Function 先查再寫不能防止併發穿透。

目前 Edge action 只接受 `schedule`、`cancel`、`complete`；RPC 必須落實狀態轉換及終態限制。scheduled 是否正在維護由伺服器時間與 `[starts_at, ends_at)` 計算，不應另造可手動修改的 active 狀態。

## 4. 連線及權限決議（以較新文件為準）

資料庫設計 v0.3 的 SUPABASE_DB_URL + Postgres driver 方案已被 connection architecture v0.4 取代，不得沿用舊方案。

目前應採：
- private schema，不加入 Data API Exposed schemas。
- public RPC + SECURITY INVOKER + 固定空 search_path + 全限定名稱。
- Edge Function 使用原始使用者 bearer token 與 publishable/anon key 呼叫 RPC；不可使用 service_role 代表使用者。
- 管理 RPC 內再次檢查 `auth.uid() IS NOT NULL AND public.is_admin()`。
- status RPC 可授予 anon/authenticated EXECUTE；anon 只取得必要 schema USAGE/SELECT 並由 RLS 限定公開狀態列。
- 管理 RPC 僅 authenticated EXECUTE，並授予 invoker 實際需要的最小 table privileges + RLS。
- audit 不授予一般 UPDATE/DELETE；但 PostgreSQL grants/RLS 不能辨識 table 操作是否來自 RPC 內部，不能宣稱絕對禁止 authenticated 直接 INSERT。

## 5. Edge Function 靜態核對結果

已讀取五個 entrypoint 與共用程式，靜態確認：
- 五支 function 分別呼叫五個契約 RPC。
- 所有 RPC request 使用單一 `p_request` JSONB body。
- 管理端點要求 bearer token，轉送同一 token；程式碼未使用 service_role。
- status endpoint 允許匿名，選用有效 bearer token 時才把 token 傳給 RPC。
- scope code 白名單與 API 七個代碼一致。
- create/update/action 的欄位白名單、UUID、ISO 時間與基本型別驗證已存在。
- update parser 對 patch 合併後的最終狀態仍依賴 RPC 驗證（見 3.1）。

這是靜態程式碼閱讀，不代表 Deno runtime、Supabase Auth、PostgREST、JWT/RLS 或 RPC 整合測試已通過。現有 Deno tests 尚未在本輪執行；目前執行環境沒有 Deno CLI。

## 6. 尚未能完成的比對／阻擋項目

| 項目 | 目前證據 | 結果 |
|---|---|---|
| 使用者提及的原始四表 SQL | 附件只有摘要，沒有 SQL | 阻擋：無法逐欄位審查或直接修補 |
| 原始 SQL 的實際表數及表名 | 附件沒有列名；設計文件列五表 | 需使用者原始 SQL 才能確認四表版本來源 |
| PK/FK/CHECK/UNIQUE/index | 設計文件有建議，無實際 SQL | 未核實 |
| RLS policies / grants / triggers | 附件只有摘要敘述，無 SQL | 未核實 |
| 五個 RPC function body | 目前只有呼叫契約，無 SQL body | 尚未實作 |
| admin list cursor contract | 僅有 cursor 欄位 | 待定 |
| 欄位長度限制 | Edge 程式有暫定 200/4000/500 | 不可視為正式定稿 |
| 真實 anon/user/admin JWT + RLS | 無隔離整合測試 | 未測 |
| Deno tests | 有測試檔，但無 Deno CLI | 未執行 |

## 7. 下一個安全可執行步驟

1. 找回原始 `v26.11.7_maintenance_migration_review.sql`，或由使用者重新上傳。沒有它就不能聲稱完成「原始四表 SQL」逐欄位核對。
2. 將資料模型收斂為五表設計（若原始 SQL 證明實際是四表，需先逐項說明差異，不直接套用）。
3. 定義 admin-list cursor、長度上限、狀態轉換及 audit request_id 產生方式。
4. 再撰寫五個 RPC SQL 草案，完成靜態 parse 與測試。
5. 在隔離環境測試 anon/authenticated/admin JWT、RLS、PostgREST、交易、併發與 idempotency。

本輪沒有執行任何 Supabase DDL/DML、migration、repair、deployment，也沒有新增付費資源。
