# Maintenance SQL 安全審查紀錄 v0.1

日期：2026-11-22  
分支：feature/maintenance-single-pass-migration-20261122  
對象：supabase/sql/maintenance-private-schema-rpc-draft-v0.1.sql  
狀態：**開發分支審查完成；正式部署仍未核准**

## 1. 審查範圍

- 六張 private tables：maintenance_scopes、maintenance_events、maintenance_event_private_notes、maintenance_event_scopes、maintenance_audit_logs、maintenance_idempotency。
- 五個 RPC：公開 status、admin list、event create、event update、event action。
- RLS / FORCE RLS、table grants、function EXECUTE ACL、owner、固定空 search_path。
- actor identity、管理員檢查、audit、idempotency、version、排程衝突與 transaction lock。
- API v0.7、RPC SQL contract、Edge Function shared validator、隔離測試及 CI workflow 的一致性。

## 2. 現行 SQL 的實際安全模型

| 項目 | 草案實際內容 |
|---|---|
| Public status RPC | SECURITY INVOKER；EXECUTE 給 anon、authenticated |
| 四個管理 RPC | SECURITY DEFINER；owner 為內建 pg_database_owner；EXECUTE 僅給 authenticated |
| 身分 helper | private.maintenance_uid() 以 SECURITY INVOKER 讀取 PostgREST JWT claims 的 subject |
| 管理員判斷 | 依賴既有 public.is_admin()；RPC 內再次檢查，不採信 client actor/role 欄位 |
| Tables | 六張 private tables 全部 ENABLE + FORCE RLS；table owner 與 RPC owner 分離 |
| 寫入權限 | 管理寫入 table grants 授予 pg_database_owner；authenticated 沒有直接 table write grants |
| Audit | 管理 RPC 同一交易寫入；trigger 阻止一般路徑 UPDATE/DELETE/TRUNCATE |
| Transaction | create/update/action 使用 idempotency 與 advisory transaction lock，維持排程衝突檢查的序列化 |

注意：草案沒有建立自訂 maintenance_rpc_executor。舊文件中出現的自訂 role 是先前設計，不是現行 SQL。

## 3. 正向檢查結果

- SQL 使用單一 transaction，並在開始時檢查資料庫 owner 能否 SET ROLE 至 pg_database_owner、能否在 public schema CREATE，以及 private schema/RPC 名稱是否已存在。
- private tables 全部啟用並 FORCE RLS；RPC owner 不是資料表 owner，且測試檢查 pg_database_owner 不具 BYPASSRLS。
- admin RPC 使用 SECURITY DEFINER、固定空 search_path、完整限定物件名稱，並在函式內檢查 JWT subject 與 admin helper。
- client 無法傳入 actor_id/user_id/role 取代資料庫端 actor identity；audit actor 預設由 JWT subject helper 取得。
- public status 只讀取有效維護狀態，並透過公開欄位 grants 與 RLS 限制匿名資料存取。
- internal_note 獨立存放於 admin-only private table，不放在 public event row。
- create/update/action 將事件、scope links、audit、idempotency 放在同一 RPC transaction；使用 version 與 advisory transaction lock 處理重送及競爭。
- workflow 包含 disposable PostgreSQL 17、GoTrue-issued JWT、PostgREST、Deno 與 Playwright 檢查；PR #34 描述的 CI run #44927798716 為 4/4 jobs passed。

## 4. 發現與阻擋事項

### R1 — 規格文件與 SQL owner 模型不一致

API v0.7、RPC contract、single-pass plan 的部分段落仍寫自訂 maintenance_rpc_executor，RPC contract 也有「五個 RPC 全部 SECURITY INVOKER」及 actor 使用 auth.uid() 的舊描述。這與現行 SQL 不一致。已在本分支校正主要規格文件並於 plan 加入更正紀錄；舊 migration 的歷史描述保留為歷史，不作為新草案部署指示。

### R2 — production public.is_admin() 的既有 ACL 必須由 migration 補齊

已對正式 Supabase 執行唯讀 catalog 核對（inspection role：postgres；沒有執行 DDL/DML）：

