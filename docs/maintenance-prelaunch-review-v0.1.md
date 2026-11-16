# Maintenance System 上線前全面審核 v0.1

> 日期：2026-11-16  
> 審核分支：`feature/maintenance-system`  
> 審核基準 commit：`4f581437f06ba24f6ee755d66dd267cc14169a46`  
> GitHub Actions：`43890950642`（Deno、isolated PostgreSQL、GoTrue/PostgREST 三項皆成功）  
> 範圍：功能分支原始碼、SQL 草案、API 規格、CI 測試與既有唯讀 Supabase 審查文件。  
> 本審核沒有連線修改正式 Supabase，沒有執行 Migration、部署、合併或付費資源操作。

## 1. 已確認通過項目

- 五支 Edge Function 的入口分別使用預期 HTTP method；四支管理 API 要求登入，公開 status 使用 optional bearer token。
- 管理 RPC 在資料庫端檢查 `auth.uid() IS NOT NULL AND public.is_admin()`；actor 由 `auth.uid()` 取得。
- SQL 草案五個 RPC 均為 `SECURITY INVOKER`，設定空的 `search_path`，並使用完整限定物件名稱。
- 六張 private tables 全部啟用 RLS；匿名角色沒有管理 RPC EXECUTE，也沒有 private table 寫入 grant。
- `internal_note` 獨立存放於 `private.maintenance_event_private_notes`；公開 status RPC 使用明確欄位白名單。
- SQL 草案未使用 `service_role`，亦未把 private schema 加入 PostgREST schema 清單；CI 的 PostgREST 設定只暴露 `public`。
- Create/update/action 的冪等性改為伺服器端 SHA-256；建立與修改的雜湊會正規化文字、scope 順序及時間表示。internal note 寫入值亦與正規化結果一致。
- CI 已測試 create 的等價輸入重播、同 key 不同內容拒絕；GoTrue/PostgREST 測試亦覆蓋 update 重播、key reuse、version conflict、schedule、cancel 與 action 重播。
- 最新 Actions run `43890950642` 三項工作全部成功。

## 2. 尚未通過正式上線門檻的項目

以下是待完成事項，不代表已發現正式環境遭入侵或已發生資料外洩。

### 高優先：正式環境尚未驗收

- 正式 Supabase 目前沒有 private schema、六張維護資料表、五個 RPC 或五支已部署 Edge Functions。
- 正式 Data API Exposed schemas 的實際設定仍需在部署前確認，確保 `private` 不在 exposed schemas。
- Migration baseline/history 尚未完成釐清；不可直接把現有 SQL 草案放進 migrations 後對正式環境執行。
- 真實正式環境的 Edge Function secrets、CORS allowlist、Gateway 設定與部署後 smoke test 尚未驗證。

### 高優先：權限邊界需在發布前再確認

- SECURITY INVOKER 必須取得實際 table grants 才能執行寫入；目前 authenticated admin 的部分 table grants 包含 event insert/update、scope link insert/delete、private note insert/update。private schema 不暴露於 Data API 是重要邊界，但這不等於資料庫權限層能證明「只能透過 RPC 寫入」。
- Audit log 已限制一般 UPDATE/DELETE，並以 trigger 阻止 row mutation/TRUNCATE；但 authenticated admin 仍有 audit INSERT 權限。規格已記載這個限制，不能把 audit 宣稱為資料庫層完全不可偽造。
- 上線前需確認產品接受上述 SECURITY INVOKER 權限模型；若要求更強的 DB 層「RPC-only」或 audit 防竄改保證，必須另行設計及隔離測試，不可臨時改成 SECURITY DEFINER。

### 中優先：產品與維運決策未定

- API 規格列有 `429 RATE_LIMITED`，但目前 Edge Function 程式碼未實作應用層 rate limiting。需決定是否依賴既有平台限制，或另設不需付費的限流方案；在未決定前不可宣稱已具備 API rate limit。
- Audit 與 idempotency 保留期限及清理方式尚未定稿；目前不應假設使用 pg_cron。
- 七個 scope code 仍需產品端最後核對。
- Status API 目前只回傳正在生效的維護事件；是否要顯示未來排程尚待確認。
- 已開始事件的欄位限制目前採保守策略；若要延長或提前結束，需另訂 action 規格。

