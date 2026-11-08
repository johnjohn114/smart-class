# Maintenance System 權限與 RPC 安全審查 v0.2

> 日期：2026-11-08  
> 分支：`feature/maintenance-system`  
> 性質：唯讀設計審查與規格決議；未修改 Supabase、未建立 schema/RPC、未部署 Edge Functions。

## 1. 審查範圍

本版依據：
- `docs/maintenance-connection-architecture-v0.4.md`
- `docs/maintenance-api-spec-v0.5.md`
- `docs/maintenance-pre-sql-verification-v0.2.md`
- `docs/schema-snapshots/20261108-public-functions.sql`
- `docs/schema-snapshots/20261108-public-acl-inventory.json`

Maintenance private schema、tables、RPC 與 Edge Functions 仍未建立。因此這是設計審查，不是真實 JWT/RLS 測試，也不能宣稱權限已驗證。

## 2. 現有管理員 helper

### 2.1 `public.is_admin()`

現有快照顯示：
- SECURITY DEFINER，owner 為 postgres。
- 固定空 `search_path`。
- EXECUTE 授權包含 authenticated、service_role 與 owner；沒有 anon 或 PUBLIC。
- 函式依 `auth.uid()` 比對 `public.profiles.id`，並要求 role 為 admin。

判定：只可作為 maintenance RPC 內部的候選管理員 helper。實作後仍須以 anon、一般 authenticated、admin 三種 JWT 驗證。不得擴大 EXECUTE 權限。

### 2.2 `public.is_admin_user()`

現有快照顯示其 SECURITY DEFINER、`search_path=public`，且 ACL 包含 anon EXECUTE。

判定：Maintenance System 禁止使用。不得與 `public.is_admin()` 混用。

## 3. 公開維護狀態 RPC 決議

**決議：`maintenance_status_public` 維持 SECURITY INVOKER，不採用 public SECURITY DEFINER。**

理由：避免在 exposed public schema 增加以高權限 owner 執行的公開函式，並保留呼叫者權限與 RLS 的約束。

必要條件：
1. 撤銷該 RPC 的 PUBLIC 預設 EXECUTE，再明確授予 anon、authenticated。
2. anon 僅取得必要的 private schema USAGE 與公開狀態資料 SELECT。
3. anon 不得取得任何 private table 寫入或管理權限。
4. status 相關 RLS policy 僅允許 anon 讀取允許公開的資料列。
5. RPC SELECT 清單只包含公開欄位白名單；RLS 不提供欄位級保護，故不能以 RLS 取代欄位白名單。
6. private schema 不加入 Data API Exposed schemas；這可避免一般 PostgREST table endpoint 暴露，但不能取代 grants/RLS。
7. 若 anon grants + RLS 無法安全實現，停止實作並重新審查；不得自行改成 SECURITY DEFINER。

此為設計決議，尚未經 anon JWT、PostgREST 與 RLS 行為測試。

## 4. 管理 RPC 與 private table grants

管理 RPC 維持 SECURITY INVOKER。每個 RPC 必須在資料庫端檢查：
- `auth.uid() IS NOT NULL`
- `public.is_admin()`

actor 一律由 `auth.uid()` 取得，不接受前端傳入 actor/user ID。

authenticated 僅取得實際 RPC 操作所需的最小 schema/table privileges；所有 private tables 啟用 RLS，管理政策明確限制 admin。不得聲稱「authenticated 完全沒有 table grants」卻又要求 SECURITY INVOKER 操作這些 tables。

private schema 不暴露於 Data API；前端只呼叫受控 Edge Functions/RPC。這是應用程式入口限制，不代表 PostgreSQL grants 能辨識 SQL 是由 RPC 內部或其他資料庫路徑發出。

## 5. Audit log 寫入邊界決議

第一版維持 SECURITY INVOKER，不新增 SECURITY DEFINER audit writer。

- audit table 不授予 anon 任何權限。
- authenticated 僅取得交易流程所需的最小 INSERT/SELECT 權限；不得授予 UPDATE/DELETE。
- RLS policy 限制 audit insert/read 為已登入且通過 admin 檢查的呼叫者。
- actor 一律取自 `auth.uid()`。
- private schema 不加入 Data API Exposed schemas；前端不提供 audit table 直接操作入口。

**限制必須明確揭露：** PostgreSQL grants/RLS 不會辨識操作是從 RPC 內部或其他資料庫路徑發出。因此不能宣稱資料庫權限層絕對禁止 authenticated 直接 INSERT audit。若產品要求更強的資料庫層防竄改，須另案審查專用 writer 的 owner、ACL、search_path、RLS 影響，並完成隔離測試後才可採用。

此外，資料庫擁有者/超級管理員仍可能修改紀錄，不得宣稱 audit 絕對不可竄改。

## 6. RPC 權限矩陣（設計目標）

| RPC | SECURITY | EXECUTE | 資料權限要求 |
|---|---|---|---|
| maintenance_status_public | INVOKER | anon、authenticated | anon 最小 USAGE/SELECT + 公開資料 RLS |
| maintenance_admin_list | INVOKER | authenticated | admin check + 最小 SELECT/RLS |
| maintenance_event_create | INVOKER | authenticated | admin check + 最小寫入/RLS |
| maintenance_event_update | INVOKER | authenticated | admin check + 最小讀寫/RLS |
| maintenance_event_action | INVOKER | authenticated | admin check + 最小讀寫/RLS |

所有新 RPC 撤銷 PUBLIC EXECUTE 後再明確 GRANT。管理 RPC 不授予 anon。不得使用 service_role 代表使用者執行管理操作。

## 7. Edge Function 身分傳遞

- 管理 Edge Functions 設定 `verify_jwt=true)。
- 使用 Auth 驗證呼叫者，並將原始 bearer token 傳給 RPC client。
- 不得使用 service_role 代替使用者 JWT。
- Edge Function 的驗證不能取代 RPC 內的資料庫授權。
- 公開 status 可匿名呼叫；其 Edge Function 是否設定 `verify_jwt=false) 必須與實際 API gateway/JWT 驗證方式一致，並且只執行公開唯讀操作。

## 8. 實作前驗收條件

隔離環境至少測試：
1. anon 可呼叫 status，且只得到公開白名單欄位。
2. anon 無法呼叫任何管理 RPC，也無法寫入 private tables。
3. 一般 authenticated 使用者不能讀取管理清單或執行寫入。
4. admin 使用原始使用者 JWT 可執行核准操作。
5. 偽造 actor_id、user_id、role 不會改變資料庫授權或 audit actor。
6. audit 不允許 anon/一般使用者寫入；authenticated 的直接 table path 風險依 private schema 不暴露及 RLS 設計確認。
7. 所有 private tables 啟用 RLS，RPC EXECUTE ACL 最小化。
8. 交易、併發衝突、version conflict、idempotency 均通過測試。

完整 PostgreSQL 還原測試依專案決定跳過；此項不得標示通過。若沒有可用隔離環境完成真實 JWT/RLS 驗證，不得核准正式 migration 或部署。

## 9. 本輪未執行

- 沒有執行 DDL/DML。
- 沒有建立 private schema、table、RPC 或 role。
- 沒有修改 Supabase Data API Exposed schemas。
- 沒有修改 migration history。
- 沒有部署 Edge Functions。
- 沒有修改正式 Supabase 或建立付費資源。
