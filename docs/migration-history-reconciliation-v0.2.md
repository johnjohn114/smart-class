# Migration History 修復對照表與執行策略 v0.2

> 日期：2026-11-08
> 專案：smart-class / fsoowongtavlsrwvzbze
> 性質：只讀核對及程序決策；未執行 migration repair。

## 1. 現況

- Supabase migration list 回傳空集合。
- supabase_migrations.schema_migrations 在目前資料庫不存在。
- 在 PR #34 head `66bb27750beefcab3b578b75459f2a389570312d` 的 `supabase/migrations/` 共有七個 SQL 檔；其中包含 app releases 兩個互不等價版本、calendar、growth hardening 兩個、Maintenance 兩個。
- GitHub commit history 只能證明檔案進入版本庫的時間，不能證明 SQL 已在正式資料庫執行。
- 正式資料庫現況與其中兩個 SQL 的部分／主要物件吻合，但這不足以安全標記 applied。

## 2. 逐檔對照

| Migration | Git 來源 | 正式 DB 物件比對 | 決策 |
|---|---|---|---|
| 20261031_app_releases.sql | 2026-10-31 06:05:23 UTC，commit fb0b6b1a94821fbe384c9db391c3ae3b95741c19 | 不吻合：遠端缺 is_latest、對應索引及 is_app_release_admin() | 不可 repair 為 applied；保留歷史檔案，待封存 |
| 202610310001_app_releases.sql | 2026-10-31 06:06:00 UTC，commit 0573e012bba978acd158d6c48643976c4c9f6da9 | app_releases 欄位、約束、索引、RLS policies 目前相符 | 候選吻合，但缺完整證據；暫不 repair |
| 26.11.3_calendar_fields.sql | 2026-11-01 合併提交 929cd3564e1a6e4d6d2fae7fe0b897f876699ac7 | announcements calendar 欄位、check constraints、partial index 目前相符 | 候選吻合，但缺完整證據；暫不 repair |

## 3. 為何現在不能執行 repair

1. History table 不存在；CLI 可能需要先初始化或按版本採取特定程序，不能假設直接 repair 可用。
2. 兩個 app_releases 腳本衝突；若把舊檔標記 applied，會造成重建環境與正式環境結構不一致。
3. 結構吻合不代表執行來源與執行時間已證實。
4. 尚未取得完整 schema-only `pg_dump` snapshot，也沒有所有物件的完整比對；MCP catalog 查詢只能作為盤點與針對性比對，不能取代完整 dump。
5. 尚未查到 Dashboard SQL Editor 執行紀錄或正式部署紀錄。

## 4. 建議基線程序

### Phase A：凍結歷史
- 不改寫既有 SQL 內容。
- 先將七份檔案及其 Git commit 保留。
- 不以 Git commit timestamp 當 applied timestamp。

### Phase B：建立正式 baseline snapshot
- 在具備 Supabase CLI 與 Docker 的受控本機環境，先確認 CLI 版本與 `supabase db dump --help`。
- 本專案目前應使用 Supabase CLI v3 的明確 remote target：`supabase db dump --remote=fsoowongtavlsrwvzbze -f production-schema.sql`；`db dump` 是 schema-only、唯讀匯出，不包含使用者資料，也不修改 migration history。CLI v3 的 `db dump` 預設目標是 local，必須明確加 `--remote`。
- **不要用 `supabase db pull --remote` 做本輪唯讀盤點**：CLI v3 的 `db pull` 會把匯出結果寫成 migration，並更新遠端 `supabase_migrations.schema_migrations`；這會改變目前正式資料庫的 history 狀態。
- `db dump` 預設排除 Supabase managed schemas 與 extension schemas，且不包含 custom roles；對 `auth`、`storage` 等 managed schemas 的自訂觸發器/RLS 仍需以唯讀 catalog query 補充。本輪已針對 public triggers/policies、functions、default privileges 做了部分查核。
- 不匯出使用者資料，不把密碼或 access token 放入 Git；snapshot 檔案先留在受控本機，不直接提交公開 repo。
- 在乾淨的 disposable PostgreSQL/Supabase 相容環境重建，核對 schema objects、RLS、functions、triggers、grants、default privileges；再與正式 catalog 比較。
- 本次執行環境沒有 `supabase`、`psql`、`pg_dump` 或 `docker` 可執行檔，因此完整 dump 與空白資料庫重建尚未完成。

