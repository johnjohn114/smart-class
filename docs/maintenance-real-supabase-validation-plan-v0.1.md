# 真實 Supabase Auth / PostgREST 驗證計畫 v0.1

> 日期：2026-11-16  
> 分支：`feature/maintenance-system`  
> 狀態：預檢完成；正式 Supabase 驗收尚未開始。本文只記錄測試方案與阻擋條件，不執行資料庫寫入或部署。

## 1. 目前 CI 已驗證的範圍

GitHub Actions run [43875775024](https://github.com/johnjohn114/smart-class/actions/runs/43875775024) 已成功：
- PostgREST 服務容器啟動。
- 測試環境自行簽署的 HS256 JWT 能讓 PostgREST 設定 anon/authenticated role claims。
- 測試環境中的公開 status RPC、管理 RPC、過期 JWT、非管理員拒絕、private table 不暴露等檢查通過。
- 兩筆同時送出的重疊全站排程，預期只允許一筆成功。
- Deno 型別檢查、22 項驗證測試與 SQL 靜態檢查通過。

**重要限制：** CI 使用自行簽署的短效 JWT、測試用 `auth.uid()` / `public.is_admin()` stub 與臨時 PostgreSQL；它不是 GoTrue/Supabase Auth 簽發的真實 access token，也不是正式 Supabase 專案的 RLS 驗收。

## 2. 正式 Supabase 只讀預檢（2026-11-16）

Project ref：`fsoowongtavlsrwvzbze`

只讀查詢結果：
- 專案狀態：`ACTIVE_HEALTHY`。
- PostgreSQL：17.11。
- Migration history：目前回傳空集合。
- `private` schema：不存在。
- 六張維護資料表：尚未建立。
- 五個 maintenance RPC：尚未建立。
- 五支 maintenance Edge Functions：尚未部署。
- 現有 `public.is_admin()`：存在，為 `SECURITY DEFINER`，`search_path = ''`，owner 為 postgres；ACL 有 authenticated EXECUTE，未見 anon EXECUTE。
- `public.is_admin()` 查詢 `public.profiles` 中 `auth.uid()` 對應的 `role='admin'`。
- profiles 的現有 RLS policy 包含 `profile_admin_all`、`profile_self_read`、`profile_self_update`。

以上是當前預檢快照，不代表已驗證真實 JWT 權限。正式 DB 沒有被修改。

## 3. 真實驗收的必要條件

必須先有可安全測試的隔離環境，並在該環境建立維護 SQL draft 所需的 schema、tables、RPC、grants 與 RLS。不得把測試資料寫入正式網站資料庫。

測試身分應由 Supabase Auth/GoTrue 實際簽發：
1. 匿名：publishable/anon API key，不帶 user access token。
2. 一般會員：隔離測試帳號登入取得 access token。
3. 管理員：隔離測試帳號對應 profiles.role=admin，登入取得 access token。

不要把 access token、refresh token、密碼、service_role key 或其他 secret 貼到聊天、commit、CI log 或測試報告。應由隔離測試程序在執行時取得並在本機/CI secret store 中短暫使用。

## 4. 真實測試矩陣

| 測試 | 匿名 | 一般會員 | 管理員 |
|---|---|---|---|
| Supabase Auth `/auth/v1/user` | 不適用/未登入 | token 可驗證 | token 可驗證 |
| public status RPC | 允許 | 允許 | 允許 |
| admin list RPC | 拒絕 | 拒絕 | 允許 |
| event create/update/action RPC | 拒絕 | 拒絕 | 允許 |
| private table REST endpoint | 不可直接存取 | 不可直接存取 | 不可直接存取 |
| internal_note / audit / idempotency | 不可讀 | 不可讀 | 僅透過受控管理 RPC 取得必要資料 |

額外檢查：
- 無 token、過期 token、簽章錯誤 token、錯誤 audience/role claim。
- Edge Function 是否轉送原始 bearer token，且只使用 publishable/anon key。
- PostgREST 的 `p_request` JSON 參數與五個 SQL RPC signatures 完全一致。
- `auth.uid()` 對應實際登入者；admin 判斷來自 profiles.role，不信任前端 role。
- public status 不回傳 internal_note、actor IDs、audit 或 idempotency 資料。
- RPC EXECUTE grants、private schema USAGE、table grants 與 RLS 組合符合最小權限。

## 5. 併發與一致性測試

必須在隔離 DB 執行，使用兩個以上獨立連線/請求同時送出：
- global/global 重疊：最多一筆成功。
- global/local 重疊：最多一筆成功。
- local/local 同 scope 重疊：最多一筆成功。
- local/local 不同 scope：依產品規則允許或拒絕，特別驗證 site_core。
- 同一 idempotency key + 同 payload：回傳同一結果，不重複寫入。
- 同一 key + 不同 payload：409。
- 相同 expected_version 的並行 update/action：只有一筆能成功。
- 任一交易中途失敗：event、scope links、audit、idempotency 不得留下部分資料。

現有 CI 的雙請求併發測試已在隔離 PostgreSQL/PostgREST 通過；真實 Supabase 版本仍待隔離環境複驗。

## 6. 阻擋與停止條件

目前正式專案沒有維護 schema/RPC/Edge Functions，因此不能對正式專案發出真實 maintenance RPC 測試。

在沒有獲得額外明確授權前：
- 不執行 migration、DDL、DML、seed 或測試資料寫入。
- 不建立/刪除 Supabase Auth 使用者。
- 不修改 Data API Exposed schemas、RLS、grants 或現有 `public.is_admin()`。
- 不部署 Edge Functions。
- 不建立 Supabase branch/project 或任何可能收費的資源。
- 不要求使用者提供任何密碼、token 或 service_role key。

下一階段應先以不產生費用的隔離方式準備真正的 Supabase Auth/GoTrue 測試環境；若目前執行環境沒有 Docker/Supabase CLI 或無法安全啟動 GoTrue/PostgREST，必須如實標示阻擋，不得以自行簽署 JWT 測試冒充真實 Auth 驗收。
