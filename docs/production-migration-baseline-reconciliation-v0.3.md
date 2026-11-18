# 正式資料庫 Baseline 與 Migration 歷史核對 v0.3

> 日期：2026-11-18（Asia/Taipei）
> 專案：`private-website` / `fsoowongtavlsrwvzbze`
> Repository branch：`feature/v26.11.7-maintenance-next`
> Repository HEAD（盤點時）：`bdbb9ec9d3c680ab5ca894aec37f7ef26f928be3`
> 性質：正式 Supabase 唯讀 metadata / catalog 盤點；不是 migration，不授權任何正式 DDL、DML、repair 或部署。

## 1. 結論

**正式資料庫仍不具備可安全執行新 Migration 的基線條件。**

本次透過 Supabase 專案工具重新確認：
- 專案為 `ACTIVE_HEALTHY`，PostgreSQL 17.11。
- Supabase Migration 清單為空（`migrations: []`）。
- PostgreSQL catalog 中沒有 `supabase_migrations` schema，也沒有 `private` schema。
- 找不到任何 `maintenance_*` 資料表或函式。
- 正式資料庫並非空白：共有 44 張 `public` 應用資料表，且已有大量既存 policies、functions、triggers、extensions。
- 正式環境目前有 6 個既有 Edge Functions，未包含五支 maintenance Edge Functions。

因此不可直接執行維護 SQL 草案、`supabase db push`、`migration repair`，也不可手動建立 migration history。

## 2. 本次正式資料庫快照（唯讀）

| 項目 | 本次結果 |
|---|---:|
| Project status | `ACTIVE_HEALTHY` |
| PostgreSQL | 17.11.0.003 |
| Supabase Migration list | 0 筆 |
| `supabase_migrations` schema | 不存在 |
| `private` schema | 不存在 |
| 非系統 schema | auth、extensions、graphql、graphql_public、public、realtime、storage、vault |
| 全部可列出的資料表 | 85 張（包含 Supabase managed schemas） |
| `public` 普通／分割資料表 | 44 張 |
| `public` 已啟用 RLS | 44 / 44 |
| `public` FORCE RLS | 0 / 44 |
| `public` RLS policies | 98 |
| `public` 非內部 triggers | 7 |
| `public` functions | 38 |
| `public` SECURITY DEFINER functions | 36 |
| `public` ordinary views | 1 |
| 已安裝 extensions | pg_stat_statements、pgcrypto、plpgsql、supabase_vault、uuid-ossp |

補充：`auth.schema_migrations`、`realtime.schema_migrations`、`storage.migrations` 是 Supabase 服務自身的 migration 記錄，不是本專案應用程式 schema 的 migration ledger。不得將它們當成 `supabase_migrations.schema_migrations`。

## 3. 正式 public 應用資料表清單

本次 catalog 回傳的 44 張 `public` 資料表如下。這份清單是 baseline inventory，不包含完整欄位、constraints、indexes、policies、triggers 與 grants 定義。

1. `announcements`
2. `site_settings`
3. `visitor_profiles`
4. `profiles`
5. `products`
6. `visitor_accounts`
7. `support_tickets`
8. `coupons`
9. `competitions`
10. `competition_results`
11. `quick_links`
12. `forms`
13. `form_questions`
14. `form_responses`
15. `form_answers`
16. `competition_categories`
17. `notifications`
18. `member_no_counter`
19. `competition_registrations`
20. `announcement_reads`
21. `growth_levels`
22. `growth_point_transactions`
23. `growth_tasks`
24. `growth_user_tasks`
25. `growth_achievements`
26. `growth_user_achievements`
27. `growth_activity_days`
28. `growth_rewards`
29. `growth_reward_redemptions`
30. `growth_achievement_unlock_history`
31. `growth_reset_history`
32. `videos`
33. `ai_announcement_generations`
34. `competition_attendance`
35. `competition_waitlist`
36. `activity_badges`
37. `user_activity_badges`
38. `competition_reward_rules`
39. `competition_reward_grants`
40. `download_files`
41. `orders`
42. `order_items`
43. `app_releases`
44. `device_push_tokens`

## 4. Repository migrations 目錄現況

盤點時目前分支 `supabase/migrations/` 有 5 個 SQL 檔案：

