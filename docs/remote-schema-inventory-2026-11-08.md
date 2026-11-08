# 正式資料庫 Schema 盤點與 Migration 歷史核對 v0.2

> 日期：2026-11-08（Asia/Taipei）
> 專案：smart-class / Supabase project ref `fsoowongtavlsrwvzbze`
> 分支：`feature/maintenance-system`
> 本文件是唯讀盤點報告，不是完整 pg_dump，也不是 Migration。

## 1. 本輪結論

1. 已取得三個 repository migration 檔案的 GitHub 檔案提交歷史，並確認兩個 App Release 腳本是先後提交的不同版本。
2. 正式資料庫目前結構與較晚提交的 `202610310001_app_releases.sql` 相符；與較早的 `20261031_app_releases.sql` 不相符。
3. 行事曆欄位與索引已存在於正式資料庫，Git 歷史中相關功能於 2026-11-01 的合併提交加入。
4. 已完成 public schema 的 metadata inventory：45 個 relation、420 個 columns、98 個 RLS policies、9 個 triggers、38 個 functions。
5. **尚未取得完整可重建資料庫的 DDL snapshot**。本輪只有 catalog inventory 和部分重點物件定義，不能宣稱已完成 schema dump。
6. 目前工作環境沒有 Supabase CLI、psql 或 pg_dump；repository 的 `supabase/` 目錄也沒有 `config.toml`。因此不能安全地執行官方 remote schema pull／本機 db reset 工作流程。

## 2. Git Migration 歷史

### 2.1 App Release 腳本 A（較早）

- 檔案：`supabase/migrations/20261031_app_releases.sql`
- commit：`fb0b6b1a94821fbe384c9db391c3ae3b95741c19`
- 時間：2026-10-31 06:05:23 UTC
- commit message：Add App release updates table and RLS policies
- 內容包含 `is_latest`、`apk_url HTTPS` constraint、`app_releases_published_idx`、`is_app_release_admin()`。
- 正式資料庫目前沒有 `is_latest`、該索引及該函式，因此現況與此檔不符。

### 2.2 App Release 腳本 B（較晚）

- 檔案：`supabase/migrations/202610310001_app_releases.sql`
- commit：`0573e012bba978acd158d6c48643976c4c9f6da9`
- 時間：2026-10-31 06:06:00 UTC
- commit message：Add secure app release metadata table migration
- 內容包含 `published_at`、`created_by`、`version_code > 0`、唯一版本代碼與管理員 policies。
- 正式資料庫的欄位、constraints、indexes 和 policies 與此版本相符。
- SQL 註解寫明在 Supabase Dashboard SQL Editor 執行一次；但這仍不是資料庫端的執行證明。

### 2.3 Calendar migration

- 檔案：`supabase/migrations/26.11.3_calendar_fields.sql`
- Git 歷史：2026-11-01 的合併提交 `929cd3564e1a6e4d6d2fae7fe0b897f876699ac7`（Add calendar and event date management for 26.11.3）。
- 正式資料庫已存在 `event_date`、`event_end_date`、`event_date_source`、`event_date_confirmed`、兩個日期 CHECK 與 calendar partial index。
- 結構吻合是現況證據，不是 migration history 執行證明。

### 2.4 History 判定

| 檔案 | Git 歷史 | 正式資料庫結構 | 可否標記 applied |
|---|---|---|---|
| `20261031_app_releases.sql` | 10/31 06:05:23 UTC 提交 | 不吻合 | **不可** |
| `202610310001_app_releases.sql` | 10/31 06:06:00 UTC 提交 | 吻合 | **暫不可；需部署／手動執行證據與完整物件核對** |
| `26.11.3_calendar_fields.sql` | 11/01 合併提交 | 吻合 | **暫不可；需完整物件核對與部署／手動執行證據** |

Git commit 能證明檔案何時進入 repository，不能證明 SQL 是否在 Supabase 執行。不得把 commit timestamp 當作 migration applied timestamp。

## 3. 正式資料庫唯讀 Inventory

### 3.1 執行環境與 schema

- PostgreSQL：17.6
- Inventory capture time：2026-11-08 15:46:04 +08:00
- 使用者 schema：
  - `auth` — owner supabase_admin
  - `extensions` — owner postgres
  - `graphql` — owner supabase_admin
  - `graphql_public` — owner supabase_admin
  - `public` — owner pg_database_owner
  - `realtime` — owner supabase_admin
  - `storage` — owner supabase_admin
  - `vault` — owner supabase_admin
- `private` schema 不存在。

### 3.2 public relation 統計

- Relations：45
- Columns：420
- RLS policies：98
- Triggers：9
- Functions：38
- `activity_member_stats` 是 view，且目前 relation metadata 顯示 RLS 不適用／未啟用；既有 Advisor 曾回報 security definer view ERROR，需在後續完整 snapshot 一併保存其 view definition。