## 3. 建議補強的隔離測試

現有 CI 已成功，但以下案例仍值得補齊後才進入正式 migration 核准：

1. anon 對四個管理 RPC（list/create/update/action）逐一確認拒絕。
2. authenticated 非管理員對 create/update/action 逐一確認拒絕。
3. 嘗試傳入偽造 actor/user/role 欄位，確認 SQL 白名單拒絕且 audit actor 不受影響。
4. 局部 scope 交集、`site_core` 與其他局部 scope、global/local 重疊的併發衝突測試。
5. `complete` 只能在事件結束時間後執行；未到期時拒絕。
6. update 的等價時間格式/文字正規化重播案例。

## 4. Supabase 近期相容性備註

Supabase 2026-04-28 公告：新建 public schema tables 不再自動暴露於 Data API，並於 2026-10-30 對所有專案強制執行。此維護設計使用 private schema，仍須明確確認 Data API schema allowlist；不能把「未自動暴露」當成 grants/RLS 的替代品。  
Supabase CLI v3（2026-11-04）改為預設 local-first 並在 hosted 變更前確認；本專案目前沒有用 CLI 對 hosted project 執行變更，本審核也沒有執行 CLI migration。

## 5. 結論

**功能分支 CI：通過。正式發布核准：尚未通過。**

目前可繼續完成測試補強、產品決策及 migration baseline 審核；在正式環境 schema、權限、設定與部署後驗收未完成前，不應執行正式 Migration 或部署。

本文件僅記錄審核結果，不授權修改正式 Supabase。

---

## 6. 整合相容性複核（2026-11-16）

> 複核基準 branch HEAD：`ab8d64e8be33e2d5cb1bb23283f07a4a6b108afa`。  
> 最近一次成功 CI：run `43891994630`，測試提交 `051f7c8f42af8b0649ea817604ff00c7c8a4e242`。目前 HEAD 是後續文件提交；不能將 run SHA 說成目前 HEAD 的完整測試。  
> 正式 Supabase 本輪僅使用唯讀工具查詢。

### 6.1 Migration baseline — 阻擋

- 正式 Supabase Migration API 回傳空清單。
- Repository 的 `supabase/migrations/` 有三份 SQL，其中兩份都建立 `public.app_releases`，但欄位、RLS policy、預設值與管理員 helper 設計不同：
  - `202610310001_app_releases.sql`
  - `20261031_app_releases.sql`
- 另有 `26.11.3_calendar_fields.sql`。
- 因此不能僅憑正式 Migration history 空白就推斷正式 schema 沒有執行過這些變更；也不能直接重跑或標記 applied。需先以唯讀 schema diff 核對正式現況，整理唯一且可重現的 migration baseline，並釐清兩份 app_releases migration 的先後/取捨。
- 維護 SQL 目前仍是 `supabase/sql/` 下的 draft，沒有被放進正式 migrations；這個停止界線必須維持。

### 6.2 正式 schema / RPC / Edge Functions — 已核實仍未建立

本輪 Supabase 唯讀查詢再次確認：
- 專案 `ACTIVE_HEALTHY`，PostgreSQL `17.11.0.003`。
- `private` schema 不存在。
- 六張 maintenance tables 不存在；五個 maintenance RPC 不存在。
- 已部署 Edge Functions 清單中沒有五支 maintenance functions。
- Migration history 清單為空。

這些結果表示維護功能尚未部署，並非正式資料庫出錯。正式資料庫沒有執行任何 DDL/DML、Migration 或部署。

### 6.3 PostgreSQL 版本相容性 — CI 已補強通過