| 檔案 | 既有核對狀態 | 本階段處置 |
|---|---|---|
| `202610310001_app_releases.sql` | 正式 `app_releases` schema 與此版本相符；但執行歷史無法證明 | 保留作為 schema 相容候選；不可直接 repair |
| `20261031_app_releases.sql` | 與前一檔為衝突替代版本；正式 DB 缺少其 `is_latest` 等結構 | 不可套用；保留歷史來源待查 |
| `26.11.3_calendar_fields.sql` | 正式 `announcements` 行事曆欄位、constraints、index 與此檔相符；執行歷史無法證明 | 保留作為 schema 相容候選；不可直接 repair |
| `202611160001_growth_function_authorization_hardening.sql` | 既有比較文件指出正式函式本體／ACL 尚未完整呈現預期變更 | 不可直接套用；需逐函式與呼叫端驗證 |
| `202611170001_default_privileges_and_trigger_hardening.sql` | 既有比較文件指出正式 default ACL 與預期撤權狀態不一致 | 不可直接套用；需評估全域 default ACL 影響及 trigger 相容性 |

注意：
- Git 檔案存在、commit 時間、正式 schema 看起來相似，都不能單獨證明該 migration 曾在正式環境執行。
- 兩份 App Releases SQL 不可被當成同一功能的連續 migration；variant B 不得接續套用到目前正式 schema。
- 兩份 hardening migration 牽涉既有 SECURITY DEFINER routines、API role ACL、trigger function 與預設權限，不能為了補 migration history 而整包執行。
- 本次沒有修改上述五個 migration 檔案。

## 5. Maintenance 系統正式環境狀態

本次正式 catalog 查詢確認：
- `private` schema 不存在。
- 六張 `private.maintenance_*` 資料表不存在。
- 五個 `maintenance_*` RPC 不存在。
- Supabase 已部署 Edge Functions 清單中沒有以下 maintenance functions：
  - `maintenance-status`
  - `maintenance-admin-list`
  - `maintenance-event-create`
  - `maintenance-event-update`
  - `maintenance-event-action`

目前正式環境列出的六個 Edge Function 為：
- `ai-generate-announcement`
- `set-visitor-password`
- `create-visitor`
- `send-announcement-push`
- `clever-service`
- `manage-visitors`

開發分支唯一維護 SQL 草案仍位於 `supabase/sql/maintenance-private-schema-rpc-draft-v0.1.sql`，不在 migrations 目錄。此草案尚未核准為正式 Migration。

## 6. 尚未完成的 baseline 證據

本次是 metadata/catalog inventory，不等同於完整 schema dump。以下項目仍需受控環境處理：

1. 使用 Supabase CLI 對正式遠端 schema 執行受控的 schema pull，產生可版本化的完整 baseline snapshot；需先確認 CLI 版本與該版本的 `db pull --help`。
2. snapshot 必須包含應用程式需要保留的 tables、columns、constraints、indexes、functions、triggers、RLS policies、grants、default privileges、views、extensions；並排除 Supabase managed system objects。
3. 在空白 PostgreSQL 17 測試資料庫驗證 snapshot 能重建預期 schema。
4. 逐項比較 baseline snapshot 與五份既有 migration，特別處理 App Releases 衝突與兩份 hardening migration。
5. 取得可信的部署／SQL Editor 執行紀錄；若沒有歷史證據，將其標示為「live schema matches」而非「migration applied」。
6. 在 Supabase Dashboard 確認 Data API Exposed schemas；catalog 查詢不能代替 Dashboard 設定確認。
7. 完成後另寫一份明確的 history reconciliation proposal，逐筆說明是否需要 repair、理由、風險及回復方式；不得直接手動插入 history rows。

目前 ChatGPT 工具可做唯讀 catalog 查詢，但沒有在此環境執行 Supabase CLI / `pg_dump` 的受控本機能力，因此完整 remote schema pull 與空白資料庫重建測試尚未完成。

## 7. 本次操作界線

- 僅使用 Supabase project metadata、migration listing、table inventory、Edge Function inventory 及 PostgreSQL catalog SELECT。
- 沒有執行 DDL 或 DML。
- 沒有建立或修改 `supabase_migrations` schema/table。
- 沒有執行 `migration repair`、`db push`、`db reset` 或 `apply_migration`。
- 沒有部署、刪除或修改 Edge Functions。
- 沒有讀取或匯出正式使用者資料列。
- 沒有建立 Supabase project/branch 或付費資源。

## 8. 結論與下一個安全步驟

**正式 Baseline 狀態：INCOMPLETE / BLOCKED。**

目前可以確認正式 DB 的物件規模、主要 schema 與 maintenance 功能尚未部署，但還沒有可重建、可稽核的完整 schema snapshot。下一步不是 repair，也不是套用任何 migration；應先在使用者可控且 CLI 版本已確認的本機環境，完成 remote schema pull 與空白 PostgreSQL 17 重建驗證。只有這份 baseline 證據完成後，才可提出 migration history reconciliation 計畫。

**本文件不構成任何正式環境執行授權。**
