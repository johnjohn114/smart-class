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

## 7. Supabase Migration 清單工具的補充確認（2026-11-18）

另外透過 Supabase 專案 Migration 清單介面查詢，回傳 `migrations: []`，即目前沒有列出任何由該介面管理的 migration 紀錄。

系統目錄另可見：
- `auth.schema_migrations`：只有 `version` 欄位，屬 Auth 服務內部紀錄，不是本專案 public schema migration 清單。
- `realtime.schema_migrations`：只有 `version`、`inserted_at`，屬 Realtime 服務內部紀錄。
- `storage.migrations`：欄位為 `id`、`name`、`hash`、`executed_at`，屬 Storage 服務 migration 紀錄。

因此，本次對應用程式資料庫 migration 的判斷更明確：Supabase Migration 清單目前為空，且未找到專案層級的標準 migration history。這仍不排除曾透過 SQL Editor 手動執行、其他工具或其他環境流程修改資料庫。正式歷史必須由專案管理者確認來源，不能把 Auth/Realtime/Storage 內部 migration 紀錄誤認為 app schema migration 歷史。

## 8. App releases 衝突的應用程式相容性檢查（2026-11-18）

本輪另外讀取了分支中的 `admin-app-releases.js`、`app-release-center.js`、`app-updates.html` 及 Android `build.gradle`，並再次唯讀查詢正式資料庫的欄位、RLS policies 與 indexes。

### 8.1 現有應用程式依賴

- `admin-app-releases.js` 查詢 `app_releases`，按 `version_code.desc` 排序。
- 新增／更新時送出 `version_code`、`version_name`、`release_notes`、`apk_url`、`published`、`published_at`、`created_by`。
- 管理介面會依 `published` 顯示發布狀態，並提供新增、編輯、切換發布、刪除操作。
- `app-release-center.js` 讀取 `id,version_code,version_name,release_notes,apk_url,published,published_at,created_at`，只顯示已發布版本。
- Android `build.gradle` 目前設定 `versionCode 21`、`versionName '26.11.6'`。

目前這些讀取路徑不依賴 `is_latest` 欄位。

### 8.2 正式資料庫實際結構

正式資料庫 `public.app_releases` 欄位為：
`id`、`version_code`、`version_name`、`release_notes`、`apk_url`、`published`、`created_at`、`published_at`、`created_by`。

目前 indexes 為：
- `app_releases_pkey`
- `app_releases_version_code_key`

目前 policies 為五項：
- `Public can read published app releases`
- `Admins can read all app releases`
- `Admins can insert app releases`
- `Admins can update app releases`
- `Admins can delete app releases`

沒有查到 `app_releases_published_idx`，也沒有查到 `is_app_release_admin()` 函式。

### 8.3 相容性判定

| 比較點 | Migration A：`202610310001_app_releases.sql` | Migration B：`20261031_app_releases.sql` |
|---|---|---|
| `created_by` | 有 | 沒有 |
| `version_code` 唯一性 | 有 | 無 UNIQUE constraint（僅普通欄位） |
| `is_latest` | 沒有 | 有 |
| `apk_url` HTTPS constraint | 沒有 | 有 |
| policies | 與正式資料庫五項命名一致 | 兩項不同命名 policies |
| helper function | 無 | 建立 `is_app_release_admin()` |
| index | version_code unique index | 額外 published/latest 複合 index |
| 與現有前後端契約 | 高度吻合 | 不完全吻合，管理端送出的 `created_by` 欄位會與此定義不相容 |

**結論更新：** 現有正式資料庫結構、管理端送出的欄位、公開更新中心的 select 欄位，以及現有 policies，均支持 Migration A 是目前實際採用的 schema 契約。Migration B 不應執行到這個正式資料庫，也不應與 Migration A 串接執行。這是相容性結論，不是 migration history 的來源證明。

### 8.4 建議處置（尚未修改程式）

