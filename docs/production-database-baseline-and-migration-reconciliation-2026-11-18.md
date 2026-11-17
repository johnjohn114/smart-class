# 正式資料庫基準與 Migration 衝突盤點（2026-11-18）

> 本文件是唯讀盤點紀錄，不是 Migration，也不授權執行任何 SQL、部署或合併。
> 盤點只讀取 PostgreSQL 系統目錄與 GitHub 分支中的 SQL/config 檔案；未讀取或匯出正式使用者資料列。

## 1. 本次正式資料庫基準

| 項目 | 唯讀查詢結果 |
|---|---:|
| public 資料表（普通／分割） | 44 |
| 已啟用 RLS 的 public 資料表 | 44 / 44 |
| 強制 RLS（FORCE ROW LEVEL SECURITY） | 0 |
| public RLS policies | 98 |
| public 非內部 triggers | 7 |
| public functions | 38 |
| public SECURITY DEFINER functions | 36 |
| public ordinary views | 1 |
| `supabase_migrations` schema 內資料表 | 0 |
| `private` schema | 不存在 |

### 解讀限制

- 查不到 `supabase_migrations` schema/table，只能表示本次檢查的標準 Supabase migration history 位置沒有紀錄；不能據此推斷從未執行過 SQL，也不能確認是否使用其他追蹤機制。
- RLS 已啟用不等於每張表都已強制 RLS；本次 FORCE RLS 數量為 0。
- 以上為結構與權限盤點，不代表所有政策、函式邏輯或應用程式流程均已通過安全測試。

## 2. Repository Migration 與正式資料庫比對

### 2.1 App releases：兩份 migration 定義衝突

| 檔案 | 內容特徵 | 正式資料庫比對 |
|---|---|---|
| `202610310001_app_releases.sql` | 含 `created_by`、`version_code UNIQUE`、五項命名 policies；沒有 `is_latest` | 現有欄位與 policy 名稱大致吻合 |
| `20261031_app_releases.sql` | 另含 `is_latest`、HTTPS constraint、`app_releases_published_idx`、`is_app_release_admin()` | 正式資料庫沒有 `is_latest`、該 index 或 helper function |

**結論：** 兩份檔案都建立 `public.app_releases`，但欄位、限制條件、索引及政策策略不同。不能把兩份檔案當成可直接依序執行的獨立 migration。第一份與現況較吻合，但僅憑結構相似仍不能證明它的執行來源或時間。第二份應先查明歷史用途，再決定保留、合併或標記為過時；目前不做修改。

### 2.2 Calendar fields

檔案：`26.11.3_calendar_fields.sql`

正式資料庫已存在：
- `event_date`
- `event_end_date`
- `event_date_source`
- `event_date_confirmed`
- `announcements_event_date_source_check`
- `announcements_event_date_range_check`
- `announcements_calendar_event_date_idx`

**結論：** 目標結構吻合；沒有 migration history，不能證明是由這個檔案套用。

### 2.3 Growth function authorization hardening

檔案：`202611160001_growth_function_authorization_hardening.sql`

- 正式資料庫存在多個該檔案涉及的成長系統函式。
- 檔案預期建立的 `_refresh_growth_level_internal(uuid)` 在本次檢查結果中不存在。
- 對若干關鍵函式，正式資料庫 ACL 仍明確列有 `anon=X`，包括 `admin_delete_growth_reward`、`admin_upsert_growth_reward`、`award_growth_points`、`check_growth_achievements`、`complete_growth_task`、`refresh_growth_level` 等；其中 `award_growth_points` 對 authenticated 為 false，但 anon 仍有 EXECUTE。
- `check_activity_badges` 的 ACL 仍包含 PUBLIC EXECUTE（ACL 中的空 grantee）。

**結論：** 目前 ACL 與該 migration 的撤銷 anon/PUBLIC 權限目標不一致，不能視為已完整套用。這是權限風險盤點結果，不代表已證實可由未登入者成功執行某項操作；函式內部驗證仍需另外審查。不要直接重跑整份 migration，應先逐一核對函式定義、呼叫端與允許清單。

