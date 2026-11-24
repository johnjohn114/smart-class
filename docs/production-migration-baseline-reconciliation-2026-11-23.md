# 正式資料庫基準與 Migration 衝突盤點（2026-11-23）

> 性質：唯讀盤點更新與後續工作清單；不是 Migration，不授權執行 SQL、部署或合併。
> 基準分支：`main`（檢查時 HEAD：`b18a3a05737af89c4d66f5c4c7835220a334469d`）
> Supabase project ref：`fsoowongtavlsrwvzbze`
> 本文件只記錄結構、權限、GitHub 檔案與既有測試證據；沒有讀取或匯出正式使用者資料列。

## 1. 執行摘要

**正式資料庫 Migration 執行狀態：BLOCKED。**

本次沿用既有正式 DB 唯讀基準，並重新核對目前 `main` 的 migration 檔案、App Releases 前後端欄位依賴，以及 Maintenance 的設計決策文件。

- 正式資料庫仍未建立／未確認應用程式 migration history；既有紀錄指出標準 migration 清單為空，`supabase_migrations` schema 不存在。這不代表資料庫沒有既存物件，也不能證明歷史上從未手動執行 SQL。
- 既有結構盤點：public 44 張表、44/44 啟用 RLS、0 張 FORCE RLS、98 個 RLS policies、7 個非內部 triggers、38 個 public functions（其中 36 個 SECURITY DEFINER）、1 個 ordinary view。這是既有唯讀快照，不是本次重新執行的即時完整 dump。
- 目前六個 migration 檔案不可視為一條可直接依序套用的安全鏈。
- Maintenance 目標採六張 `private` tables、五個 public RPC、使用者 JWT + SECURITY INVOKER 的設計；正式 DB 尚無 `private` schema 或 Maintenance objects。
- 不執行 DDL/DML、migration repair、db push、Edge Function deploy 或正式網站部署；不建立 Supabase 付費分支／專案。

## 2. Repository migration inventory（main）

| 檔案 | 目前證據／分類 | 安全處置 |
|---|---|---|
| `202610310001_app_releases.sql` | 與正式 `app_releases` 目前欄位形狀及已記錄的五項 policies 相符；前後端程式使用 `created_by`，不依賴 `is_latest` | 保留為現況相容候選；不能只憑結構吻合就標記為已套用 |
| `20261031_app_releases.sql` | 同名表的另一套定義；含 `is_latest`、HTTPS constraint、複合 index 與 `is_app_release_admin()`；與正式欄位及目前前端 payload 不一致 | 衝突檔，不可在目前正式 DB 當成下一個 migration 執行；查明其他環境用途前不要刪除 |
| `26.11.3_calendar_fields.sql` | 正式 `announcements` 的四個 calendar 欄位、兩個 CHECK 與 partial index 已在既有唯讀盤點中確認吻合 | 結構吻合候選；執行來源未證實，不可逕自 repair |
| `202611160001_growth_function_authorization_hardening.sql` | 候選權限修補；正式 DB ACL 與目標仍不一致，且預期 helper `_refresh_growth_level_internal(uuid)` 未見於既有盤點 | 僅限隔離測試；不可整份直接套用正式 DB |
| `202611170001_default_privileges_and_trigger_hardening.sql` | 候選 default ACL／trigger hardening；既有正式 DB 的 postgres public default privileges 仍廣泛授予 API roles | 僅限隔離測試；先完成所有受影響呼叫端與未來物件授權分析 |
| `20261117121103_maintenance_system_initial.sql` | 六表 private Maintenance 初始 migration；正式 DB 既有盤點未見 private schema、Maintenance tables 或 RPC | 尚未部署；不可執行，先完成架構契約、隔離測試及 migration baseline |

### 2.1 App Releases 的程式相容性

已重新讀取目前 `main` 的 `admin-app-releases.js` 與 `app-release-center.js`：

- 管理端讀取 `version_code`、`version_name`、`release_notes`、`apk_url`、`published` 等欄位。
- 管理端新增／更新會送出 `created_by`，並依 `published` 更新發布狀態。
- 公開更新中心選取 `id,version_code,version_name,release_notes,apk_url,published,published_at,created_at`。
- 兩個程式路徑均未依賴 `is_latest`。

