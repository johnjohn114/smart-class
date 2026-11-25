# Maintenance SQL / API / Edge Functions 相容性合併稽核 v0.2

> 日期：2026-11-08  
> 分支：`feature/maintenance-system`  
> 狀態：部分比對完成；原始 SQL 本文未能從目前可用檔案/GitHub 取回。本文只記錄可追溯的既有審查摘要、目前 API/Edge 契約及其差異，不代表已完成逐欄位 SQL 驗證。  
> 安全界線：未執行 Supabase DDL/DML、Migration、repair、deploy 或正式資料庫變更；未新增付費資源。

## 1. 本次可用證據

### 1.1 可讀取來源
- 目前上傳的 `啟動第一步檢查.txt`：只有審查摘要，沒有 SQL 本文。
- GitHub `feature/maintenance-system`：
  - 五支 Edge Function 與 shared validator
  - `supabase/tests/functions/maintenance-validation.test.ts`
  - `docs/maintenance-api-spec-v0.4.md`（文件標題為 API v0.5）
  - `docs/maintenance-rpc-sql-contract-v0.1.md`
  - `docs/maintenance-permission-rpc-security-review-v0.2.md`
- 過往 SQL 審查紀錄摘要：原 SQL 曾為 357 行；四表名稱、三個 trigger function、五個 trigger，以及部分時間欄位可追溯，但完整 DDL 文字未保存於目前可讀來源。

### 1.2 已能追溯的舊 SQL 摘要
四張表：
- `maintenance_state`
- `maintenance_events`
- `maintenance_scopes`
- `maintenance_audit_logs`

欄位線索：
- 事件時間欄位曾包含 `starts_at`、`expected_end_at`、`actual_started_at`、`actual_ended_at`。
- 完整欄位型別、NULL/default、PK/FK、CHECK、UNIQUE、index、RLS policy expression 目前無法由摘要確認。

函式/觸發器線索：
- `maintenance_set_updated_at()`
- `maintenance_reject_event_delete()`
- `maintenance_reject_audit_mutation()`
- `maintenance_events_set_updated_at`
- `maintenance_state_set_updated_at`
- `maintenance_events_no_delete`
- `maintenance_audit_no_update_delete`
- `maintenance_audit_no_truncate`

舊 SQL 權限設計摘要：
- 四張表啟用 RLS，未建立瀏覽器角色 policies。
- 曾明確撤銷 `anon`、`authenticated` 對四表的直接存取，目標為由 `service_role` Edge Function 存取。
- trigger functions 曾撤銷 `anon`、`authenticated` EXECUTE。
- 此摘要不能替代原始 ACL/GRANT/REVOKE SQL 的逐項核對。

## 2. 已確認的契約差異與處理決議

| 項目 | 舊 SQL 線索 | 現行 API / Edge | 結論 |
|---|---|---|---|
| 預期結束時間 | `expected_end_at` | API/Edge 使用 `ends_at` | 必須在 RPC 明確做欄位映射；不得假設資料表存在 `ends_at` |
| 實際開始/結束時間 | `actual_started_at`、`actual_ended_at` | API 不接受這兩欄作為 client input | 保持 DB/server 管理欄位；不得讓前端直接指定 |
| 維護範圍 | `maintenance_scopes` | API 傳 `scope_codes` | RPC 應負責 code → scope row/link 的解析；需由原 SQL 確認 scope 欄位與關聯鍵 |
| 稽核 | `maintenance_audit_logs` | API 要求 reason、actor、before/after snapshot、idempotency | 必須確認 audit 欄位及交易寫入契約；actor 僅由 `auth.uid()` 取得 |
| 啟用模式 | 舊 SQL 摘要未能確認欄位 | 過往產品決策要求逐筆選擇 automatic/manual，建議預設 manual | 尚未落到可驗證的 SQL/API 欄位；需在原 SQL 核對後補上 `activation_mode` 或明確記錄暫不支援，不能自行假設已存在 |
| RLS / table grants | 舊 SQL 摘要為瀏覽器角色無直接權限、service_role 存取 | 最新架構 v0.4 要求 user JWT + SECURITY INVOKER RPC + private tables + 最小 authenticated grants/RLS | **重大架構衝突**。舊 service_role-only table grant 模型不能直接支援目前的 invoker/user-JWT RPC；必須以 v0.4 安全決議為準重新設計 grants/RLS，完成隔離測試前不得產生正式 migration |
| audit 不可變更 | audit UPDATE/DELETE/TRUNCATE 保護線索 | 權限審查 v0.2 另要求 SECURITY INVOKER、最小 INSERT/SELECT、RLS admin gate | 必須確認 trigger、ACL、RLS 與 invoker 寫入能力可同時成立；不可宣稱對 DB owner/superuser 絕對不可竄改 |

