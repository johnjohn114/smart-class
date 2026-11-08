# Maintenance 四表 SQL 與目前 API/Edge 架構相容性審查 v0.1

> 日期：2026-11-08  
> 分支：`feature/maintenance-system`  
> 審查來源：`v26.11.7_maintenance_migration_review.sql`（320 行）與 `v26.11.7_maintenance_migration_revised(1).sql`（356 行）；目前 maintenance API v0.5 文件、connection architecture v0.4、RPC contract v0.1、五支 Edge Function。  
> 性質：唯讀靜態審查；不是 migration，不可直接執行。  
> 結論：**目前四表 SQL 與五表 API/Edge/RPC 設計不相容。不可生成或執行 RPC SQL，也不可部署現有 Edge Functions，直到資料模型與安全架構重新收斂。**

## 1. 已找回的來源檔案與版本差異

兩份原始來源均已在專案檔案庫找到：

- `v26.11.7_maintenance_migration_review.sql`：320 行。
- `v26.11.7_maintenance_migration_revised(1).sql`：356 行。

兩者都建立四張 `public` 資料表：
1. `public.maintenance_state`
2. `public.maintenance_events`
3. `public.maintenance_scopes`
4. `public.maintenance_audit_logs`

修訂版相對原始版的變更：
- 移除 `public.profiles` 與 `public.is_admin()` 的 precondition；仍保留 `public.announcements` precondition。
- `maintenance_set_updated_at()` 改用 `pg_catalog.now()`。
- 新增 `maintenance_state` 的 updated_at trigger。
- 新增 `maintenance_events` 防刪除 trigger。
- 新增三個 trigger functions 對 `PUBLIC`、`anon`、`authenticated` 的 EXECUTE revoke。
- 其餘四表欄位、索引、RLS 啟用與 service_role grants 主要結構相同。

## 2. 原始四表資料模型實際欄位

### 2.1 maintenance_state
- `id boolean` PK，default true，CHECK id=true（singleton）
- `global_enabled boolean` NOT NULL default false
- `current_global_event_id uuid`，FK → maintenance_events(id)，ON DELETE SET NULL
- `updated_at timestamptz` NOT NULL
- `updated_by uuid`，FK → auth.users(id)，ON DELETE SET NULL

### 2.2 maintenance_events
- `id uuid` PK
- `title text` NOT NULL
- `reason text`
- `mode text`：normal/emergency
- `scope_mode text`：all/selected
- `status text`：draft/scheduled/active/completed/cancelled
- `starts_at timestamptz`
- `expected_end_at timestamptz`
- `actual_started_at timestamptz`
- `actual_ended_at timestamptz`
- `background_path text`
- `announcement_id uuid` FK → public.announcements(id)，ON DELETE SET NULL
- `created_by uuid` FK → auth.users(id)，ON DELETE SET NULL
- `created_at`, `updated_at` timestamptz NOT NULL
- 兩個時間順序 CHECK constraints。

### 2.3 maintenance_scopes
- `id uuid` PK
- `event_id uuid` NOT NULL，FK → maintenance_events(id)，ON DELETE CASCADE
- `scope_key text`，CHECK 限定七個 key：home、announcements、competitions、products_orders、members、support、app_settings
- `enabled boolean` NOT NULL default true
- `message text`
- `created_at timestamptz`
- UNIQUE(event_id, scope_key)

注意：此表是「每個事件的範圍列」，不是全域 scope catalog。沒有獨立 scope directory 或 event_scope junction table。

### 2.4 maintenance_audit_logs
- `id uuid` PK
- `event_id uuid` nullable FK → maintenance_events(id)，ON DELETE RESTRICT
- `admin_id uuid`（沒有 FK）
- `action text` NOT NULL
- `reason text`
- `before_data jsonb`
- `after_data jsonb`
- `created_at timestamptz` NOT NULL

## 3. SQL 與目前 API/Edge 欄位不相容