### 2.4 Default privileges and trigger hardening

檔案：`202611170001_default_privileges_and_trigger_hardening.sql`

正式資料庫目前 `postgres` 的 public default privileges 仍顯示：
- tables：anon、authenticated、service_role 有廣泛權限
- sequences：anon、authenticated、service_role 有廣泛權限
- functions：anon、authenticated、service_role 有 EXECUTE

另外，本次檢查到的五組既有觸發器仍存在且啟用，但這只能證明觸發器存在，不能證明此 migration 的函式定義及撤權語句曾完整執行。

**結論：** 正式資料庫 default ACL 與此 migration 的預期收緊方向不一致。此 migration 影響未來建立物件的預設權限，範圍較廣；在核對現有應用程式、Edge Functions、部署流程與所有需要的角色權限前，不應直接執行。

### 2.5 Maintenance system initial

檔案：`20261117121103_maintenance_system_initial.sql`

- 此檔案建立 `private` schema、六張 `private.maintenance_*` 資料表、相關 policies、triggers 及五個 public RPC。
- 正式資料庫目前沒有 `private` schema，也查不到該組維護資料表及 RPC。

**結論：** 正式資料庫尚未呈現這份 migration 所建立的結構；目前不得假設維護系統已上線。

## 3. 上傳的啟動檢查文件與 PR migration 不同

上傳文件《啟動第一步檢查.txt》記載的是另一版維護系統草案，使用 `maintenance_state`、`maintenance_events`、`maintenance_scopes`、`maintenance_audit_logs` 等設計方向；PR migration 則採用 `private.maintenance_scopes`、`private.maintenance_events`、`private.maintenance_event_private_notes`、`private.maintenance_event_scopes`、`private.maintenance_audit_logs`、`private.maintenance_idempotency`。

兩者不是同一份 schema。後續若要做維護系統，必須先指定唯一採用版本，逐項核對前端、Edge Functions、RPC 及資料表契約；不可把兩份 SQL 拼接執行。

## 4. Migration 衝突處理清單

| 項目 | 目前處置 |
|---|---|
| 兩份 app_releases migration | 標記衝突；查明歷史後再決定唯一有效版本 |
| Calendar fields | 標記為結構已存在、來源未證實 |
| Growth hardening | 標記為部分物件存在但 ACL 不吻合；禁止直接重跑 |
| Default privileges hardening | 標記為正式 DB 尚未呈現預期撤權；需完整影響評估 |
| Maintenance initial | 標記為正式 DB 未呈現目標 schema；先決定採用哪一版設計 |
| Migration history | 先確認專案實際使用的 migration 管理方式與權威紀錄 |

## 5. 下一步安全門檻

在任何正式 SQL 執行前，至少完成：

1. 從 Supabase Dashboard/CLI 專案設定確認實際 migration history 管理方式；不得只依 Git 檔名猜測。
2. 為每個 migration 建立「預期變更、目前狀態、來源證據、是否可重複執行、回復方式」對照表。
3. 先處理兩份 app_releases 定義衝突，並確認實際前端依賴的欄位。
4. Growth/default ACL 先做函式逐一盤點及呼叫端相容性測試；不可用廣泛授權或整包撤權作為捷徑。
5. Maintenance 先選定唯一 schema 版本，並核對 Edge Function 設定與前端契約。
6. 完成 staging 測試、備份與回復演練後，才另行提出正式環境執行計畫。

## 6. 本次操作界線

- 本次只有讀取 GitHub 檔案與 PostgreSQL 系統目錄。
- 沒有新增、修改或刪除正式資料庫物件或資料列。
- 沒有執行 migration、部署 Edge Function、發布網站或合併 PR。
- 本文件只記錄本次查詢時點的觀察結果；正式執行前必須重新盤點。
