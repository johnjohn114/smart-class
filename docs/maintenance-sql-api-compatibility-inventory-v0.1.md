# Maintenance SQL 與 API/Edge 相容性盤點 v0.3

> 日期：2026-11-08  
> 分支：`feature/maintenance-system`  
> 性質：依實際找回的兩份 SQL、目前 API/Edge 程式與架構文件進行靜態盤點；不是 Migration，不可執行。  
> 最新結論：**原始 SQL 是四表 public + service_role 模型；目前 API/Edge 是五表 private + user JWT/SECURITY INVOKER 模型。兩者不相容。以本文件與 `maintenance-four-table-sql-compatibility-review-v0.1.md` 為準，取代 v0.2 中「原始 SQL 未取得」及「五表模型已足以代表原始設計」等錯誤結論。**

## 0. v0.3 重要更正

v0.2 盤點時尚未找回原始 SQL，因此錯誤地把 repository 的五表設計當成唯一可用模型，並稱原始 SQL 未取得。現在已在 ChatGPT 專案檔案庫找到並完整讀取兩份 SQL：

- `v26.11.7_maintenance_migration_review.sql`：320 行、10,833 bytes。
- `v26.11.7_maintenance_migration_revised(1).sql`：356 行、12,091 bytes。

原始 SQL 明確建立四張 public tables：`maintenance_state`、`maintenance_events`、`maintenance_scopes`、`maintenance_audit_logs`。因此 v0.2 第 2 節所列五表模型只能代表後續 API/架構文件的設計，不能說成原始 SQL 的既定資料模型。

## 1. 兩份 SQL 來源與修訂差異

兩份 SQL 都建立四張 public tables，主要欄位及 FK 結構相同。修訂版相對原始版：
- 移除 `public.profiles` 與 `public.is_admin()` precondition；保留 `public.announcements` precondition。
- updated_at function 改用 `pg_catalog.now()`。
- 增加 `maintenance_state` updated_at trigger。
- 增加阻止刪除 `maintenance_events` 的 trigger。
- 對三個 trigger functions 撤銷 PUBLIC、anon、authenticated EXECUTE。
- 兩版均啟用四表 RLS，均撤銷 anon/authenticated table privileges，均授予 service_role 指定表權限。
- 兩版均沒有建立 RLS policies、API RPC 或 idempotency table。

## 2. 原始四表模型

| 表 | 核心內容 |
|---|---|
| `public.maintenance_state` | singleton boolean id、global_enabled、current_global_event_id、updated_at、updated_by |
| `public.maintenance_events` | title、reason、mode(normal/emergency)、scope_mode(all/selected)、status(draft/scheduled/active/completed/cancelled)、starts_at、expected_end_at、actual_started_at、actual_ended_at、background_path、announcement_id、created_by、created_at、updated_at |
| `public.maintenance_scopes` | event_id、scope_key、enabled、message、created_at；UNIQUE(event_id,scope_key) |
| `public.maintenance_audit_logs` | event_id、admin_id、action、reason、before_data、after_data、created_at |

原始 SQL scope keys：`home`、`announcements`、`competitions`、`products_orders`、`members`、`support`、`app_settings`。此 `maintenance_scopes` 是每事件範圍列，不是全域 scope catalog。

## 3. 目前 API/Edge 五表模型

目前 API/Edge 設計文件預期：
- private.maintenance_scopes：全域 scope catalog
- private.maintenance_events：事件主檔，含 is_global、version 等
- private.maintenance_event_scopes：事件與範圍連結
- private.maintenance_audit_logs：操作稽核
- private.maintenance_idempotency：重複請求保護

五表模型與四表 SQL 的差異：
- 五表以 events.is_global 表達全站維護；四表以 maintenance_state.global_enabled/current_global_event_id 搭配 events.scope_mode。
- 五表拆成 scope catalog + event links；四表以每事件 scope rows 儲存。
- 五表有 version/idempotency 設計；四表沒有 version 欄位或 idempotency table。
- 四表有 mode、background_path、announcement_id、actual_started_at、actual_ended_at；目前 API/Edge 沒有完整承接。
- API 的 scope codes（site_core 等）與 SQL scope keys（home 等）不同，沒有已核准 mapping。

## 4. 目前 API/Edge 欄位相容性

| API/Edge | 原始 SQL | 結果 |
|---|---|---|
| message | events 無此欄位，僅 scopes.message | 不相容，語意與存放位置未定 |
| internal_note | 無 | 不相容 |
| is_global | state.global_enabled + events.scope_mode | 不等價 |
| scope_codes | 每事件多列 scopes.scope_key | 需定義 mapping 與轉換 |
| ends_at | expected_end_at | 可能映射，需確認語意 |
| expected_version/version | 無 | 無法實作 optimistic concurrency |
| idempotency_key | 無 idempotency storage | 無法實作冪等 |
| status | SQL 允許 active | Edge list parser 只接受 draft/scheduled/cancelled/completed |
| reason | events.reason 與 audit.reason | 必須拆清事件原因與每次操作 audit reason |
| starts_at | starts_at | 一致 |
| event_id | events.id | 可映射，名稱不同 |