## 3. 必須維持的 API / Edge 契約

### 3.1 目前 Edge Functions 的外部輸入
- status：可選 `scope`
- admin-list：`status`、`scope`、`is_global`、`from`、`to`、`limit`、`cursor`
- create：`title`、`message`、`internal_note`、`is_global`、`scope_codes`、`starts_at`、`ends_at`、`status`、`reason`、`idempotency_key`
- update：`event_id`、`expected_version`、`reason`、`idempotency_key`，以及白名單事件欄位
- action：`event_id`、`expected_version`、`action`、`reason`、`idempotency_key`

### 3.2 RPC 呼叫
五個 Edge Function 都以 `{ "p_request": validatedPayload }` 呼叫單一 public RPC。SQL 端需提供對應 `jsonb` 參數，並維持 SECURITY INVOKER、空 search_path、完整限定名稱及明確 EXECUTE ACL。

### 3.3 安全架構
- 管理 Edge Function 傳遞原始使用者 JWT；不得使用 service_role 冒充使用者。
- 每個管理 RPC 再檢查 `auth.uid() IS NOT NULL AND public.is_admin()`。
- actor 取自 `auth.uid()`，不得信任 client actor/user id。
- status RPC 維持 SECURITY INVOKER；若 anon 最小 USAGE/SELECT + RLS 無法安全成立，停止實作，不得自行改 SECURITY DEFINER。
- private schema 不加入 Data API Exposed schemas。
- 不得為配合舊 SQL 而退回 service_role-only RPC 寫入模型。

## 4. 必須在 SQL 本文取回後完成的逐欄位核對

- [ ] 四張表每一欄的名稱、型別、NULL/default、生成方式。
- [ ] PK、FK、ON DELETE/UPDATE、CHECK、UNIQUE、索引及排程重疊約束。
- [ ] `maintenance_scopes` 是 lookup table 還是 event-scope junction table；核對實際鍵與 enabled 欄位。
- [ ] event status、version、activation_mode 是否有 CHECK/enum 與預設值。
- [ ] idempotency table/欄位、actor + key 唯一性、request hash、response replay 欄位。
- [ ] audit snapshot、reason、actor、created_at 欄位及寫入權限。
- [ ] trigger function 的 schema、owner、SECURITY、search_path、EXECUTE ACL。
- [ ] 四表 RLS policy 的完整 USING/WITH CHECK expression。
- [ ] grants/revokes 與 v0.4 user-JWT SECURITY INVOKER 架構一致。
- [ ] Edge parser 的長度上限與 DB CHECK 一致；目前 Edge 暫定 title 200、message/internal_note 4000、reason 500，尚未核准為正式上限。
- [ ] API `ends_at` 與 DB `expected_end_at` 映射完整且一致。
- [ ] action transition、排程衝突、version、idempotency、audit 全部同一 transaction。

## 5. 靜態驗證狀態

已能確認：
- 五個 Edge entrypoints 對應五個預期 RPC。
- Edge 呼叫 body 使用 `p_request`。
- shared parser 拒絕未知欄位。
- create/update/action 使用 UUID idempotency key。
- 既有測試檔包含 6 個 Deno.test cases（測試檔已讀取，未在本環境執行）。
- 本環境沒有 Deno executable，因此本次無法執行 Deno tests。
- 沒有原始 SQL 本文，故無法執行 SQL parser、SQL-to-API 欄位對照或真正 SQL lint。
- 不進行完整 PostgreSQL restore test，遵照使用者先前決定。

## 6. 目前結論 / Gate