因此目前程式契約支持 Migration A（`202610310001_app_releases.sql`）的欄位方向；這仍不是歷史執行證明。

## 3. 正式資料庫權限與 View 風險（沿用既有唯讀證據）

### 3.1 Default privileges

既有 catalog 查詢顯示，`postgres` 在 public schema 的 default privileges 對 anon、authenticated、service_role 仍有廣泛 table／sequence 權限及 function EXECUTE。候選 migration 會改變未來物件的預設授權，影響範圍較單一功能廣。

**處置：** 不直接套用整份 default-privilege migration。先盤點目前每個應用程式／RPC／trigger 的必要權限，並在隔離環境測試「新建 table、sequence、function」的實際 ACL。

### 3.2 `is_admin()` 與 RLS policy 相依

既有盤點顯示 `is_admin()` 對 anon 沒有 EXECUTE，但多個 public RLS policies 使用 `is_admin()`。需要用 anon、authenticated 的 PostgREST 情境驗證 policy evaluation 是否出現權限錯誤；不可只由 ACL 靜態推斷所有匿名查詢均會失敗，也不可未測就授予 anon EXECUTE。

### 3.3 `activity_member_stats`

既有正式 DB 快照顯示此 view 曾向 anon／authenticated 開放，並包含 `user_id` 與內部積分細項。PR #35 提出的安全調整採分階段方式：先建立僅含五個公開欄位的 projection，再切換前端，最後才收緊舊 view。候選 PR CI 成功不等於正式 Supabase/PostgREST smoke test 通過；仍須維持分階段與上線門檻。

## 4. Maintenance 架構：唯一目標與舊文件界線

目前架構決策文件 `docs/maintenance-architecture-baseline-decision-v0.1.md` 已選定六表 private schema 方向：

1. `private.maintenance_scopes`
2. `private.maintenance_events`
3. `private.maintenance_event_private_notes`
4. `private.maintenance_event_scopes`
5. `private.maintenance_audit_logs`
6. `private.maintenance_idempotency`

此架構搭配五個 public RPC、使用者 JWT + SECURITY INVOKER、最小 grants/RLS。正式 DB 尚無以上物件；`private` 不存在的狀態也表示尚未部署。

使用者上傳的《啟動第一步檢查.txt》記錄的是較早的四表草案（`maintenance_state`、`maintenance_events`、`maintenance_scopes`、`maintenance_audit_logs`），不是目前六表架構。舊四表草案不可與六表 migration 拼接或混用。GitHub 中的 `maintenance-four-table-sql-compatibility-review-v0.1.md` 已標示為歷史審查，並指向後續架構決策文件。

仍需確認：
- Supabase Dashboard 的 Data API Exposed schemas 是否排除 `private`（GitHub 靜態檢查不能證明 Dashboard 設定）。
- 五支 Edge Functions 與五個 RPC 的欄位、JWT 傳遞、錯誤碼及回應契約。
- anon、一般 authenticated、admin 的 JWT/RLS/PostgREST 行為。
- 排程重疊、交易鎖、version conflict、idempotency 與 audit 行為。
- Maintenance scope code 的唯一 mapping 與前端七個功能區域。
- 完整 SQL 在隔離 PostgreSQL 17／GoTrue／PostgREST 環境的回歸測試。

## 5. Migration baseline 程序

1. 先確認實際 Supabase CLI 版本、專案設定與官方 remote schema pull 流程。
2. 在受控本機環境產生正式 schema snapshot；不匯出使用者資料或 secrets。
3. 人工檢查 public 自訂物件、extensions、auth/storage 自訂物件及 Supabase managed objects 的界線。
4. 在空白本機測試資料庫驗證 baseline 可重建。
5. 以完整 schema snapshot、Git history 與部署證據，建立逐檔的「來源證據／目前狀態／重複執行性／回復方案」表。
6. 不手動建立或修改 `supabase_migrations.schema_migrations`，不把 Auth／Realtime／Storage 內部 migration ledger 誤認為應用程式 migration history。
7. 完成以上步驟後，才提出具體的 migration history adoption／repair 計畫；任何正式套用仍需另行審核與明確授權。