2026-11-16 已將兩組隔離 PostgreSQL services 更新為 `postgres:17`。最新 CI run `43899555108` 對應 branch HEAD `761b37b2b3f5b47a2d17ea5d0399c1f8e309ed6e`，Deno、isolated PostgreSQL RPC/RLS、GoTrue/PostgREST JWT/RLS 三項工作全部成功。這確認 CI 已在 PostgreSQL 17 測試路徑通過；仍不等同正式 Supabase 部署後驗收。

### 6.4 Data API Exposed schemas — 無法由目前唯讀介面確認

- CI 的 PostgREST 明確使用 `PGRST_DB_SCHEMAS=public`，可確認隔離測試不暴露 `private`。
- 本輪可用的 Supabase 管理介面沒有提供正式專案 Data API Exposed schemas 設定讀取結果；不能把 CI 設定當成正式設定。
- 部署前必須由 Supabase Dashboard 的 API/Data API 設定頁確認 `private` 不在 exposed schemas，並將確認結果記錄。若無法確認，維持停止，不執行 Migration/部署。

### 6.5 Edge Function / CORS — 原始碼靜態檢查

- `maintenance-status` 使用 `verify_jwt=false`，但程式會驗證可選 bearer token；管理員 bypass 只作為前端提示。
- 其餘四支管理 functions 使用 `verify_jwt=true`，並要求有效使用者 token。
- 共用 CORS helper 預設只允許 `https://johnjohn114.github.io`，可由 `MAINTENANCE_ALLOWED_ORIGINS` 覆寫；只回傳與 allowlist 完全相符的 Origin，不使用萬用 `*`，亦未設定 credential sharing。
- RPC 呼叫使用 publishable/anon key 作 apikey，並轉送使用者 bearer token；靜態檢查未見 service_role key。
- 正式專案尚未部署這五支 functions，因此正式 secrets、實際 CORS env、Gateway 行為與部署後 smoke test 仍未驗收。

### 6.6 既有 Security Advisor — 與本功能分開追蹤

本輪 Advisor 仍顯示既有安全警示（包含 SECURITY DEFINER 函式可由 API roles 執行、既有 RLS/policy 問題與 Auth leaked-password protection 設定）。這些警示涉及既有網站功能，不能在維護系統上線工作中批次撤權或修改。應另建逐項盤點，確認呼叫端、依賴、權限及回歸測試後再處理。

### 6.7 整合結論

**本輪整合審核：完成唯讀核對；正式發布核准：未通過。**

明確阻擋項目：
1. Migration history 仍為空；唯讀 schema 比對已確認正式 app_releases 與 `202610310001_app_releases.sql` 相符、行事曆欄位/約束/索引與 `26.11.3_calendar_fields.sql` 相符，但仍需整理可重現的歷史 baseline，不能據此直接 repair 或重跑。
2. 正式 Data API Exposed schemas 無法由目前管理介面讀取，必須人工確認 private 未暴露。
3. PostgreSQL 17 CI 已通過；仍須保留正式環境部署後驗收。
4. 正式 Edge Function secrets/CORS 與部署後 smoke test 尚未驗證。
5. API 規格有 429 rate-limit response，但現有共用 Edge Function 程式碼尚無應用層 rate limiter；需定稿限流方案或調整契約。
6. audit/idempotency retention 與清理政策仍未定稿。

在上述阻擋解除前，不執行正式 Migration、不部署、不合併 main、不新增付費資源。這份整合複核不構成正式環境變更授權。


### 6.8 Migration baseline 唯讀比對補充（2026-11-16）

本輪直接對正式 Supabase 執行唯讀 catalog 查詢，未修改任何資料：

**`public.app_releases`**
- 正式表欄位為 `id, version_code, version_name, release_notes, apk_url, published, created_at, published_at, created_by`；預設值、nullable、`version_code > 0`、唯一約束及 `created_by -> auth.users(id)` 外鍵，均與 `202610310001_app_releases.sql` 的建表設計相符。
- 正式 RLS policies 的名稱及條件亦與 `202610310001_app_releases.sql` 相符：公開讀取已發布版本、管理員讀取全部、管理員新增（created_by 必須為 null 或 auth.uid()）、管理員更新及刪除。
- 正式索引為主鍵及 version_code 唯一索引；未發現第二份 `20261031_app_releases.sql` 所定義的 `is_latest` 欄位、`is_app_release_admin()` helper 或複合 published index。
- 因此，兩份候選 SQL 中，第一份與目前正式 app_releases schema/policies 相符；第二份不相符。這是現況結構比對結果，不是 migration history 證明，也不代表可將 migration 標記 applied 或重跑。