- 實際 signature：public.is_admin() RETURNS boolean；owner 為 postgres；LANGUAGE sql、STABLE、SECURITY DEFINER；固定 search_path 為空字串。
- 函式內容使用完整限定名稱 public.profiles 與 auth.uid()，條件為 profiles.id = auth.uid() 且 role = 'admin'。因此空 search_path 不會造成這兩個物件名稱解析問題；函式以 postgres 權限讀取 profiles 並只回傳 boolean。
- 現有 EXECUTE ACL 包含 postgres、authenticated、service_role；正式資料庫目前尚未授予 pg_database_owner。唯讀 has_function_privilege 結果：pg_database_owner = false、authenticated = true、service_role = true；auth.uid() 對 pg_database_owner 可執行。
- single-pass SQL 草案已明確包含 GRANT EXECUTE ON FUNCTION public.is_admin() TO pg_database_owner，且 migration actor preflight 要求目前角色可呼叫該 helper。套用最終 migration 後，管理 RPC 的 SECURITY DEFINER owner 才能成功呼叫 helper。此 grant 是必要部署條件，不能省略。
- 已在隔離 PostgreSQL 測試增加明確 assertion，確保 pg_database_owner 對 public.is_admin() 有 EXECUTE；CI 將驗證這項權限不會回歸。

結論：既有 helper 的 owner、SECURITY DEFINER、固定空 search_path 與 schema-qualified 依賴，與草案的呼叫方式相容；但正式資料庫目前 ACL 尚未補齊。只有在核准的最終 migration 中保留並成功執行上述 GRANT，才可視為通過此項相容性檢查。

### R3 — Audit append-only 的保證範圍有限

row UPDATE/DELETE 與 TRUNCATE trigger 可阻止一般資料庫操作路徑，但 database owner、superuser 或其他具足夠權限者仍可能停用 trigger、改變 schema 或直接操作資料。文件不得宣稱 audit 對高權限操作者絕對不可竄改。

### R4 — private schema 的 Data API 設定尚未正式確認

必須在 Supabase Dashboard 確認 private 不在 Data API Exposed schemas。這是部署前設定檢查，不能只靠 SQL 註解推定已完成。

### R5 — Hosted runtime 尚未驗證

CI 的 Deno.serve handler harness、PostgreSQL、GoTrue、PostgREST 與 Playwright 都是隔離測試；它們不等於正式 Supabase Edge Runtime / gateway smoke test。正式 runtime 測試仍須在另行授權的非正式環境執行。

### R6 — Migration history / production baseline 獨立阻擋

使用者已明確確認沒有在其他 local/test/preview/staging/shared database 執行 Maintenance migrations。已知 Supabase 帳戶只有一個 production project，且 production catalog 未見 Maintenance objects；但該 production project 的 migration ledger/baseline 有全域缺口，不能僅憑 catalog 缺少 Maintenance objects 就重寫 timestamped migration history。兩份既有 Maintenance timestamped migrations 與 PR #34 stacked branch 的關係仍需協調；本次不改寫、不刪除、不重排。

## 5. 審查結論

**開發分支 SQL 草案：主要權限與資料流程設計可進入後續驗證，但本次不核准正式部署。**

正式部署前至少必須完成：
1. 最終 migration 必須保留並驗證 `GRANT EXECUTE ON FUNCTION public.is_admin() TO pg_database_owner`；正式資料庫目前尚未授予此權限。
2. Data API Exposed schemas、CORS、Edge Function environment variables 的設定核對。
3. production schema baseline / migration history reconciliation。
4. 在另行核准的非正式 hosted Supabase 環境完成 Edge Runtime / gateway smoke test。
5. 更新並審查最終 timestamped migration，確認 CI 測試的就是最終部署檔，而非只測 development draft。

## 6. 本次未執行事項

- 未連線執行任何 production SQL；未執行 DDL/DML、migration、migration repair、db push 或 db reset。
- 未部署 Edge Functions，未變更 feature flag、production data 或 Supabase schema。
- 未合併 PR #31 / PR #34，未 retarget PR。
- 未建立付費服務、Supabase branch 或額外專案。

本文件記錄的是 repository-level review 與 CI 證據，不是正式環境安全認證。