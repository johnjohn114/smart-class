# Maintenance Migration 部署對照表 — 2026-11-22

> 性質：唯讀環境核對與部署決策紀錄。  
> 範圍：GitHub `main`、PR #34 base/head、已知 single-pass SQL draft、正式 Supabase 專案。  
> 安全界線：本文件不授權 SQL 執行、migration repair、migration 重寫、PR 合併、Edge Function 部署或 feature flag 變更。

## 1. 結論摘要

**目前不可部署 Maintenance migration。**

- 正式 Supabase 未找到 Maintenance schema、六張 Maintenance tables、Maintenance RPCs 或五支 Maintenance Edge Functions。
- Supabase migration listing 回傳空集合；資料庫 catalog 中未找到 `supabase_migrations` schema/table。這不能證明任何 SQL 從未在其他環境執行，也不能單憑空 ledger 推定正式資料庫從未執行過 migration。
- GitHub `main`、PR #34 base/head 的 Maintenance migration 檔案並不一致。
- PR #34 base/head 保留舊的兩段式 migration；single-pass SQL 目前仍位於開發草案路徑，不是正式 timestamped migration。
- 使用者已明確回答「無」：沒有在其他 local/manual/preview/staging/shared database 執行過 Maintenance migrations。此為使用者對已知其他環境的明確確認；production 的全域 migration baseline 缺口仍未解決，因此不可直接 squash、刪除、改名、取代或重排 timestamped migration。

## 2. Git 分支檔案矩陣

| SQL / Migration | `main` | PR #34 base | PR #34 head | 分類與處理 |
|---|---:|---:|---:|---|
| `20261117121103_maintenance_system_initial.sql` | 有 | 有 | 有 | 舊版初始 migration；單獨套用會留下中間權限模型 |
| `20261121140000_maintenance_rpc_least_privilege_upgrade.sql` | 無 | 有 | 有 | 舊版權限升級 migration；需緊接初始 migration 才形成預期 hardened state |
| `supabase/sql/maintenance-private-schema-rpc-draft-v0.1.sql` | 開發草案 | 開發草案 | 開發草案 | Single-pass 候選來源；不是 timestamped migration，不可直接當作正式部署檔 |

**分支定位**
- `main`：目前包含初始 Maintenance migration，但未包含權限升級 migration。
- PR #34 base：`integration/maintenance-pagination-hardening-main-20261121`，包含上述兩份 timestamped migrations。
- PR #34 head：`feature/maintenance-single-pass-migration-20261122`，包含上述兩份 timestamped migrations；PR #34 仍為 Draft、未合併。
- PR #34 head SHA（本次核對）：`9dc3dee2759f017da905035a3107c524ffead481`。

## 3. Migration 內容與依賴關係

| 順序／候選 | 建立或變更內容 | 權限狀態 | 部署判斷 |
|---|---|---|---|
| 舊 migration 1：初始版 | 建立 private schema、六張 Maintenance tables、seed scopes、RLS policies、status/admin RPC 與 trigger | 初始版曾授予 authenticated 管理寫入路徑；尚未達到最終 executor-only mutation model | 不可單獨作為最終部署狀態 |
| 舊 migration 2：權限升級 | 建立 `maintenance_rpc_executor`、啟用 FORCE RLS、調整 mutation policies、撤銷 authenticated 寫入 grants、設定管理 RPC owner/ACL | 轉為專用 NOLOGIN/NOBYPASSRLS executor role 的最小權限設計 | 僅描述舊版兩段式 migration；不是目前 single-pass 草案的 owner 模型 |
| Single-pass draft | 從一開始建立最終 RLS/grants/RPC ownership 模型；四個管理 RPC 為 SECURITY DEFINER 並由內建 `pg_database_owner` 擁有，不建立自訂 executor role | 目標是避免舊 migration 1 與 2 之間的中間權限窗口 | 候選設計已在隔離 CI 路徑測試；仍不是已核准的 timestamped migration |

### 重要差異

舊 migration 1 單獨完成時，authenticated admin 仍有直接寫入資料表的授權路徑，可能繞過 RPC 的 version、idempotency、排程衝突與 audit 流程。舊 migration 2 套用後才轉為 executor-only mutation model。

因此：
- 不可在新環境只套用舊 migration 1。
- 不可把舊 migration 2 當成乾淨環境的 bootstrap migration。
- 不可只新增第三份 single-pass migration 而保留舊 migration 1 在自動套用序列中的前置位置；否則中間權限窗口仍存在。
- 不可直接把兩份舊 SQL 串接成新檔；物件 owner、policy target、grant、function security mode 與 role 建立順序必須完整核對。