### Phase C：處理 migration history
- 先確認 Supabase CLI 版本、history table 初始化狀態與 migration repair --help。
- 不手動建立／更新 supabase_migrations.schema_migrations。
- 只有在完整 schema snapshot 與部署證據足夠時，才提出精確的 history repair 命令。
- 對衝突檔 20261031_app_releases.sql 不標記 applied；待查明是否任何環境曾使用，再從 active migration chain 移除或改名封存。
- 對吻合候選，在未取得執行證據前仍保持未確認；若採 snapshot baseline，需由 CLI 官方流程建立新的 baseline history，不可假造舊 migration 的執行日期。

### Phase D：新功能
- baseline 可重建且 migration history 一致後，再以 supabase migration new <name> 建立維護系統 migration。
- 不把維護系統 DDL 混進 baseline snapshot。
- 先在本機測試，再另行討論正式套用。

## 5. 本輪未執行

- 沒有 migration repair。
- 沒有 db pull、db push、db reset。
- 沒有手動建立 migration history table。
- 沒有修改任何正式 schema 或資料。
- 沒有建立 Supabase project／branch 或付費資源。


## 6. 2026-11-23 正式 Production Schema Baseline 唯讀盤點

### 6.1 專案與 catalog inventory

- Supabase project：`fsoowongtavlsrwvzbze`，狀態 `ACTIVE_HEALTHY`；PostgreSQL 17.11。
- Supabase `list_migrations` 回傳空集合。
- 以唯讀 catalog query 確認 schema 清單為 `auth`、`extensions`、`graphql`、`graphql_public`、`public`、`realtime`、`storage`、`vault`；沒有 `supabase_migrations`、`private` schema。
- MCP table inventory 回報 85 張 tables：`public` 44、`auth` 27、`storage` 10、`realtime` 3、`vault` 1；此為 catalog inventory，不是完整 schema dump。
- public catalog 有 98 policies、7 user triggers、38 functions；目前僅針對 migration 相關 objects 做了 targeted comparison。
- 正式 DB 並非空白資料庫；不能把空 migration listing 當作可直接初始化或重播所有 repo migrations 的依據。

### 6.2 Repository 七份 migration 與正式 DB 比對

| Migration | 正式 DB 指紋 | 目前判斷 |
|---|---|---|
| `202610310001_app_releases.sql` | `app_releases` columns、version check/unique、created_by FK、五個 RLS policies 與檔案定義相符 | **schema fingerprint 相符候選**；無 ledger / execution record，不能標記 applied |
| `20261031_app_releases.sql` | 缺 `is_latest`、對應 index、`is_app_release_admin()` 與 HTTPS check constraint | **完整 migration 不相符**；不可標記 applied；與另一 app_releases migration 是衝突版本 |
| `26.11.3_calendar_fields.sql` | announcements 的四個 calendar columns、兩個 check constraints、partial index 均存在且定義相符 | **schema fingerprint 相符候選**；無 ledger / execution record，不能標記 applied |
| `202611160001_growth_function_authorization_hardening.sql` | live function bodies / ACL / default privileges 與 migration 目標不同 | **未完整套用**；不要直接在 production 盲目重播 |
| `202611170001_default_privileges_and_trigger_hardening.sql` | live postgres default privileges 仍對 anon/authenticated/service_role 授予 public tables/sequences/functions 權限；`ensure_visitor_profile()` 仍為 conflict 時更新 role 的舊定義 | **未完整套用** |
| `20261117121103_maintenance_system_initial.sql` | `private` schema、六張表、五個 RPC 均不存在 | **未套用於此 production project** |
| `20261121140000_maintenance_rpc_least_privilege_upgrade.sql` | 初始 Maintenance objects 與 `maintenance_rpc_executor` 均不存在 | **未套用於此 production project** |

### 6.3 必須升級處理的既有 RPC 權限風險

唯讀檢查發現 production 的部分 `SECURITY DEFINER` functions 目前仍允許 `anon` EXECUTE，且部分函式本體沒有足夠的 actor/target authorization guard：

