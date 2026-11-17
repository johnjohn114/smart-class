# 維護系統安全與相容性審核 v0.1

> 審核日期：2026-11-08
> 專案：`fsoowongtavlsrwvzbze`
> 範圍：只讀核對現有 Supabase 結構、Edge Functions、管理員驗證及 Supabase 當前文件。
> 限制：沒有執行 DDL、沒有修改正式資料庫、沒有部署或修改任何 Edge Function。

## 1. 審核摘要

| 項目 | 審核結果 | 說明 |
|---|---|---|
| PostgreSQL | 已確認 | 專案回報 PostgreSQL 17.6 |
| 現有資料表 | 已確認 | 列表工具回傳 44 張 public tables |
| private schema | 尚不存在 | schema 清單未包含 private |
| 維護專用資料表 | 尚不存在 | 沒有 maintenance 相關 table/view |
| 維護 Edge Functions | 尚不存在 | 現有 6 支 active functions，沒有維護 API |
| 管理員角色欄位 | 已存在 | public.profiles.role，允許 admin / visitor |
| is_admin() | 可沿用 | SECURITY DEFINER、空 search_path、只授權 authenticated/service_role/postgres |
| is_admin_user() | 不建議沿用 | anon 也有 EXECUTE，search_path 設為 public |
| Migration history | 工具回傳空清單 | 執行前須再比對 repository migration files 與資料庫 migration history |
| Data API 新物件預設曝光 | 必須明確處理 | 2026-10-30 起，既有專案也已執行新物件預設不自動曝光的變更 |

## 2. 管理員驗證審核

### 現有資料庫函式

`public.is_admin()`：
- 查核 `public.profiles.id = auth.uid()` 且 `role = 'admin'`。
- `SECURITY DEFINER`。
- `SET search_path TO ''`，函式內使用完整 schema 名稱。
- EXECUTE 授權包含 authenticated、service_role、postgres；沒有 anon。
- 建議維護管理 API 的 Edge Function 驗證 JWT 後，以該使用者的 JWT 呼叫此函式確認管理員身分。

`public.is_admin_user()`：
- 同樣查詢 profiles.role。
- `SECURITY DEFINER`，search_path 設為 public。
- anon、authenticated、service_role、postgres 都有 EXECUTE。
- 不作為新維護系統的管理員授權入口；也不應以「函式回傳 false」取代正確的 EXECUTE 權限限制。

### 現有 Edge Function

`manage-visitors`：
- `verify_jwt = true`。
- 程式再呼叫 `auth.getUser()` 驗證 token。
- 以 `ADMIN_EMAIL` 環境變數比對使用者 email。
- 此做法與資料庫 `profiles.role` 不是同一授權來源。

### v0.3 決策

- 新管理 API 設 `verify_jwt = true`。
- Edge Function 使用呼叫者 JWT 呼叫 `auth.getUser()` 取得真實使用者。
- 再使用同一使用者 JWT 呼叫 `public.is_admin()`；失敗或非 admin 一律 403。
- 不信任 body 的 `role`、`isAdmin`、`actor_id` 或 email。
- audit actor_id 一律取自已驗證 user.id。
- 不沿用 `ADMIN_EMAIL` 作為維護系統角色來源。
- `maintenance-status` 是公開讀取 API，允許匿名；若有有效使用者 token，才可額外判斷是否 admin bypass。無效 token 不可取得 bypass 權限。

## 3. Schema 與資料存取審核

目前資料庫 schema 清單包含 auth、extensions、graphql、graphql_public、public、realtime、storage、vault，沒有 private。

原 v0.2 將維護資料表放在 private schema 的方向正確，但原 API 文件未明確說明：private schema 不經 Data API 暴露時，Edge Function 不可直接用一般 `supabase-js .from()`／`.rpc()` 的預設 public schema 呼叫它。

### v0.3 建議存取架構

- 維護資料表與內部交易函式放在新建的 `private` schema。
- 不把 `private` 加入 Supabase Data API Exposed schemas。
- Edge Functions 透過伺服器端 `SUPABASE_DB_URL` 與 Postgres driver 連線，執行固定、參數化的 SQL／資料庫函式。
- 不讓前端連線資料庫，不接受用戶提供 SQL，不在 Edge Function 組合動態 SQL。
- Edge Function 使用 Supabase Auth client 驗證使用者；資料庫連線只在伺服器端使用。
- 連線採 serverless 適用的 transaction pooler；Postgres.js 設定 `max: 1`、`prepare: false`、SSL required。若使用其他 driver，採相同連線限制。
- 所有寫入操作在單一資料庫交易中完成；用 `pg_advisory_xact_lock` 取得交易層級鎖，不能使用依賴 session 狀態的 session-level lock。
- public status 讀取只呼叫固定的唯讀查詢／函式，回傳白名單欄位。

這樣不需要把 private schema 暴露到 Data API，也不必新增 public SECURITY DEFINER RPC 入口。Supabase 官方文件確認 Edge Functions 可使用 `SUPABASE_DB_URL` 及 Postgres client；serverless／edge 應採 transaction pooler，並限制連線池與關閉 prepared statements。

注意：`SUPABASE_DB_URL` 是高權限資料庫憑證，只能存在 Edge Function 伺服器端，絕不可放進 GitHub Pages 前端程式或回應內容。每個 API 只能執行固定操作；不得提供通用 SQL 執行介面。

## 4. RLS、GRANT 與 Data API