**`public.announcements` 行事曆欄位**
- 正式表已有 `event_date`, `event_end_date`, `event_date_source`, `event_date_confirmed`，型別及 nullable/default 與 `26.11.3_calendar_fields.sql` 相符。
- `announcements_event_date_source_check`、`announcements_event_date_range_check` 兩項 CHECK constraint 的定義與 migration 相符。
- `announcements_calendar_event_date_idx` 的 partial index 定義亦與 migration 相符（`published = true AND event_date_confirmed = true`）。

**結論與限制**
- 這次已將兩個 migration 家族的現況核對從「未知」縮小為「正式 schema 與 repo 中指定 SQL 的物件定義相符」。
- 仍需完成其餘正式 schema、函式、觸發器、GRANT/RLS、索引及 extension 的完整唯讀盤點，才能決定 migration baseline 的唯一重建方式。
- Migration history 仍為空；不得因 schema 相符就執行 `migration repair`、`db push`、套用 migration 或改動正式資料庫。


### 6.9 正式 public schema 安全目錄盤點（2026-11-16，唯讀）

- `public` schema 共 44 張資料表；44 張均已啟用 RLS，未發現 RLS disabled 的 public table。
- `member_no_counter`、`visitor_profiles` 兩張表目前沒有任何 RLS policy。RLS 開啟但沒有 policy 時，API roles 的一般 row access 會被拒絕；仍需確認這兩張表的預期存取路徑（例如受控 trigger/function），不能直接補上寬鬆 policy。
- 目前盤點到 38 個 public functions，其中 36 個為 `SECURITY DEFINER`；其中 34 個可由 `anon` 執行，34 個可由 `authenticated` 執行（依 `has_function_privilege` 檢查，包含透過 PUBLIC 權限繼承的可執行性）。這是既有網站安全審查項目，不代表 34 個函式均可被未授權利用；必須逐一檢查函式內容、ACL、呼叫端及身分驗證條件。不得在本維護系統工作中批次撤權。
- public schema 目前有 7 個非內部 trigger；啟用 extension 包含 `pg_stat_statements`、`pgcrypto`、`plpgsql`、`supabase_vault`、`uuid-ossp`。
- catalog 結果顯示多張 public tables 對 API roles 存在廣泛 table-level grants。RLS 是 row-level 邊界，不等於 table privilege；需後續按表與操作（SELECT/INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER）對照 policies、前端實際呼叫及 service_role 使用方式，先建立權限矩陣，不進行批次 revoke。

此盤點是 preliminary catalog inventory，並非完整安全滲透測試或正式發布核准。所有查詢均為唯讀，沒有變更正式資料庫。


### 6.10 高優先級既有 SECURITY DEFINER / ACL 發現（2026-11-16，唯讀靜態審查）

本節為正式資料庫 catalog 與函式定義的唯讀審查，未呼叫這些函式、未測試修改資料，也未變更權限。

**A. 管理員判斷存在 NULL 比較漏洞**
- public.admin_delete_growth_reward(uuid) 與 public.admin_upsert_growth_reward(...) 均為 SECURITY DEFINER，且 ACL 明確允許 anon 與 authenticated 執行。
- 兩者以 caller_role <> 'admin' 作為拒絕條件。未登入時 auth.uid() 查不到 profile，caller_role 為 NULL；SQL 的 NULL <> 'admin' 結果仍是 NULL，PL/pgSQL 的 IF NULL 不會進入拒絕分支。因此管理員檢查並未可靠地拒絕未登入呼叫。
- 這兩個函式分別包含停用/刪除成長獎勵，以及新增/更新成長獎勵的寫入邏輯。列為 P0 / 緊急待修。這是由正式函式定義與 ACL 推導出的可達風險；本輪沒有實際呼叫驗證，也沒有執行任何寫入。