1. 將 Migration A 標記為目前 schema 的相容基準。
2. 將 Migration B 標記為衝突候選／待查明來源，不可套用到現有正式資料庫。
3. 暫不刪除或改寫 Migration B，避免破壞其他分支或環境可能存在的歷史用途。
4. 若未來要統一 migration 管理，應先在獨立測試資料庫驗證完整 migration 序列，再安排版本化整理。
5. 不新增 `is_latest`，也不修改管理介面、公開更新中心或 Android 版本設定；目前沒有證據顯示這些改動是必要的。

## 9. Growth RPC 正式環境風險與呼叫端審查（2026-11-18）

本節只做正式資料庫函式定義／EXECUTE 權限的唯讀檢查，以及分支前端呼叫位置比對；沒有呼叫任何會修改正式資料的 RPC。

### 9.1 高優先級：目前 anon 可執行且函式本體授權不足

| 函式 | 正式資料庫 anon EXECUTE | 正式函式本體觀察 | 風險 |
|---|---:|---|---|
| `award_growth_points(uuid,integer,text,text,text,text,uuid)` | 是 | 沒有驗證 `auth.uid()` 或呼叫者角色；可依參數更新指定會員積分、寫入交易及通知 | 未登入呼叫可影響任意會員積分 |
| `check_growth_achievements(uuid)` | 是 | 正式版本沒有會員本人／管理員檢查；會依指定會員資料解鎖成就，並可能呼叫積分發放 | 未登入呼叫可觸發他人獎勵與積分變更 |
| `refresh_growth_level(uuid)` | 是 | 正式版本沒有本人／管理員檢查；會更新指定會員的 `profiles.growth_level` | 未登入呼叫可改動他人等級欄位 |
| `check_activity_badges(uuid)` | 是 | 正式版本以 `p_user_id <> auth.uid()` 判斷；當 `auth.uid()` 為 NULL 時，SQL 比較結果也是 NULL，條件可能不會觸發拒絕 | 未登入呼叫可指定其他會員並寫入徽章紀錄 |
| `admin_delete_growth_reward(uuid)` | 是 | 以 `caller_role <> 'admin'` 判斷；匿名請求查不到角色時 `caller_role` 為 NULL，IF NULL 不會進入拒絕分支 | 未登入呼叫可能停用或刪除獎勵 |
| `admin_upsert_growth_reward(...)` | 是 | 同樣以 nullable 的 `caller_role <> 'admin'` 判斷，沒有先拒絕 `auth.uid() IS NULL` | 未登入呼叫可能新增或修改獎勵 |

以上是依據函式定義與權限推導出的可達風險；本次沒有實際呼叫這些 RPC，也沒有修改積分、獎勵、等級或徽章資料。

### 9.2 其他 Growth RPC：目前可由 anon 呼叫，但函式內有登入檢查

| 函式 | anon EXECUTE | 本次檢查到的保護 |
|---|---:|---|
| `complete_growth_task(text)` | 是 | 先檢查 `auth.uid()`，未登入會拒絕 |
| `record_growth_activity()` | 是 | 先檢查 `auth.uid()`，未登入會拒絕 |
| `redeem_growth_reward(uuid)` | 是 | 先檢查 `auth.uid()`，未登入會拒絕 |
| `use_growth_coupon(uuid)` | 是 | 先檢查 `auth.uid()`，未登入會拒絕 |
| `admin_adjust_growth_points(uuid,integer,text)` | 是 | 呼叫 `is_admin()`；正式 `is_admin()` 以 `auth.uid()` 對照 profiles admin 角色，匿名呼叫不會通過 |
| `admin_reset_growth_member(uuid,text)` | 是 | 明確拒絕 `auth.uid()` 為 NULL，並要求 `is_admin()` |

即使部分函式有內部驗證，仍應撤銷不必要的 anon EXECUTE，採取最小權限；這可降低未來函式改版時漏掉內部檢查的風險。

### 9.3 Trigger functions 與內部 helper

- `growth_registration_reward()` 與 `growth_result_reward()` 是觸發器函式，會在報名／成績事件中呼叫 `award_growth_points`。
- `award_growth_points` 也由任務完成、成就解鎖及獎勵兌換等 SECURITY DEFINER 流程內部呼叫；不需要讓瀏覽器直接呼叫。
- `_refresh_growth_level_internal(uuid)` 應只供受控資料庫函式內部使用，不應開放給 API 角色。
- 撤銷 API 角色對 trigger function 的直接 EXECUTE，不會刪除 trigger binding；候選 SQL 測試也包含「撤權後觸發器仍能運作」的驗證。