### 3.3 public relations 名稱

`activity_badges`, `activity_member_stats`, `ai_announcement_generations`, `announcement_reads`, `announcements`, `app_releases`, `competition_attendance`, `competition_categories`, `competition_registrations`, `competition_results`, `competition_reward_grants`, `competition_reward_rules`, `competition_waitlist`, `competitions`, `coupons`, `device_push_tokens`, `download_files`, `form_answers`, `form_questions`, `form_responses`, `forms`, `growth_achievement_unlock_history`, `growth_achievements`, `growth_activity_days`, `growth_levels`, `growth_point_transactions`, `growth_reset_history`, `growth_reward_redemptions`, `growth_rewards`, `growth_tasks`, `growth_user_achievements`, `growth_user_tasks`, `member_no_counter`, `notifications`, `order_items`, `orders`, `products`, `profiles`, `quick_links`, `site_settings`, `support_tickets`, `user_activity_badges`, `videos`, `visitor_accounts`, `visitor_profiles`.

45 個 relation 中，44 個是 table，1 個是 view；44 個 table 都回報已啟用 RLS。這只是 relation 層級摘要，不代表每個 policy 都已通過安全審查。

### 3.4 已安裝 extensions

- `pg_stat_statements` 1.11（extensions）
- `pgcrypto` 1.3（extensions）
- `plpgsql` 1.0（pg_catalog）
- `supabase_vault` 0.3.1（vault）
- `uuid-ossp` 1.1（extensions）

Supabase extension listing 同時列出可用但未安裝的 extension；本節只列 catalog 中實際已安裝者。

### 3.5 關鍵物件摘要

- `public.profiles` 欄位包含 id、role、created_at、nickname、member_no、growth_points、growth_level。
- `public.app_releases` 欄位包含 id、version_code、version_name、release_notes、apk_url、published、created_at、published_at、created_by。
- `public.announcements` 包含四個 calendar 欄位。
- `public.is_admin()` 是新維護系統既定設計要沿用的 admin check；仍需在完整 snapshot 確認函式定義、owner、EXECUTE grants 與實際呼叫路徑。

## 4. 重要發現：目前設計文件的資料庫連線模型不一致

本分支目前存在兩種尚未收斂的描述：

- `maintenance-database-design-v0.3.md`：Edge Function 使用伺服器端 `SUPABASE_DB_URL` + Postgres driver 直接連線 private schema。
- `maintenance-sql-readiness-review-v0.1.md`：建議使用 public RPC gateway + 使用者 JWT。

兩者不是同一種執行身分模型，不能直接混用。若 DB URL 最終以 postgres／owner 角色連線，RLS 不是隔離邊界；若以使用者 JWT RPC，則需確定 private schema 函式權限與 PostgREST 暴露方式。**正式 SQL 生成前，必須先選定唯一模型並用實際連線角色驗證。**

此外，`docs/sql-drafts/README.md` 已明確記錄目前執行環境沒有 Supabase CLI，且早期 DDL 草案不是可部署 Migration。

## 5. 完整 Snapshot 缺口

本輪沒有取得完整 DDL，缺少：
- 全部 table／view／materialized view 的完整 CREATE 定義。
- 全部 constraints、indexes、sequences、identity 定義。
- 所有 functions／procedures 的完整 source、owner、security mode、search_path、grants。
- triggers 與 trigger functions 的完整定義。
- RLS policies、table grants、column grants、schema grants 的完整匯出。
- storage／auth 等 Supabase managed schema 的自訂物件差異。
- Data API Exposed schemas Dashboard 設定。
- Migration execution／manual SQL Editor 執行紀錄。

不能用本報告替代 `supabase db pull` 或 `pg_dump --schema-only`。

## 6. 下一步執行計畫

1. 在本機或受控開發環境安裝／確認 Supabase CLI，先執行 `supabase --version` 與 `supabase --help`，按該版本官方文件確認 `db pull` 用法。
2. 確認 repository branch 並建立／核對 `supabase/config.toml`；不要猜測 project settings。
3. 使用已授權的 CLI 登入方式執行 remote schema pull，只匯出 schema，不匯出資料；避免將 DB 密碼貼到聊天或提交 Git。
4. 將完整 snapshot 存放於功能分支，先 review managed schemas 與 extensions。
5. 根據完整 DDL 與部署／手動執行證據，製作逐檔 migration history repair 對照表。
6. 修正維護系統連線架構文件的矛盾，再生成維護 Migration。

## 7. 安全紀錄

- 本輪 Supabase 操作只有 SELECT／metadata 讀取。
- GitHub 只讀取歷史與檔案；新增本報告除外。
- 未執行 DDL／DML、migration repair、db push、apply_migration。
- 未建立 private schema、table、role、function 或 migration history。
- 未部署 Edge Function 或網站。
- 未建立 Supabase project／branch，未新增付費資源。
- 未讀取或輸出 secrets。
