# 真實 Supabase 唯讀相容性審查 v0.2

> 日期：2026-11-16  
> 專案：`fsoowongtavlsrwvzbze`  
> 程式分支檢查基準：`9334b37521da41bbc7d65b0baf76731786c151c8`  
> 狀態：唯讀檢查完成；正式 Auth/RPC 驗收未完成。本文沒有執行 DDL、DML、Migration、設定修改或部署。

## 1. 正式 Supabase 目前狀態

唯讀檢查結果：

- Project 狀態：`ACTIVE_HEALTHY`。
- PostgreSQL：17.11。
- `auth.users` 目前共 5 個帳號；`public.profiles` 角色統計為 1 個 admin、4 個 visitor。未讀取或記錄任何帳號識別資料。
- `private` schema 不存在。
- 五個 maintenance RPC 數量為 0。
- 六張維護資料表均未建立。
- 已部署 Edge Functions 清單中沒有五支 maintenance functions。
- `public.is_admin()` 存在，owner 為 `postgres`，屬 `SECURITY DEFINER`，固定 `search_path = ''`；ACL 有 authenticated / service_role EXECUTE，anon 無 EXECUTE。
- `public.is_admin()` 的定義以 `auth.uid()` 查詢 `public.profiles`，確認該使用者的 `role='admin'`。

因此目前正式專案沒有可供維護功能執行真實 RPC 測試的資料庫物件；不能把 CI PostgREST 測試稱為正式 Supabase 驗收。

## 2. Edge Function 原始碼相容性審查

以功能分支 commit `9334b37521da41bbc7d65b0baf76731786c151c8` 檢查：

- `supabase/config.toml` 將 `maintenance-status` 設為 `verify_jwt = false`；其餘四支管理 functions 設為 `true`。
- status function 對可選 bearer token 呼叫 `/auth/v1/user` 驗證；無效 optional token 不會取得管理員 bypass。
- 管理 functions 要求 bearer token，並以 `/auth/v1/user` 驗證。
- RPC 呼叫使用 publishable key（若未設定則相容使用 anon key）作為 `apikey`，並轉送使用者 bearer token 作為 `Authorization`。
- RPC body 為 `{ "p_request": ... }`，與 SQL 草案的五個 `(p_request jsonb)` signatures 一致。
- 原始碼未使用 service_role key。
- CORS 預設允許目前 GitHub Pages 網站 origin，並可由 `MAINTENANCE_ALLOWED_ORIGINS` 設定覆寫。

限制：這些是 repo 原始碼及 config 的靜態檢查結果；五支 functions 尚未部署，故不能視為部署後環境變數、Gateway JWT 驗證或 Edge Runtime 已驗收。

## 3. SQL 草案相容性與待修正事項

SQL 草案採用六張 private tables、五個 public SECURITY INVOKER RPC，並使用 `auth.uid()`、`public.is_admin()`、明確 grants 與 RLS。整體架構方向與目前正式專案的 helper 函式相符，但仍有以下待處理項目：

1. **Idempotency 契約差異**：API 規格要求伺服器端計算 request hash；目前 SQL 草案儲存原始 `request_payload` JSONB 並直接比較，沒有實作 hash 欄位或 hash 計算。需統一規格與實作，再補測同 key 同 payload / 不同 payload。
2. **真實 RLS/grants 尚未驗收**：CI 使用測試 stub；正式專案尚無 private schema/tables/RPC。需要在隔離 Supabase/GoTrue/PostgREST 環境以實際 Auth 簽發 token 驗證。
3. **Data API Exposed schemas 尚未確認**：透過目前 SQL 連線無法讀取 PostgREST 的 `pgrst.db_schemas` 設定；private schema 尚不存在，因此仍需在建立隔離環境時明確確認 private 不在 exposed schemas。
4. **Migration baseline**：本次沒有執行 migration history 修改或 baseline 操作。既有 migration baseline 計畫仍需獨立完成與審核。

## 4. 現有 Security Advisor 提醒（與維護系統分開處理）

本次唯讀 Security Advisor 回報：

- 34 個 `SECURITY DEFINER` functions 可由 anon 及 authenticated 執行。
- 1 個 `SECURITY DEFINER` view：`public.activity_member_stats`。
- 2 張啟用 RLS 但沒有 policy 的 public tables：`member_no_counter`、`visitor_profiles`。
- Auth leaked-password protection 目前停用。

`public.is_admin()` 本身目前未授予 anon EXECUTE，但屬 SECURITY DEFINER，authenticated 可執行。不能只依 Advisor 數量就批次 REVOKE 或改函式；必須逐一檢查用途、依賴、呼叫端及資料表權限，避免破壞現有網站功能。這些既有問題不應混入維護系統 migration 一併修改。

## 5. 真實 Supabase Auth 測試阻擋

正式 Auth 目前有既有帳號，但本次沒有取得任何使用者 access token，也沒有進行登入、建立帳號或改動帳號。不得要求使用者把密碼、access/refresh token、service_role key 貼到聊天或 commit。

在不碰正式資料的前提下，下一個可行路徑是建立免費、隔離的 GoTrue/Auth + PostgreSQL + PostgREST CI 測試服務，讓 GoTrue 自行簽發測試 token，再驗證 JWT claims、PostgREST role switching、RPC、RLS/grants。這仍是隔離環境驗證，不會取代正式部署後的 smoke test，但比自行簽署 JWT 更接近 Supabase Auth 真實流程。不得建立付費 Supabase project/branch。

## 6. 結論與停止界線

- Edge Function 原始碼的 JWT 驗證流程、apikey/bearer 轉送與 RPC body 契約，靜態檢查未發現明顯不一致。
- 正式 Supabase 尚無維護系統 schema、tables、RPC 或 Edge Functions。
- 真正 GoTrue/Auth 簽發 JWT 與正式 RLS 行為尚未驗收。
- SQL 草案至少要先處理 idempotency hash 契約差異。
- Security Advisor 的既有警示需另案逐項審查。

本次只讀檢查沒有修改正式 Supabase、沒有建立測試帳號或測試資料、沒有部署、沒有合併分支，也沒有建立任何付費資源。