## 6. 風險分級與建議順序

| 優先級 | 工作 | 完成條件 |
|---|---|---|
| P0 | 固定正式 DB baseline | CLI schema pull、完整人工比對、空白 DB 重建成功 |
| P0 | 確認 migration history 管理方式 | 找到權威來源；不手動造 history |
| P1 | App Releases 衝突整理 | 確認 Migration B 的其他環境用途；維持 A 與目前程式契約 |
| P1 | Growth function allowlist | 每個 SECURITY DEFINER function 的 owner、ACL、呼叫端與測試矩陣完成 |
| P1 | Default privileges 影響分析 | 新物件 ACL、trigger 執行、storage/schema 範圍與應用回歸通過 |
| P1 | PR #35 staged view hardening | 隔離環境驗證 A/B/C；先 projection，再前端，最後舊 view |
| P2 | Maintenance 六表契約驗證 | SQL／RPC／Edge／前端契約及 JWT/RLS/PostgREST 隔離測試通過 |
| P2 | Maintenance release readiness | Data API schema exposure、排程併發、rollback 與操作手冊完成 |

## 7. 2026-11-24 正式資料庫即時唯讀複查與 Repo 對照

> 本節是 2026-11-24 重新執行的 Supabase catalog SELECT 與 GitHub 檔案核對結果，更新並補充前述 2026-11-23 快照。沒有讀取使用者資料列，也沒有執行 DDL/DML。

### 7.1 正式資料庫即時結構計數

| 項目 | 2026-11-24 查詢結果 |
|---|---:|
| public base tables | 44 |
| base-table columns | 412 |
| public views | 1 |
| view columns | 8 |
| public constraints | 150 |
| public indexes | 109 |
| public RLS policies | 98 |
| public functions | 38 |
| SECURITY DEFINER functions | 36 |

注意：`information_schema.columns` 若不區分 relation 類型，會得到 420 欄（412 個 base-table columns + 8 個 view columns）。本文件分開記錄，避免把 View 欄位算成資料表欄位。

### 7.2 Schema 與 Migration history

- 非系統 schema 查詢結果：`auth`、`extensions`、`graphql`、`graphql_public`、`public`、`realtime`、`storage`、`vault`。
- 未找到 `private` schema；未找到 public Maintenance tables 或 Maintenance RPC。
- `schema_migrations` 名稱只在 `auth` 與 `realtime` schema 找到；這些是各自服務的內部紀錄，不是專案 Supabase CLI migration history。
- 此專案的 Supabase migration listing 仍為 0 筆；未找到 `supabase_migrations` schema。
- 因此目前不能從正式 DB 建立可信的「哪些 repo migrations 已執行」清單。結構相符只能列為吻合候選，不能當成執行證明。

### 7.3 App Releases 與 Calendar 的即時欄位核對

**App Releases：**
- 正式 `public.app_releases` 有 9 欄：`id`、`version_code`、`version_name`、`release_notes`、`apk_url`、`published`、`created_at`、`published_at`、`created_by`。
- 正式表沒有 `is_latest`；沒有 `public.is_app_release_admin()`。
- 正式表目前五項 policies：Admins can delete/insert/read all/update app releases，以及 Public can read published app releases。
- Constraints 包含 primary key、`version_code > 0`、`version_code` unique、`created_by` foreign key to `auth.users(id)`。
- 目前正式形狀與 `202610310001_app_releases.sql` 的方向相符；與 `20261031_app_releases.sql` 中的 `is_latest`／管理函式設計不相符。仍不能據此判斷哪一檔歷史上曾執行。

**Calendar：**
- 正式 `announcements` 存在 `event_date`、`event_end_date`、`event_date_source`、`event_date_confirmed`。
- 存在 `announcements_event_date_range_check`、`announcements_event_date_source_check`。
- 存在 partial index `announcements_calendar_event_date_idx`，條件為 published 且 event_date_confirmed。
- 以上結構與 `26.11.3_calendar_fields.sql` 相符；仍只屬結構吻合證據。