此外，Edge update parser 支援 partial patch。RPC 必須在同一交易內讀取舊資料、合併 patch、驗證最終狀態、檢查 expected_version，再更新事件、audit 與 idempotency；不能只驗證 request 同時帶入的欄位。

## 5. 權限架構重大衝突

### 四表 SQL 的模型
- tables 位於 public schema。
- anon/authenticated 對四表 revoke all。
- service_role 取得 state select/update、events select/insert/update、scopes select/insert/update/delete、audit select/insert。
- SQL 註解預期 Phase 2 Edge Functions 使用 service_role。
- RLS enabled，但沒有 policies。

### 最新 connection architecture v0.4 / Edge code 的模型
- tables 放 private schema，不加入 Data API Exposed schemas。
- Edge Function 轉送原始使用者 bearer token + publishable/anon key。
- public RPC 使用 SECURITY INVOKER。
- 管理 RPC 內檢查 auth.uid() + public.is_admin()。
- 不使用 service_role 代表使用者。
- invoker RPC 需呼叫角色具備實際最低 table grants 並受 RLS 約束。

這兩種模型不能直接混搭。四表 SQL 的 grants 不會讓 authenticated user JWT 的 SECURITY INVOKER RPC 自動擁有資料表權限；而若改用 service_role，資料庫端 auth.uid() 不會自然代表原始使用者，actor 信任與管理員授權必須另行設計。

## 6. SQL 靜態審查結果

已有：
- 四表皆 ENABLE ROW LEVEL SECURITY。
- anon/authenticated 沒有直接 table privileges。
- audit UPDATE/DELETE row trigger 與 TRUNCATE statement trigger。
- 修訂版額外阻止 events DELETE。
- events 時間順序 CHECK。
- scopes UNIQUE(event_id,scope_key)。
- audit event FK ON DELETE RESTRICT。

未包含或尚未解決：
- status/admin list/create/update/action RPC。
- anon status read path 與任何 RLS policies。
- authenticated invoker admin read/write policies/grants。
- event version / optimistic concurrency。
- idempotency storage。
- 排程重疊的併發保護。
- scope mapping。
- maintenance_state 與 events 狀態一致性保證。
- actor 可信寫入流程。
- 完整 precondition 檢查；CREATE TABLE IF NOT EXISTS 不會校正既有同名表的欄位結構。

## 7. 目前可確認的 Edge 程式狀態

靜態閱讀已確認：
- 五支 Edge entrypoints 呼叫五個 RPC 名稱。
- RPC request 使用單一 p_request JSONB body。
- 管理端點要求 bearer token 並將原始 token 傳給 RPC；共用程式未使用 service_role。
- status 允許匿名。
- Edge scope code 與 API 七個代碼一致，但與 SQL scope keys 不同。
- create/update/action 有基本欄位、UUID、ISO 時間驗證。
- update 的 patch 合併後驗證必須由 RPC 完成。

這些是靜態檢視結果，不代表 Deno、Auth、PostgREST、JWT/RLS 或 RPC 整合測試通過。五個 RPC SQL body 尚不存在；Edge tests 尚未執行。

## 8. 架構收斂前的阻擋決策

目前不可直接寫 RPC SQL。必須先明確選定並同步所有文件/程式：

**方向 A：保留四表 SQL 功能模型。** 需重設 API/Edge 與身份信任模型，決定是否保留 public schema/service_role，並設計安全 status read path、actor 傳遞、version/idempotency、scope mapping 與交易鎖定。

**方向 B：保留 user JWT + SECURITY INVOKER 原則。** 需正式設計與四表 SQL 不同的新 schema（可考慮保留 singleton state 或明確替代它），補齊 version/idempotency/scope mapping，並為 invoker RPC 設計最小 grants/RLS。這是對原始 SQL 的架構變更，必須在文件中明確記錄。

目前較安全的建議是優先保留 v0.4 的 user JWT + invoker 安全原則，再設計能滿足原始四表產品需求的 schema；但這只是建議，不是已核准決策。

## 9. 本輪未執行事項

- 沒有修改兩份來源 SQL。
- 沒有修改 Edge Function source。
- 沒有執行 Supabase DDL/DML、migration、repair 或 deployment。
- 沒有建立 RPC/private schema/table 或新增 secret。
- 沒有建立付費資源或新 Supabase project。
- 沒有執行 Deno/JWT/RLS/isolated restore tests。
- 完整 PostgreSQL restore test 依使用者先前決定跳過，不得標示通過。

詳細欄位、FK、trigger 與差異說明另見 `docs/maintenance-four-table-sql-compatibility-review-v0.1.md`。