| 現有 API/Edge | 四表 SQL | 判定 |
|---|---|---|
| `message` | events 無 message；僅 scopes.message | 不相容，語意與存放位置未定 |
| `internal_note` | 無此欄位 | 不相容 |
| `is_global` | `maintenance_state.global_enabled` + `events.scope_mode` | 不等價；事件本身沒有 is_global |
| `scope_codes` | `maintenance_scopes.scope_key` 每事件一列 | 需要重新定義轉換，且目前 API code 與 SQL key 不同 |
| `ends_at` | `expected_end_at` | 可能映射，但必須確認產品語意 |
| `expected_version` / `version` | 無 version 欄位 | 無法實作 optimistic concurrency |
| `idempotency_key` | 無 idempotency table/欄位 | 無法實作規格要求的 idempotency |
| `status` | SQL 額外允許 active | API 僅 draft/scheduled/cancelled/completed | 不相容 |
| `created_by` | SQL 有 created_by | 名稱可對應，但 API/DB actor 信任來源須統一 |
| `reason` | events.reason / audit.reason | 欄位有，但 API 把 reason 當每次寫入 audit 理由，需明確拆分 |
| `starts_at` | events.starts_at | 一致 |
| `event_id` | events.id | 可映射但命名不同 |

目前 Edge scope code：
`site_core`, `announcements_info`, `events_competitions`, `video_content`, `membership_growth`, `store_support`, `downloads_app`

原始 SQL scope keys：
`home`, `announcements`, `competitions`, `products_orders`, `members`, `support`, `app_settings`

這不是單純大小寫或命名差異；例如 SQL 沒有明確的 video_content 對應，也把網站首頁 home 與 site_core 的範圍邊界定義成不同概念。必須先核准 mapping 表，不能在 RPC 中猜測。

## 4. 表數與資料模型差異

目前 API/資料庫設計文件的五表模型：
- private.maintenance_scopes（全域 scope catalog）
- private.maintenance_events
- private.maintenance_event_scopes（多對多關聯）
- private.maintenance_audit_logs
- private.maintenance_idempotency

原始 SQL 四表模型：
- public.maintenance_state
- public.maintenance_events
- public.maintenance_scopes（每事件的 scope rows）
- public.maintenance_audit_logs

因此五表模型不能直接當成四表 SQL 的別名或正規化版本。其中特別是：
- 五表模型以 `events.is_global` 作全站旗標；四表模型以 singleton `maintenance_state.global_enabled/current_global_event_id` 搭配 event.scope_mode 表達。
- 五表模型的 scope catalog + event links，與四表模型的 event-scoped scopes table 不同。
- 五表模型新增 idempotency table 與 version 欄位概念；四表 SQL 沒有。
- 四表 SQL 有 mode、background_path、announcement_id、actual_started_at、actual_ended_at；目前 API/Edge 沒有完整承接這些欄位。

## 5. 安全架構重大衝突

### 5.1 schema / object location
四表 SQL 建立在 `public` schema。最新 connection architecture v0.4 要求維護資料表放在 `private` schema，且不加入 Data API Exposed schemas。

### 5.2 role / grants
四表 SQL：
- revoke anon/authenticated 對四張表所有權限。
- 對 service_role 授予 SELECT/UPDATE/INSERT/DELETE 等有限表權限。
- SQL 註解明確預期 Edge Functions 使用 service_role。

最新 connection architecture v0.4 與現有 Edge code：
- 使用者原始 bearer token + publishable/anon key 呼叫 SECURITY INVOKER RPC。
- RPC 內檢查 auth.uid() + public.is_admin()。
- 不使用 service_role 代表使用者。

兩者是不同信任模型，不能混搭。以目前 SQL grants，authenticated INVOKER RPC 沒有執行四表 DML 的 table grants；以目前 v0.4 architecture，service_role grants 不會幫助原始使用者 JWT 的 invoker RPC。

### 5.3 RLS
兩份 SQL 都只 ENABLE RLS，沒有建立任何 RLS policies。由於四表同時撤銷 anon/authenticated 權限，現狀並沒有可供 status RPC 的 anon read path，也沒有 authenticated invoker admin RPC 的 table access path。
若採 service_role，RLS 會被 bypass，資料庫授權責任就落到受信任 Edge Function；需另做嚴格的 admin 驗證和 actor 傳遞設計。不能把 v0.4 的 auth.uid()/is_admin() INVOKER 設計直接套在此 SQL 上。

### 5.4 Trigger function EXECUTE revoke
修訂版 revoke trigger functions 的 EXECUTE 權限。這項變更本身是合理的最小權限強化；trigger 仍由資料庫觸發器執行。但需在目標 PostgreSQL/Supabase 版本與實際 owner 情境測試後確認，不可只憑靜態審查視為已通過。