### 9.4 前端實際呼叫端

分支前端目前找到以下呼叫：

| 檔案／位置 | RPC | 使用目的 |
|---|---|---|
| `app.js` 約第 604 行 | `record_growth_activity()` | 記錄會員活躍 |
| `app.js` 約第 611 行 | `complete_growth_task(text)` | 更新本人任務進度 |
| `app.js` 約第 613 行 | `check_growth_achievements(uuid)` | 檢查本人成就 |
| `app.js` 約第 614 行 | `refresh_growth_level(uuid)` | 更新本人等級 |
| `app.js` 約第 168 行 | `use_growth_coupon(uuid)` | 使用本人優惠券 |
| `app.js` 約第 687 行 | `redeem_growth_reward(uuid)` | 兌換獎勵 |
| `admin.js` 約第 860 行 | `admin_reset_growth_member(uuid,text)` | 管理員重置指定會員成長資料 |
| `admin.js` 約第 883 行 | `admin_adjust_growth_points(uuid,integer,text)` | 管理員調整指定會員積分 |

補充：
- `admin.js` 的獎勵新增／編輯／刪除目前直接使用 `growth_rewards` REST table API 與 RLS policies；本分支未找到它呼叫 `admin_upsert_growth_reward` 或 `admin_delete_growth_reward` 的程式碼。
- 本分支前端檔案中未找到 `check_activity_badges` 的直接呼叫；保留 authenticated 執行權限前，仍應確認是否有外部或排程呼叫者。
- 前端沒有直接呼叫 `award_growth_points` 或 `_refresh_growth_level_internal` 的需求。

### 9.5 候選 Migration 與測試的相符性

`202611160001_growth_function_authorization_hardening.sql` 已包含下列修正方向：
- 管理員獎勵函式改用 `caller_role IS DISTINCT FROM 'admin'`，並拒絕 NULL 身分。
- `award_growth_points`、內部等級 helper 不授權 anon/authenticated 直接執行。
- 成就、等級、徽章函式加入本人／管理員範圍檢查。
- 任務、活躍、兌換、優惠券等使用者 RPC 僅保留 authenticated allowlist。
- 以完整 ACL allowlist 撤銷其餘 SECURITY DEFINER 函式的 API 角色 EXECUTE，並保留 `is_admin()` 的 anon EXECUTE，以供既有 RLS policy 使用。
- SQL 測試檔包含 anon 拒絕、會員跨帳號拒絕、管理員允許、內部 helper 拒絕，以及 trigger 撤權後仍能執行的檢查。

### 9.6 本階段判定與限制

**判定：正式資料庫目前不符合 Growth 權限候選修補版的安全目標；至少六個高優先級函式存在明確授權缺口。**

候選 Migration 是可供測試的修補方向，不等於已獲准直接執行。它的 ACL 區塊會重新整理 public schema 中整批 SECURITY DEFINER 函式的 EXECUTE 權限，影響範圍不只 Growth。執行前仍須完成整份 allowlist 與每個非 Growth RPC 呼叫端的相容性核對，並在獨立測試環境跑完整 SQL 測試。

本次沒有執行候選 Migration、沒有呼叫寫入型 RPC、沒有修改正式資料庫，也沒有改動前端程式碼。

## 10. Growth 修補 Migration 的完整 ACL 相容性檢查（2026-11-18）

### 10.1 既有前端 RPC 呼叫與候選 allowlist

除 Growth 本身外，也比對了 `app.js`、`admin.js` 中的 RPC 呼叫及管理訂單的動態 RPC 名稱。