### 7.4 Growth 權限與 PR #35 候選 Migration 對照

正式 DB 即時查詢仍顯示下列 SECURITY DEFINER 函式由 `postgres` 擁有，且 `anon` 目前具有 EXECUTE：

- `admin_delete_growth_reward(uuid)`
- `admin_upsert_growth_reward(...)`
- `award_growth_points(...)`
- `check_activity_badges(uuid)`
- `check_growth_achievements(uuid)`
- `complete_growth_task(text)`
- `refresh_growth_level(uuid)`

其中 `award_growth_points` 的 authenticated EXECUTE 為 false；其餘上述函式的 authenticated EXECUTE 為 true。正式 DB 未找到 `_refresh_growth_level_internal(uuid)`，也未找到 PR #35 新增的 `activity_public_leaderboard`。

PR #35 的兩個候選檔案：
- `20261122120000_growth_rpc_and_public_leaderboard_hardening.sql`
- `20261122130000_activity_member_stats_security_invoker.sql`

目前是 PR 分支的候選內容，不是已證明存在於正式 DB 的 migration 狀態。Stage A／Stage B 仍未套用。

### 7.5 Default Privileges 即時核對

正式 catalog 顯示：
- `postgres` 在 `public` 的函式、資料表及序列 default ACL 仍包含 anon、authenticated、service_role 的廣泛權限。
- `supabase_admin` 在 `public` 也有函式、資料表及序列 default ACL 記錄；其函式預設授權仍包含 anon、authenticated、service_role。
- `postgres` 與 `supabase_admin` 都可在 `public` 建立物件。
- `supabase_admin` 是 Supabase 平台管理角色；本專案候選 Migration 不應未經獨立平台影響審查就修改其 default ACL。

此處只記錄 catalog 現況，不表示應直接執行某一份 default-privilege Migration。

### 7.6 Maintenance 舊草案與現行架構邊界

重新讀取使用者上傳的《啟動第一步檢查.txt》後，確認該文件描述較早四表草案：
- `maintenance_state`
- `maintenance_events`
- `maintenance_scopes`
- `maintenance_audit_logs`

該上傳檔是第一輪 SQL 審查摘要，並不是目前六表架構的 Migration，也不應被當成六表架構的 SQL 來源。現行 repo 六表目標仍以 `20261117121103_maintenance_system_initial.sql` 及架構決策文件為準；正式 DB 目前沒有 `private` schema 或 Maintenance objects。

### 7.7 本輪結論

1. 正式 DB 的結構計數已重新查詢；412 是 base-table 欄位數，另有 8 個 view 欄位。
2. App Releases A 與 Calendar Migration 的結構吻合，但歷史執行來源未知。
3. App Releases B 與正式 schema 不相符，不可直接當成正式環境下一個 migration。
4. Growth 權限與 PR #35 Stage A 目標仍有差異；PR #35 Stage A／B 未發布。
5. Maintenance 六表目標尚未部署；上傳四表草案只作為歷史審查材料。
6. Migration history 仍無權威來源；不能手動造 history，也不能把 auth/realtime 內部 migration table 當成專案紀錄。
7. 所有正式 Migration 維持 BLOCKED，直到取得完整 schema snapshot、完成隔離資料庫重建及逐檔證據審查。

## 8. 本次操作紀錄與限制

- 本次 GitHub 操作只新增本盤點文件於獨立文件分支並建立 Draft PR。
- 沒有修改既有 migration SQL、前端程式或 Edge Functions。
- 沒有執行正式 Supabase DDL/DML、migration repair、db push 或任何寫入型 RPC。
- 沒有部署 Edge Functions 或發布網站。
- 沒有建立 Supabase project／branch 或任何付費資源。
- 沒有讀取、匯出或記錄正式使用者資料列、密碼、token 或其他 secrets。
- 本文件引用既有唯讀盤點快照；正式執行前仍須重新查詢，不能把歷史快照當成當下即時狀態。

**最終判定：** 本文件可作為後續審核與排程依據；正式 Migration 仍為 BLOCKED，Maintenance 尚未部署。
