# Smart Class 正式環境基線與維護系統文件統一紀錄 v1.0

> 更新日期：2026-11-28  
> 對應專案：`johnjohn114/smart-class`  
> 檢查分支：`integration/growth-registration-and-reward-security-20261125`  
> 檢查 commit：`6f661d9d156b88396c1eb6cef40097960c8b49f2`  
> 本文件用途：統一目前可確認的正式資料庫現況、候選 Migration 分類、文件版本差異與上線阻擋條件。  
> **狀態：唯讀盤點完成；正式 Migration、部署及合併仍未核准。**

## 1. 本次確認的正式環境基線

2026-11-28 對正式 Supabase 執行唯讀 catalog 查詢，結果：

| 項目 | 結果 |
|---|---|
| PostgreSQL | 17.11 |
| `supabase_migrations.schema_migrations` | 不存在 |
| `auth.schema_migrations` | 存在，屬 Auth/GoTrue 內部遷移紀錄 |
| `realtime.schema_migrations` | 存在，屬 Realtime 內部遷移紀錄 |
| `storage.migrations` | 存在，屬 Storage 內部遷移紀錄 |
| `private` schema | 不存在 |
| private schema 資料表 | 0 |
| public `maintenance_%` RPC | 0 |
| public `maintenance_%` relation | 0 |

上述三個服務內部 migration ledger **不是**本網站 `supabase/migrations/` 的應用程式遷移紀錄。不得將其版本當成應用 Migration 已執行的證據。

先前唯讀比對已確認：
- 正式 `public.app_releases` 欄位、主要限制與 RLS policy，符合 `202610310001_app_releases.sql` 的建表設計。
- 正式 `public.announcements` 行事曆欄位、CHECK constraints 與 partial index，符合 `26.11.3_calendar_fields.sql`。
- 正式資料庫沒有 `private` schema、六張維護資料表或五個維護 RPC；五支維護 Edge Functions 亦尚未部署。

這些是 schema 現況比對，不是 migration history 證明，也不授權執行 `migration repair`、`db push` 或重播 SQL。

## 2. Repository Migration 分類與處理決策

### 2.1 已與正式 schema 現況相符的歷史 SQL

| 檔案 | 現況比對 | 本文件處理方式 |
|---|---|---|
| `202610310001_app_releases.sql` | 正式 app_releases 結構與其設計相符 | 作為 schema 比對參考；不重跑、不標記 applied |
| `26.11.3_calendar_fields.sql` | 正式 announcements 行事曆欄位、限制與索引相符 | 作為 schema 比對參考；不重跑、不標記 applied |

### 2.2 衝突的 App Releases 變體

`20261031_app_releases.sql` 是另一份不同設計：包含 `is_latest`、`is_app_release_admin()` 及不同索引/欄位配置。正式表沒有該變體的 `is_latest` 欄位與 helper。

**決策：不得將 `20261031_app_releases.sql` 與 `202610310001_app_releases.sql` 當作兩個可依序執行的遷移。** 目前正式 schema 與第一份相符；第二份列為衝突/不採用的歷史候選，需另行整理檔案狀態，但不可為了整理而改動正式資料庫。

### 2.3 候選安全與成長系統 Migration

以下檔案位於候選分支，尚不可視為正式環境已套用：