目前已在前端找到的 RPC：
- 會員／一般功能：`close_my_support_ticket`、`use_growth_coupon`、`checkin_competition`、`join_competition_waitlist`、`record_growth_activity`、`complete_growth_task`、`check_growth_achievements`、`refresh_growth_level`、`redeem_growth_reward`、`increment_download_count`。
- 管理功能：`admin_mark_order_paid`、`admin_complete_order`、`admin_cancel_order`、`admin_promote_competition_waitlist`、`admin_settle_competition`、`admin_activity_analytics`、`admin_grant_competition_reward`、`admin_mark_competition_member_attendance`、`admin_reset_growth_member`、`admin_adjust_growth_points`、`admin_upsert_video`、`admin_delete_video`。

上述有實際前端呼叫的 RPC 均列在候選 Migration 的 authenticated allowlist 內。部分其他函式目前沒有在這兩個前端檔案中找到直接呼叫，但可能供資料庫政策、觸發器或其他受控流程使用；不能只因前端搜尋不到就刪除或撤銷其內部用途。

### 10.2 正式資料庫現況 ACL 矩陣

正式資料庫目前查到 36 個 public SECURITY DEFINER 函式。除 `is_admin()` 與一個內部 award helper 的特殊狀態外，絕大多數目前對 anon、authenticated、service_role 都有 EXECUTE；三個觸發器函式亦仍可被 API 角色直接 EXECUTE。

重要例外：
- `award_growth_points(...)`：anon=true、authenticated=false、service_role=true。
- `is_admin()`：anon=false、authenticated=true、service_role=true。
- `check_competition_registration_rules()`、`ensure_visitor_profile()`、`growth_registration_reward()`、`growth_result_reward()`：目前 API 角色可直接 EXECUTE；它們屬 trigger-returning routines，應保留 trigger binding，但不應當成可直接呼叫的 RPC。

### 10.3 RLS policies 對 is_admin() 的依賴

本次另查到多項 RLS policies 在條件式中呼叫 `public.is_admin()`，包括：
- 公開讀取政策：`competitions`、`competition_results`、`forms`、`form_questions`、`products`。
- 會員／管理政策：`profiles`、`announcements`、`growth_*`、`notifications`、`coupons`、`support_tickets` 等。

目前正式資料庫 `anon` 沒有 `is_admin()` 的 EXECUTE；候選 Migration 特別保留並授予 `is_admin()` 給 anon、authenticated，且該函式在 `auth.uid()` 為 NULL 時會回傳 false。這項 grant 不可被誤刪，否則部分使用 `is_admin()` 的 RLS 查詢可能因函式權限不足而失敗。候選 Migration 將 `is_admin_user()` 另列為 authenticated allowlist，不能與 `is_admin()` 混為一談。

### 10.4 Trigger 相容性

正式資料庫查到五個 SECURITY DEFINER trigger-returning functions：
- `assign_member_no_and_nickname()`
- `check_competition_registration_rules()`
- `ensure_visitor_profile()`
- `growth_registration_reward()`
- `growth_result_reward()`

這五個函式都必須保留各自既有的 trigger binding；修補前後應逐一核對。候選 Migration 對 trigger functions 撤銷 API role 的直接 EXECUTE，但不移除 trigger binding；候選 SQL 測試有一個 fixture 驗證撤銷直接 EXECUTE 後，觸發器仍會執行。正式環境仍需在隔離測試資料庫重現全部現有 trigger 行為，不能只依 fixture 推斷正式資料庫已通過。

### 10.5 最終相容性判定

- 候選 allowlist 已包含本次找到的前端 RPC 呼叫端。
- `is_admin()` 的 anon EXECUTE 是既有 RLS policy 相容性要求，必須保留。
- trigger functions 應撤銷直接 API EXECUTE，但保留現有 trigger bindings。
- 其餘未在前端找到直接呼叫的 SECURITY DEFINER routines，仍須依其 trigger、policy、資料庫內部呼叫及排程用途核對。
- 候選 Migration 對 public SECURITY DEFINER 函式採 fail-closed ACL 整理，影響面大於 Growth 單一功能；應先在與正式 schema 相符的隔離資料庫執行完整測試，再審查每個例外。

**本輪仍為唯讀審查。** 沒有套用候選 Migration、修改 ACL、呼叫寫入型 RPC、執行使用者資料操作或變更前端程式碼。