## 4. 正式 Supabase 唯讀核對

| 檢查 | 本次觀察 | 解讀 |
|---|---|---|
| Project | `fsoowongtavlsrwvzbze`，`ACTIVE_HEALTHY` | 專案可連線 |
| PostgreSQL | 17.11 | 與隔離測試主要版本相符 |
| Supabase migration listing | 空集合 | 沒有可用的 Supabase migration 清單紀錄 |
| `supabase_migrations` schema/table | 未找到 | 不能用現有 ledger 證明歷史 |
| Maintenance tables | 未找到 | 本次查詢範圍內沒有 Maintenance tables |
| Maintenance RPCs | 未找到 | 未發現 Maintenance functions |
| Maintenance Edge Functions | 五支均未列出 | 本次 Edge Function 清單沒有 Maintenance endpoints |
| 其他既有 public tables | 存在 | 正式 DB 並非空資料庫，不可用空 migration listing 推論資料庫從未變更 |

正式專案 Edge Functions 清單中有其他既有函式；它們不屬於本次 Maintenance migration 核對範圍，不應因本文件而修改。

## 5. 環境歷史與證據缺口

| 環境 | 目前證據 | 狀態 |
|---|---|---|
| 正式 Supabase 專案 | 本次 catalog 未見 Maintenance objects；migration listing 空 | 已唯讀核對；不能推論其他環境 |
| Supabase-managed branches | 已知帳戶盤點未列出開發分支 | 目前未發現 |
| GitHub Actions CI | PostgreSQL、GoTrue、PostgREST 為 workflow disposable services | 測試用，不是持續存在的部署環境 |
| Local / manually managed PostgreSQL | 使用者明確確認沒有在其他此類資料庫執行 Maintenance migrations | 使用者確認未套用；未聲稱所有外部資料庫均已完整盤點 |
| Preview / staging / shared DB | 使用者明確確認沒有在其他此類資料庫執行 Maintenance migrations | 使用者確認未套用；CI disposable services 不計入持續環境 |

使用者已針對 local、test、preview、staging、shared 及其他資料庫是否曾執行 Maintenance migrations 明確回答「無」。此確認更新先前「好像沒有／未確認」的回憶紀錄。CI PostgreSQL、GoTrue、PostgREST 是 workflow 建立的 disposable services，不屬於使用者持續管理的資料庫。這項確認只涵蓋使用者所知的其他環境；不能取代正式 production migration baseline 的完整重建，也不能證明未被提及的外部資料庫不存在。

## 6. 部署路徑決策矩陣

| 環境歷史結果 | 建議路徑 | 必要條件 |
|---|---|---|
| 所有目標環境均有證據確認兩份舊 migration 都未套用 | 可評估協調式 clean-bootstrap / squash，以 single-pass 作唯一新安裝入口 | 先列出所有環境；更新 migration directory、CI、SQL harness、scripts、docs；確認實際測試的是最終 timestamped migration |
| 任一環境已套用舊 migration 1 | 保留歷史，規劃 forward-upgrade | 確認該環境目前 grants、policies、owners、RLS 與資料狀態；不可重寫既有 migration |
| 任一環境已套用舊 migration 1 + 2 | 保留兩份歷史，評估後續增量 migration | 驗證實際 schema 是否等於預期 hardened state；不可重播 bootstrap |
| 任一環境歷史不明 | 暫停 migration 變更 | 先取得該環境 ledger、schema snapshot、部署紀錄或 DBA 確認 |

**目前決策：使用者確認其他已知環境沒有套用 Maintenance migrations；但正式 production migration ledger/schema baseline 仍存在獨立缺口。** 因此仍暫停 timestamped migration 改寫與正式部署，不選擇 squash 或 forward migration，直到 production baseline 完成可驗證的 reconciliation。

## 7. 執行前必須完成的檢查

- [x] 已取得使用者明確確認：其他已知 local、manual、preview、staging、shared databases 未執行 Maintenance migrations。
- [ ] 完成正式 production migration ledger/schema baseline reconciliation，並確認是否有未盤點的外部資料庫。
- [ ] 對每個環境記錄 migration 檔案是否套用、時間、證據來源；未知就明確標記未知。
- [ ] 對每個已存在 Maintenance objects 的環境，取得 schema / grants / policies / function owners / RLS / triggers 的唯讀 snapshot。
- [ ] 決定 clean-bootstrap 或 forward-upgrade 路徑，並說明為何適用於每一個環境。
- [ ] 確認最終 single-pass SQL 的來源檔與 timestamped migration 不會漂移。
- [ ] CI 改為測試最終 migration 檔本身，並保留 GoTrue-issued JWT + PostgREST、PostgreSQL RLS/RPC、Deno 與 Playwright checks。
- [ ] 測試 migration 失敗回滾、role ownership、ACL、RLS、RPC、audit、idempotency 與併發行為。
- [ ] 完成正式部署順序、監控、復原與 forward-fix 計畫。
- [ ] 取得使用者對任何正式環境變更的獨立明確核准。