**可完成：** API/Edge 呼叫契約盤點、已知欄位映射決議、權限架構衝突識別、待核對清單。

**不可宣稱完成：** 原始四表 SQL 逐欄位相容性、SQL 靜態 parse、RLS/grants 真實驗證、五個 RPC SQL 草案已可安全定稿。

**阻塞項目只有一個必要來源：** 請提供原始 `v26.11.7_maintenance_migration_review.sql`（或先前修正版 SQL 檔）。取得後即可依第 4 節逐項比對；不需要再重複確認已決議的產品規則。

## 7. 本次未執行事項
- 未連線或修改正式 Supabase。
- 未執行 DDL/DML、Migration、migration repair、db push、db reset。
- 未部署 Edge Functions。
- 未建立付費服務或額外專案。


## 8. 2026-11-22 現行分支與隔離驗證補記

本節更新目前 repository 的狀態，不回寫或抹除 11/08 原始稽核當時可取得的證據。原始上傳的 `啟動第一步檢查.txt` 是舊四表設計的審查摘要，不是 SQL 原始碼；其四表與 service_role 權限描述不可直接當作目前六表 Maintenance 架構。

### 8.1 現行 repository 架構

目前工作分支：`feature/maintenance-single-pass-migration-20261122`，相對 `main` 為 ahead 44、behind 0。現行 API 契約為 `docs/maintenance-api-spec-v0.7.md`。

repository 內可讀取到兩個正式命名的 migration 檔案：
- `supabase/migrations/20261117121103_maintenance_system_initial.sql`
- `supabase/migrations/20261121140000_maintenance_rpc_least_privilege_upgrade.sql`

兩個 migration 建立／升級六張 private tables：`maintenance_scopes`、`maintenance_events`、`maintenance_event_private_notes`、`maintenance_event_scopes`、`maintenance_audit_logs`、`maintenance_idempotency`，以及五個 public RPC。另有 `supabase/sql/maintenance-private-schema-rpc-draft-v0.1.sql` 作為 single-pass development draft；它不是已核准或已套用的正式 migration。

因此，11/08 摘要中的四張表（`maintenance_state`、`maintenance_events`、`maintenance_scopes`、`maintenance_audit_logs`）只代表舊設計線索，不是 v0.7 現行 schema。完整欄位與限制應以目前 migration 和 API v0.7 為準。

### 8.2 已核對的欄位長度

目前 API v0.7、Edge parser 與 SQL 草案／驗證使用一致限制：
- `title`: 200 字元
- `message`: 4,000 字元
- `internal_note`: 4,000 字元
- `reason`: 500 字元

原第 4 節所列「Edge 暫定、尚未核准」已由這次程式碼與 SQL 對照更新；不應再把這四個限制標示為待定。這項核對只證明 repository 內來源一致，不代表正式資料庫已套用。

### 8.3 隔離 CI 證據

最新 GitHub Actions run [#270](https://github.com/johnjohn114/smart-class/actions/runs/44997928704) 對應分支 commit `182eef7377a313c3f98431410daee2608aef1f73`，四個 jobs 全數成功：
- Deno type check（27 項 validation tests）/ feature gate / Playwright（首頁、管理頁、維護生命週期 UI）/ SQL static guardrails。
- 隔離 PostgreSQL RPC、RLS 與回歸測試。
- GoTrue-issued JWT + PostgREST single-pass draft 整合測試。
- GoTrue-issued JWT + PostgREST legacy migration 路徑整合測試。

此 CI run 驗證的是隔離測試資料庫與測試服務；Playwright 管理操作使用 in-memory mock。它不是正式 Supabase smoke test，不證明 production migration history，也不代表已部署。

### 8.4 仍然有效的限制

- 尚未對正式 Supabase 執行 DDL/DML、migration 或 migration repair。
- 尚未部署五支 Edge Functions，未啟用正式功能旗標。
- single-pass draft 是否取代 migration pair，仍須先盤點所有可能使用環境的 migration history；不得直接改寫已套用的 migration 歷史。
- 正式 schema baseline、Data API Exposed schemas、CORS/env 與部署後 smoke test 仍待獨立審核。
- 本補記不執行安全強化或正式環境權限變更；相關安全工作依原排程另行處理。