- `award_growth_points(uuid,integer,text,text,text,text,uuid)`：`anon` 可 EXECUTE；函式本體沒有驗證呼叫者必須是管理員或只能操作本人。
- `check_growth_achievements(uuid)`：`anon` 可 EXECUTE；目前 live body 在指定非 NULL 的 user id 時沒有驗證呼叫者與目標 user 的關係。
- `admin_delete_growth_reward(uuid)`：`anon` 可 EXECUTE；live body 使用 `caller_role <> 'admin'`，但沒有先 fail-closed 檢查 `auth.uid() IS NULL`，NULL 比較可能不會進入拒絕分支。
- `refresh_growth_level(uuid)`、`admin_upsert_growth_reward(...)`、`increment_download_count(uuid)` 也允許 `anon` EXECUTE；各函式本體的授權與預期公開行為需逐一審核，不能只靠 ACL 名稱推定安全。

這是 production 現存權限風險，與 Maintenance migration baseline 是兩件事。**不可為了修正它而直接重播整份 `202611160001`**；該檔同時修改多個函式、預設權限與 RPC ACL，必須先逐函式核對 live definitions、依賴、trigger bindings、呼叫來源與前端行為，再準備獨立、可回歸測試的最小修補方案。此次沒有修改任何正式權限。

### 6.4 CLI 程序與目前阻擋

- Supabase CLI v3（2026-11-04 breaking change）database commands 預設目標改為 local，需明確使用 `--remote=<project-ref>`。
- 官方 CLI reference 說明 `db dump --remote` 以 pg_dump 匯出 schema，不包含資料或 custom roles，且不詢問 hosted mutation confirmation；這適合用於本輪唯讀 baseline snapshot。
- CLI v3 的 `db pull` 會寫入 migration 檔並更新遠端 migration history；目前 production 沒有 history table，因此不得把 `db pull` 當作無副作用的唯讀檢查。
- 本次 ChatGPT 執行環境沒有 Supabase CLI、psql、pg_dump、Docker；因此尚未取得完整 schema dump、尚未完成空白資料庫重建，也沒有資格提出 migration repair / baseline history mutation。
- 下一步需在受控本機環境取得 schema-only dump，審核後於 disposable database 驗證重建；這完成前，保留所有既有 migration 檔案，不做 history repair 或 production SQL。

### 6.5 本次操作界線

本輪僅執行 Supabase catalog SELECT / inventory 與 GitHub source file review；未執行 DDL/DML、`db dump`、`db pull`、`db push`、migration repair、部署、feature flag 修改或 PR merge。


### 6.6 2026-11-23 Production SECURITY DEFINER / anon RPC 深入核對

#### Catalog facts

- `anon` 對 `public` schema 有 USAGE。
- Production 有 36 個 public SECURITY DEFINER functions，其中 34 個目前可由 `anon` EXECUTE。這是 ACL inventory，不代表 34 個函式全部可被利用；必須把每個函式的 body authorization 與預期公開用途分開判讀。
- 下列六個 RPC 已確認同時具備 `SECURITY DEFINER`、`anon EXECUTE`，且存在實際授權缺陷：

| Function | Live defect | Potential impact |
|---|---|---|
| `award_growth_points(uuid,integer,text,text,text,text,uuid)` | 無呼叫者身分／管理員驗證 | 可指定目標會員並改動積分及交易紀錄 |
| `check_growth_achievements(uuid)` | 只在目標 ID 為 NULL 時返回；未驗證呼叫者與目標會員 | 可指定其他會員觸發成就檢查及相關獎勵副作用 |
| `check_activity_badges(uuid)` | `p_user_id <> auth.uid()` 在匿名情境會得到 NULL，後續 IF 不會拒絕 | 可嘗試替其他會員觸發徽章寫入 |
| `refresh_growth_level(uuid)` | 未驗證登入身分或目標會員 | 可指定其他會員更新 growth_level |
| `admin_delete_growth_reward(uuid)` | `caller_role <> 'admin'` 在 caller_role 為 NULL 時結果為 NULL，IF 不會拒絕 | 未登入呼叫可能通過管理員檢查並刪除／停用獎勵 |
| `admin_upsert_growth_reward(...)` | 同樣使用可被 NULL 繞過的 `caller_role <> 'admin'` | 未登入呼叫可能通過管理員檢查並新增／修改獎勵 |

