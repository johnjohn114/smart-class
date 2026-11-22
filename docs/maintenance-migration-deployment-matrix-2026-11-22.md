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
- 未取得所有 local/manual/preview/staging/shared database 的執行歷史證據，因此不可 squash、刪除、改名、取代或重排 timestamped migration。

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
| 舊 migration 2：權限升級 | 建立 `maintenance_rpc_executor`、啟用 FORCE RLS、調整 mutation policies、撤銷 authenticated 寫入 grants、設定管理 RPC owner/ACL | 轉為專用 NOLOGIN/NOBYPASSRLS executor role 的最小權限設計 | 只適用於已按順序套用舊 migration 1 的環境；不得假設可在乾淨環境單獨執行 |
| Single-pass draft | 從一開始建立最終 executor/RLS/grants/RPC ownership 模型 | 目標是避免舊 migration 1 與 2 之間的中間權限窗口 | 候選設計已在隔離 CI 路徑測試；仍不是已核准的 timestamped migration |

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
| Local / manually managed PostgreSQL | 尚無可驗證的完整環境清單與 migration ledger | 未確認 |
| Preview / staging / shared DB | 尚無可驗證的完整環境清單與 migration ledger | 未確認 |

先前使用者回憶可能沒有手動套用 Maintenance SQL，但此回憶不是資料庫執行證據。必須把未知環境維持為「未確認」，不能轉成「確定未套用」。

## 6. 部署路徑決策矩陣

| 環境歷史結果 | 建議路徑 | 必要條件 |
|---|---|---|
| 所有目標環境均有證據確認兩份舊 migration 都未套用 | 可評估協調式 clean-bootstrap / squash，以 single-pass 作唯一新安裝入口 | 先列出所有環境；更新 migration directory、CI、SQL harness、scripts、docs；確認實際測試的是最終 timestamped migration |
| 任一環境已套用舊 migration 1 | 保留歷史，規劃 forward-upgrade | 確認該環境目前 grants、policies、owners、RLS 與資料狀態；不可重寫既有 migration |
| 任一環境已套用舊 migration 1 + 2 | 保留兩份歷史，評估後續增量 migration | 驗證實際 schema 是否等於預期 hardened state；不可重播 bootstrap |
| 任一環境歷史不明 | 暫停 migration 變更 | 先取得該環境 ledger、schema snapshot、部署紀錄或 DBA 確認 |

**目前適用列：任一環境歷史不明。** 因此維持暫停，不選擇 squash 或 forward migration。

## 7. 執行前必須完成的檢查

- [ ] 列出所有可能持有此專案資料的 local、manual、preview、staging、shared、production databases。
- [ ] 每個環境記錄 Migration 檔案是否套用、時間、證據來源；未知就明確標記未知。
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

**最終狀態：Migration 對照表已建立；部署仍被環境歷史未確認與正式 baseline 缺口阻擋。**