**B. 成長積分與成就函式的身分限制不足**
- public.award_growth_points(...) 是 SECURITY DEFINER，ACL 允許 anon 執行，函式本體未檢查呼叫者身分或管理員資格，且可更新指定 p_user_id 的成長積分。列為 P0 / 緊急待修。
- public.check_growth_achievements(p_user_id) ACL 允許 anon 與 authenticated 執行；函式本體未確認 p_user_id 是否等於 auth.uid() 或管理員，並會寫入指定會員的成就及可能呼叫積分發放。列為 P1 / 高優先。
- public.refresh_growth_level(p_user_id) ACL 允許 anon 與 authenticated 執行；函式本體未確認呼叫者與目標會員的關係，並會更新指定會員的 growth_level。列為 P1 / 高優先。
- 前端 app.js 目前會以登入會員自己的 u.id 呼叫 check_growth_achievements 及 refresh_growth_level。修補時須保留此合法使用情境，加入 auth.uid() IS NOT NULL 且（目標非本人時）明確管理員授權檢查；不可只撤銷 authenticated EXECUTE 而破壞既有流程。

**C. 其他觀察與權限背景**
- public schema 對 postgres 與 supabase_admin 的 table default privileges 均包含 anon=arwdDxt（含 INSERT/UPDATE/DELETE/TRUNCATE 等）。因此新建 public table 可能自動取得過寬的 anon table privileges。
- 本輪確認沒有任何 anon 角色的 public table write RLS policy；所以單靠這些 table grants 並不代表 anon 可直接寫入受 RLS 保護的列。但它仍違反 least privilege，且不能防止具有缺陷的 SECURITY DEFINER RPC 繞過一般 table RLS。
- 多個 admin_* SECURITY DEFINER 函式也授予 anon EXECUTE；其中不少函式本體有明確 auth.uid()/admin 檢查，不能把所有 34 個函式一概視為可未授權寫入。必須逐個依函式本體、呼叫者、trigger 用途及前端呼叫確認。
- public.increment_download_count(uuid) 目前允許 anon 執行，函式只對已發布下載項目增加計數；初步視為預期公開計數功能，仍需納入濫用/速率限制審查。
- 部分 trigger function 在 catalog 中也顯示 anon EXECUTE，但 trigger-returning function 不能當作一般 RPC 直接呼叫；應從 default ACL 清理策略中獨立處理，不可誤判為一般 API callable function。

**建議修補順序（僅供功能分支設計，尚未執行）**
1. 先修正兩個管理員函式的 guard，使用 auth.uid() IS NULL OR caller_role IS DISTINCT FROM 'admin'，並限制 anon EXECUTE；保留 authenticated 呼叫，由函式本體再做管理員驗證。
2. award_growth_points 移除 anon EXECUTE，並確認只由受信任 trigger/SECURITY DEFINER 流程或 service_role 呼叫。
3. check_growth_achievements、refresh_growth_level 加入本人/管理員授權檢查，保留前端本人呼叫；匿名 EXECUTE 應移除。
4. 調整 public schema default privileges，停止未來新表自動向 anon 授予寫入權限；先確認新表建立者與既有 API 使用情境。
5. 建立完整函式 ACL 清單及每個 function 的用途矩陣，再在隔離 PostgreSQL/GoTrue/PostgREST CI 加入匿名拒絕、會員本人允許、會員跨帳號拒絕、管理員允許測試。

**安全界線**
- 上述只記錄為正式環境發現與功能分支修補建議。本輪沒有執行 REVOKE、ALTER DEFAULT PRIVILEGES、CREATE OR REPLACE FUNCTION、資料寫入、Migration、部署或 merge。
- 在修補及隔離測試完成前，正式環境不可視為已通過安全審查；maintenance system 發布仍需獨立核准。
