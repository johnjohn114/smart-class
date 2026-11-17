# Maintenance System 權限與資料暴露審查 v0.3

> 日期：2026-11-15
> 分支：`feature/maintenance-system`
> 性質：GitHub 靜態程式碼與 SQL 草案審查；不是 live Supabase 權限測試。

## 1. 審查範圍

本輪檢查：
- 六張 `private` 資料表的 RLS policies 與 grants。
- 五個 public RPC 的 SECURITY INVOKER、search_path 與資料讀寫範圍。
- Edge Functions 的 JWT 驗證與原始使用者 bearer token 傳遞。
- `supabase/config.toml` 的公開 status 與管理端點 gateway 設定。
- 已保存的 2026-11-08 public schema / ACL snapshot，僅作歷史參考。

## 2. 本輪發現與處理

### 2.1 公開事件資料列原本含建立者識別欄位

原 SQL 草案的 `maintenance_events.created_by` 欄位預設為 `auth.uid()`。雖然 anon 的 column-level SELECT grant 沒有包含此欄位，但所有 authenticated 使用者另有整表 SELECT 權限，且公開 active-event RLS policy 允許讀取正在生效的事件。若 private schema 日後被錯誤加入 Data API Exposed schemas，一般登入使用者可能直接讀取該欄位。

**處理：** 已從目前 SQL 草案移除 `created_by` 欄位與 INSERT policy 中的欄位相等檢查。管理 RPC 的授權仍由 `auth.uid() IS NOT NULL AND public.is_admin()` 強制執行；audit actor 仍由 `admin_id DEFAULT auth.uid()` 產生，不接受前端傳入 actor。

取捨：第一版不在事件資料列保存建立者 ID。若未來產品需要顯示建立者，應另行設計 admin-only metadata 欄位/表，不能重新加入公開可讀事件資料列。

### 2.2 公開與管理資料邊界

靜態檢查確認 SQL 草案：
- anon 僅有 scope catalog 的白名單欄位 SELECT，以及事件公開欄位 `id,title,message,is_global,status,starts_at,ends_at` 和 active scope links 的 SELECT。
- anon 沒有 private table INSERT、UPDATE、DELETE grants。
- `maintenance_event_private_notes` 有獨立的 admin-only SELECT/INSERT/UPDATE RLS policies；沒有 anon grants。
- audit 與 idempotency 沒有 anon grants；audit 沒有 UPDATE/DELETE grants，且設有 UPDATE/DELETE/TRUNCATE triggers。
- 六張 private tables 全部啟用 RLS。
- 五個 public RPC 均為 SECURITY INVOKER 且固定 `search_path = ''`。
- 管理 RPC 在資料庫端檢查登入者及 `public.is_admin()`。
- 管理 Edge Functions 設 `verify_jwt=true`；公開 status 設 `verify_jwt=false`，但函式只提供唯讀 status 並對可選 token 驗證後才傳遞。

## 3. 仍然存在的限制與上線條件

1. **private schema 必須排除於 Supabase Data API Exposed schemas。** 目前 GitHub 檔案無法證明 Dashboard 設定現況。
2. authenticated 需要 SECURITY INVOKER RPC 實際所需的 table grants。PostgreSQL grants/RLS 無法辨識 SQL 是由 RPC 內部還是其他資料庫路徑執行；尤其 admin 直接 INSERT audit 的風險已在 v0.2 設計審查揭露。不得宣稱 audit 對資料庫管理者或具權限 admin 絕對不可竄改。
3. 目前保存的 ACL snapshot 日期為 2026-11-08，且不是 live 查詢；它不能證明現在的資料庫狀態。
4. 尚未使用 anon、一般 authenticated、admin 的真實 JWT 驗證 PostgREST、RLS、RPC ACL 和欄位可見性。
5. 尚未完成 PostgreSQL SQL parser / migration 驗證；靜態字串檢查不能代替資料庫測試。
6. 不得將此審查視為正式 Supabase 已建立六張表或已套用權限。

## 4. 結論

**靜態設計方向：可繼續進入隔離環境驗證，但目前不核准正式 migration 或部署。**

本輪只修改 GitHub `feature/maintenance-system` 分支的 SQL 草案、靜態檢查腳本與測試。未執行 DDL/DML、未修改 Supabase、未部署 Edge Functions、未建立付費資源。