## 8. 明確禁止事項（解除 gate 前）

- 不執行 `db push`、`migration repair`、`db reset` 或手動建立 migration history。
- 不執行任何 Maintenance SQL 到正式 Supabase。
- 不刪除、改名、重排、覆寫或 squash 兩份 timestamped Maintenance migrations。
- 不部署五支 Maintenance Edge Functions。
- 不變更 `MAINTENANCE_FEATURE_ENABLED`。
- 不合併 PR #34 或將其標記為 Ready。
- 不把 disposable CI 通過描述成 hosted production smoke test。

## 9. 本次核對紀錄

- GitHub `main`、PR #34 base/head migration directory：唯讀列檔。
- Maintenance initial / least-privilege upgrade SQL：唯讀檢視。
- Maintenance API v0.7 與既有 migration planning / reconciliation docs：唯讀檢視。
- Supabase project status、migration listing、table catalog、function catalog、Edge Function inventory：唯讀查詢。
- 沒有執行 SQL DDL/DML、migration repair、Edge Function deployment、feature flag 修改或 PR 合併。

**最終狀態：使用者已確認其他已知環境未執行 Maintenance migrations；single-pass draft 的管理 RPC owner 為內建 pg_database_owner。部署仍被正式 production migration baseline 缺口、最終 timestamped migration 尚未建立/驗證，以及 hosted runtime 檢查未完成所阻擋。**


## 10. 使用者環境確認與最新 CI 更新（2026-11-22）

- 使用者已明確回答「無」：沒有在其他 local/test/preview/staging/shared 或其他持續管理資料庫執行過 Maintenance migrations。此確認取代早期文件中的「好像沒有／未確認」。
- PR #34 single-pass 隔離 PostgreSQL harness 已新增 assertion：`pg_database_owner` 必須能執行正式既有 `public.is_admin()` helper。該 assertion 於 CI run #45042828862 通過（4/4 jobs）。
- 正式 Supabase 的唯讀檢查顯示 `public.is_admin()` 由 `postgres` 擁有，為 `SECURITY DEFINER`、固定空 `search_path`，並使用 schema-qualified `public.profiles` 與 `auth.uid()`；目前 ACL 尚未授予 `pg_database_owner`。single-pass draft 中的 `GRANT EXECUTE ON FUNCTION public.is_admin() TO pg_database_owner` 是必要部署語句，但尚未在正式資料庫執行。
- 此 helper ACL 核對不等於 migration baseline 已修復。正式 production 的 migration listing 仍為空，`supabase_migrations` schema/table 未找到；需依正式 Supabase schema snapshot 完成獨立 baseline reconciliation。
- 本次仍未建立 timestamped migration、未修改既有 migration history、未執行 production SQL、未部署 Edge Functions、未變更 feature flag、未合併 PR #34。


## 11. 最終檢查補記（CI run #45043081949）

- 最新提交 `66bb27750beefcab3b578b75459f2a389570312d` 的 CI run #45043081949 已完成，4/4 jobs success：Deno type check/tests、legacy GoTrue/PostgREST、isolated PostgreSQL RPC/RLS、single-pass GoTrue/PostgREST。
- 隔離 SQL 測試包含 `pg_database_owner` 必須能執行 `public.is_admin()` 的 assertion；該 CI run 成功，代表此權限契約在 disposable test database 中通過。
- Single-pass SQL 仍位於 `supabase/sql/maintenance-private-schema-rpc-draft-v0.1.sql`，檔首明確標示 DEVELOPMENT DRAFT ONLY，並非 timestamped migration。此分支沒有建立 replacement timestamped migration。
- 原兩份 timestamped Maintenance migrations 仍保留；未 squash、刪除、改名、重排或改寫。這是刻意的安全決定：正式 production migration ledger 缺失與全域 schema baseline 未 reconciliation，不能僅依使用者對其他環境的確認就進行正式 migration history 操作。
- 下一個阻擋項目是 production schema baseline / migration history reconciliation；完成前不產生可部署 migration、不執行 `db push` / migration repair、不部署 Edge Functions、不啟用 feature flag。