- private schema 不暴露 Data API，但新表仍建議啟用 RLS 作縱深防禦。
- 不授予 anon 或 authenticated 對維護資料表的直接 SELECT／INSERT／UPDATE／DELETE 權限。
- 不將 service_role key 或 DB connection string 傳給瀏覽器。
- 由 Edge Function 的伺服器端 DB 連線存取 private schema。
- private schema 的 USAGE 與物件權限只授予必要的資料庫角色；避免給 PUBLIC。
- 若未來改用 public RPC，必須先明確確認 function exposure，並撤銷 PUBLIC、anon、authenticated 的 EXECUTE，只授予需要的 server-side role；不得依賴預設權限。

Supabase changelog 指出：2026-10-30 起，既有專案的新資料表與函式也不再自動曝光到 Data API。Migration 必須明確規劃 API exposure 與 GRANT，不可假設新 public function/table 自動可呼叫。

## 5. 稽核記錄與外鍵修正

原 v0.2 的 audit log FK 描述需具體化：
- `event_id`：`ON DELETE SET NULL`，保留歷史紀錄。
- `actor_id`：`ON DELETE SET NULL`，避免刪除 Auth 使用者時無法保留稽核紀錄。
- 事件採取消／完成，不提供一般硬刪除；若因維護作業需刪除，仍保留 audit log。
- `created_by`、`updated_by` 亦建議 `ON DELETE SET NULL`。
- 稽核紀錄只允許追加；不提供一般 UPDATE／DELETE。
- audit 快照只存業務欄位，不存 JWT、密碼、service key、DB URL 或不必要個資。

## 6. 排程鎖與交易核對

- 使用 `pg_advisory_xact_lock`，確保 lock 只在同一交易期間有效。
- 建立／修改／排程啟用都使用相同鎖鍵及相同衝突檢查函式。
- 在取得鎖後才查衝突，再寫事件、scope 關聯、audit、idempotency。
- 任一步驟失敗全部 rollback。
- 區間採半開區間 `[starts_at, ends_at)`。
- 全站事件與任何局部事件時間重疊皆衝突；局部事件僅在 scope 有交集且時間重疊時衝突。
- draft 不佔用排程；scheduled 才佔用其時間區間。這是建議定案，需在 migration 前寫入正式規格。
- idempotency 唯一鍵需在交易中先鎖定／建立，避免兩個相同 key 的併發請求重複執行。

## 7. 管理員全站維護 bypass

使用者已確認全站維護期間管理員仍可登入管理後台。前端與 Edge Function 必須分開處理：

- 不把 `admin.html`、登入頁、Auth callback 或必要的 Auth API 一起導向一般維護頁。
- 管理員登入後，前端才可依有效 session 與管理員檢查略過維護遮罩。
- bypass 只代表不顯示維護封鎖畫面，不會跳過任何管理 API 的 JWT、admin role、輸入驗證或 audit。
- 如果 Supabase Auth 本身故障，無法保證管理員仍能登入；需保留獨立復原程序，不建立公開後門。
- 一般使用者不受影響的局部 scope 原則上仍可使用，但共用服務依賴要逐頁核對。

## 8. 目前 Supabase Advisor 基線（未因本功能修改）

本次讀取到的 Security Advisor：
- ERROR 1：`public.activity_member_stats` 為 security definer view。
- WARN 34：SECURITY DEFINER functions 可由 anon 執行。
- WARN 34：SECURITY DEFINER functions 可由 authenticated 執行。
- INFO 2：`public.member_no_counter`、`public.visitor_profiles` 已啟用 RLS 但沒有 policy。
- WARN 1：Auth leaked password protection disabled。

這些是現有專案基線，不是本次維護系統設計造成的問題。不得在維護系統 migration 中順手修改不相關物件；應由獨立 security-hardening 工作處理。特別是 Advisor 的函式警告不代表每一個函式都已可被利用，仍需逐一核對函式內容、實際 ACL 與內部授權檢查。

## 9. 尚待實作前確認

1. GitHub repository 的 Migration 檔案與 Supabase migration history 為何不同；本次 list_migrations 工具回傳空清單，不能單憑此結果推論所有 schema 都未經 migration。
2. Edge Function 使用的 `SUPABASE_DB_URL` 連線模式與 pooler 連線設定；不可輸出或記錄密碼。
3. 七個 scope 的完整頁面、共用 API 與背景服務映射。
4. 已開始事件可修改欄位、自然到期處理及稽核保留期限。
5. 各 scope 維護時是封鎖、唯讀或只顯示提示。

## 10. 參考文件

- Supabase Data API 安全與 grants：<https://supabase.com/docs/guides/api/securing-your-api>
- Supabase Edge Functions 連線 Postgres：<https://supabase.com/docs/guides/functions/connect-to-postgres>
- Supabase serverless／transaction pooler 連線：<https://supabase.com/docs/guides/database/connecting-to-postgres>
- Supabase Database Functions 權限：<https://supabase.com/docs/guides/database/functions>
- Supabase Data API 新物件預設不自動曝光變更：<https://supabase.com/changelog?types=breaking-change>

## 11. 結論

原 v0.2 的資料表分組、七個 scope、全站獨立控制及管理員 bypass 方向可保留；必須修正的是管理員驗證來源、private schema 的實際存取方式、audit 外鍵策略、交易層級鎖與 Data API exposure 假設。

本輪只讀審核並產生設計文件，未修改正式資料庫、未部署 Edge Functions、未建立付費資源。