1. `202611160001_growth_function_authorization_hardening.sql`
2. `202611170001_default_privileges_and_trigger_hardening.sql)
3. `202611250001_protect_profile_fields_growth_system_updates.sql`
4. `202611250002_admin_growth_reward_null_auth_guard.sql`
5. `202611250003_growth_achievement_user_scope_guard.sql`
6. `202611250004_security_definer_execution_scope_guard.sql`
7. `202611250005_activity_member_stats_and_public_leaderboard.sql`

依賴關係與風險摘要：
- 先完整核對 20261116/17 的函式替換、default ACL 與 trigger 行為，再評估 20261125 成長系統修補。
- 202611250001 會改變成長積分寫入路徑及受保護 profile 欄位的更新方式；須確保所有合法的積分來源、管理員流程、任務/報名/簽到流程皆有測試。
- 202611250002、003 加強身分與目標會員範圍檢查；須保留本人操作與管理員跨會員操作的既有合法路徑。
- 202611250004 影響多個 SECURITY DEFINER 函式的 EXECUTE ACL；需逐函式核對前端、Edge Function、trigger、RLS policy、service_role 及既有後端消費者，不能只看 CI 的 fixture 測試。
- 202611250005 涉及活動統計 view 與公開排行榜 projection；需完成隱私/公開欄位決策、讀取者權限及前端相容性驗證後，才可納入發布。

### 2.4 維護系統 Migration

`20261117121103_maintenance_system_initial.sql` 建立獨立的六表 private schema 模型及五個 public RPC。它不是成長系統修補的一部分，亦不可與舊版四表 `public.maintenance_*` 設計混用。

必要前提：
- 正式 `public.is_admin()` 存在，並可由 authenticated 呼叫者依預期判斷管理員。
- `private` schema 必須保持不在 Supabase Data API Exposed schemas。
- 以 anon、一般 authenticated、admin 的真實 GoTrue JWT 驗證 SECURITY INVOKER、table grants、RLS、RPC、audit 與 idempotency 行為。
- 確認正式 Edge Function secrets、CORS allowlist、Gateway JWT 設定，再部署後做 smoke test。
- 維護功能旗標維持關閉，直到 schema、functions、環境設定與 smoke test 全部完成。

## 3. 建議的遷移治理順序（不是正式執行指令）

1. **凍結基線**：保存目前正式 schema/catalog 快照與 Git commit；逐項比對表、欄位、constraints、indexes、views、functions、triggers、RLS、GRANT、default ACL、extensions。
2. **整理歷史差異**：將已與正式 schema 相符的歷史 SQL、衝突變體及候選 SQL 分類；不得僅憑檔名推定 applied 狀態。
3. **建立應用程式 migration adoption/baseline 方案**：選定可追溯且可重現的基準方式，明確記錄哪些物件屬於既有正式基線、哪些是未套用變更。方案須先在隔離環境驗證；不得直接對正式資料庫執行 repair。
4. **分開驗證功能群**：先驗證成長/權限修補的完整依賴與回歸，再單獨驗證維護系統六表/RPC/Edge Functions。不要把兩組功能視為同一個不可分割的部署。
5. **審查所有消費者**：對每個將被撤權或替換的函式，列出前端、Edge Functions、trigger、RLS policies、service_role 及其他自動化呼叫端。
6. **隔離環境完整測試**：在 PostgreSQL 17 + GoTrue-issued JWT + PostgREST 測試完整 migration 順序、anon/member/admin/service_role 權限、交易、併發、冪等、回滾及既有功能。
7. **人工發布核准**：確認 Data API schema allowlist、環境變數、CORS、監控、回滾方案及發布窗口；再由使用者另行明確授權任何正式變更。

以上是建議治理順序，不代表已完成完整 migration graph，也不代表現有候選檔案可直接依日期排序套用。

## 4. 文件版本統一與歷史文件使用方式

| 文件 | 本次定位 | 使用原則 |
|---|---|---|
| `maintenance-api-spec-v0.7.md` | 維護 API 最新產品/技術契約 | 作為 API 行為與 v1 保留策略的主要規格 |
| `maintenance-rpc-sql-contract-v0.1.md` | Edge 到 RPC 的參數/回應契約 | 與 v0.7 一起使用；若有差異，先修訂契約再改程式 |
| `maintenance-architecture-baseline-decision-v0.1.md` | 六表 private-schema 架構決策 | 作為架構選擇依據；其中早期 CI/分支資訊屬歷史 |
| `maintenance-prelaunch-review-v0.1.md` | 早期上線前審查紀錄 | 保留當時發現；較新的 v0.7 已定稿項目以新規格為準 |
| `maintenance-real-supabase-readonly-audit-v0.2.md` | 早期正式環境唯讀審查 | 保留歷史；其中「缺少 request hash」已被後續 SQL/API v0.7 修正，不可當成目前狀態 |
| `maintenance-compatibility-permission-dependency-audit-v0.1.md` | 權限與依賴的歷史深度審查 | 其中 2026-11-17 的候選分支與 CI SHA 不代表目前 PR head；逐項重新核對當前分支 |
| `activity-leaderboard-migration-baseline-and-rollback-evidence-2026-11-18.md` | activity view/leaderboard 的基線與回滾證據 | 作為 view 專題依據；回滾 SQL 僅供審查，非執行授權 |

重要修訂：
- 舊文件對 idempotency hash 的「尚未實作」描述，屬於早期 SQL 草案狀態。候選 maintenance migration 已包含 32-byte SHA-256 request hash，API v0.7 亦記載同 key 同 payload 重播、不同 payload 拒絕及永久保留決策。
- 舊文件曾把 429 rate limit 列為 API 錯誤碼；API v0.7 已明確移除 v1 的 429 承諾，且目前 Edge Function 沒有自建 per-IP/per-user rate limiter。不得宣稱已具備應用層限流。
- Audit log append-only 不等於 DB 層完全不可偽造：authenticated admin 的 INSERT 權限仍是文件揭露的限制。
- CI 的 GoTrue/PostgREST/PG17 成功，只代表隔離測試通過，不代表正式 Supabase 的 Data API allowlist、JWT Gateway、CORS、secrets 或部署後 smoke test 已驗收。

## 5. 正式發布阻擋條件

以下任一項未完成，維持 HOLD：
- [ ] 應用程式 migration baseline/adoption 方案完成並經隔離環境驗證。
- [ ] 正式 schema 與所有候選 Migration 的完整差異及依賴矩陣完成。
- [ ] SECURITY DEFINER 函式 ACL 逐項核對所有消費者，包括 service_role。
- [ ] Data API Exposed schemas 已由 Dashboard 人工確認不包含 `private`。
- [ ] 成長系統修補與 activity leaderboard 的完整回歸測試完成。
- [ ] 維護系統以 GoTrue-issued anon/member/admin JWT 完成 RPC/RLS/PostgREST 驗證。
- [ ] 正式 Edge Function secrets、CORS、Gateway 設定與部署後 smoke test 計畫完成。
- [ ] Audit/idempotency 永久保留策略、隱私揭露與維運接受度確認。
- [ ] 回滾腳本已在隔離環境演練，並確認資料保留/相容性風險。

## 6. 安全界線與本次執行紀錄

本次只做 GitHub 原始碼/文件讀取、建立文件分支與正式 Supabase SELECT catalog 查詢。沒有：
- 執行正式 DDL/DML、GRANT/REVOKE、Migration 或 migration repair；
- 部署或修改 Edge Functions / GitHub Pages；
- 合併 PR #41；
- 建立付費 Supabase project/branch 或啟用付費服務；
- 讀取或要求任何密碼、access token、refresh token 或 service_role key。

**最終狀態：文件基線已整理；正式 Migration、部署與合併仍為 HOLD。**