## 6. SQL 本身的審查觀察

### 已有的保護
- 四表皆啟用 RLS。
- anon/authenticated 沒有直接 table privileges。
- audit table 有 UPDATE/DELETE row trigger，並有 TRUNCATE statement trigger。
- 修訂版額外阻止 maintenance_events DELETE。
- state 使用 boolean singleton PK + CHECK true。
- events 時間順序有 CHECK。
- scopes 有 event/scope unique。
- audit event FK 使用 ON DELETE RESTRICT。

### 尚未包含或需補足
- 沒有 RLS policies（若採 service_role-only 路徑可有意不開 client policies，但 status 公開讀取需另外實作安全路徑）。
- 沒有公開 status RPC、admin list/create/update/action RPC。
- 沒有事件 version / optimistic concurrency。
- 沒有 idempotency storage。
- 沒有排程重疊保護或 transaction-scoped concurrency lock。
- 沒有對 scope_key 與七個產品功能 code 的核准 mapping。
- `maintenance_state.global_enabled/current_global_event_id` 與 events.status/時間窗的一致性尚未由 constraint/trigger/RPC 保證。
- `maintenance_state.updated_by` 沒有在這份 SQL 中看到可信 actor 寫入路徑。
- events 的 `created_by` 只在 INSERT 設定，沒有 updated_by 欄位。
- `CREATE TABLE IF NOT EXISTS` 不會校正已存在但欄位不同的 table；precondition 只檢查 announcements（修訂版），不檢查 announcements.id 型別、auth.users FK 可用性、既有同名 maintenance objects 的結構。
- 目前只有單純索引，沒有針對 active/scheduled 衝突檢查設計的索引/約束；具體索引需依採用的衝突模型設計。

## 7. 必須先決定的架構方向

不可在未決定前繼續寫 RPC SQL。兩條路徑：

### A. 保留四表 SQL 的原始設計方向
需重新設計 API/Edge：
- 保留四表 public schema，或另外制定安全搬遷到 private 的策略。
- 決定 Edge Function 是否使用 service_role。若使用，必須在 Edge Function 內以 Supabase Auth 驗證原始使用者，資料庫端不能假設 auth.uid() 代表原始使用者；actor 由已驗證的使用者身分可信地傳入受控 server-side 路徑。
- 為公開 status 設計獨立安全讀取方式；不能因 service_role 有權限就直接把高權限資料回傳。
- 將 API 欄位重定義為 SQL 真正支援的語意，補齊 version、idempotency、audit、排程交易與 scope mapping。
- 這會要求調整目前五支 Edge Function 與 connection architecture v0.4。

### B. 保留目前五表 private + user JWT + SECURITY INVOKER 架構
需正式設計新的 schema，而不是直接套用四表 SQL：
- 明確記錄與四表 SQL 的差異及資料遷移/相容決策。
- 決定是否保留 singleton maintenance_state，或由 events 即時計算全站狀態。
- 確認 scope catalog / event-scope links / idempotency / version。
- 需提供 authenticated invoker 所需的最小 grants/RLS，並驗證 anon status 的最小讀取權限。
- 此方向偏離原始 SQL 的四表模型，必須明確核准設計變更。

## 8. 本輪結論與未執行事項

- 兩份 SQL 已完整讀取並完成靜態差異及 API/Edge 相容性審查。
- **目前判定：不相容，禁止進入可部署 RPC SQL。**
- 尚未修改兩份原始 SQL。
- 尚未修改 Edge Function source。
- 尚未執行 SQL parse / Deno tests / JWT-RLS integration tests。
- 未執行任何 Supabase DDL/DML、migration、repair、deployment。
- 未新增 secret、付費資源或 Supabase project。
- 完整 PostgreSQL restore test 仍依先前專案決策跳過，不能標記為通過。

## 9. 建議下一個工作項目

先建立一份「四表 SQL vs 五表架構」決策記錄，採用一條路徑後，再同步修訂 API spec、connection architecture、RPC contract、Edge Functions。建議在不擴大付費與正式資料庫風險的前提下，優先評估 **保留目前 user JWT + SECURITY INVOKER 的安全原則，再依原始四表功能需求調整 schema**；但此建議不是已獲核准的架構決策。