- 上述六個函式的 live owner 均為 `postgres`，且目前 ACL 都明確允許 `anon` EXECUTE；這不是僅由 PUBLIC 預設權限推測。
- `increment_download_count(uuid)` 也目前允許 anon EXECUTE，雖然它只更新已發布檔案的下載計數；前端 `app.js` 在呼叫前要求 `visitorToken()`，且 candidate migration 將其改為 authenticated-only，與目前前端流程一致。
- 多個 trigger-returning functions（例如 `ensure_visitor_profile()`、`growth_registration_reward()`、`growth_result_reward()`、`check_competition_registration_rules()`）也有多餘 API-role EXECUTE grants；candidate migration 會撤銷直接呼叫權限，但保留 trigger bindings。

#### Existing candidate remediation review

`202611160001_growth_function_authorization_hardening.sql` 已包含對上述六個問題的對應修補：

1. `award_growth_points` 撤銷 PUBLIC、anon、authenticated 的直接 EXECUTE；保留 trusted server-side `service_role`，並讓 SECURITY DEFINER 內部呼叫及 trigger 呼叫繼續工作。
2. `check_growth_achievements` 加入 `auth.uid() IS NULL` fail-closed 檢查，並拒絕跨會員操作（管理員例外）。
3. `check_activity_badges` 改用 `IS DISTINCT FROM` 並明確拒絕 NULL UID，防止匿名 NULL 邏輯繞過。
4. `refresh_growth_level` 限制只能更新本人，或由管理員更新其他會員。
5. `admin_delete_growth_reward` 與 `admin_upsert_growth_reward` 加入明確 UID 檢查及 `caller_role IS DISTINCT FROM 'admin'`。
6. ACL hardening block 先撤銷 public SECURITY DEFINER routines 的 PUBLIC/anon/authenticated grants，再依審核 allowlist 授權；trigger functions 不再有 API-role EXECUTE。

#### Regression coverage and remaining gap

- `supabase/tests/sql/growth-function-authorization.test.sql` 有檢查 anon ACL、登入者跨會員操作拒絕、缺少 JWT UID 時管理 RPC 拒絕、本人操作及管理員操作。
- `supabase/tests/sql/growth-and-default-privileges-sequential.test.sql` 驗證兩份 hardening migrations 順序套用、trigger 行為與 default privileges。
- PR #34 current head 的四項 CI checks 已通過；但這些仍是 disposable PostgreSQL fixtures，不能視為正式資料庫已修補，也不是對每個 live RPC 的 hosted PostgREST 行為完整驗證。
- 仍需在隔離環境補上針對六個漏洞的明確匿名／跨帳號行為測試，並逐一審核其餘 anon-executable SECURITY DEFINER functions 的預期用途與授權路徑。

#### Decision

**Production RPC risk is confirmed and remediation candidate exists, but no production fix has been applied.** 不可在 global migration baseline reconciliation 前直接執行整份 `202611160001` 或 `202611170001`。下一個安全工作是把六項 live defect 轉成獨立、最小、可回歸測試的修補候選，先於 disposable PostgreSQL/PostgREST 驗證，再等待正式 baseline / migration governance 核准。

本輪仍只執行唯讀 catalog SELECT、GitHub source/test review；未執行 production DDL/DML、權限變更、migration、部署或 PR merge。


### 6.7 2026-11-23 補強匿名及缺少 JWT 身分的回歸測試

- 在 `supabase/tests/sql/growth-function-authorization.test.sql` 新增匿名角色直接呼叫六個受保護 RPC 的行為測試，要求在 EXECUTE 權限邊界收到 `insufficient_privilege`。
- 新增 authenticated SQL role 缺少 JWT subject 時，對 `check_growth_achievements`、`check_activity_badges`、`refresh_growth_level` 指定其他會員 ID 必須拒絕的測試。
- 新增 side-effect assertions，確認缺少身分的呼叫沒有更動目標會員積分、等級、徽章或成就紀錄。
- GitHub Actions run `45045026995` 的 **Isolated PostgreSQL RPC and RLS tests** 已成功完成，包含 growth authorization regression、default privileges/trigger regression、sequential integration；該 run 其餘三項工作當時仍在執行，故不能將整體 CI 標記為通過。
- 這些新增測試只在 disposable PostgreSQL fixture 執行；未連接正式 Supabase，也未更動正式權限。
