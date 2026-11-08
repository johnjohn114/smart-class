# 維護系統資料庫連線模型決策 v0.4

> 日期：2026-11-08
> 分支：feature/maintenance-system
> 狀態：設計決策；尚未實作、尚未生成正式 migration。

## 1. 決策摘要

**採用：Edge Function + 使用者 JWT + PostgREST public RPC（SECURITY INVOKER）+ private schema tables + RLS。公開 status RPC 也維持 SECURITY INVOKER，透過 anon 的最小 schema/table 權限與嚴格 RLS 提供唯讀公開資料；不採用 public SECURITY DEFINER。**

不採用：
- Edge Function 以 postgres／資料庫 owner 連線直接 CRUD private tables。
- 使用 service_role 代表一般使用者呼叫維護資料庫操作。
- 在第一版把 private schema 加入 Data API Exposed schemas。
- 將 SECURITY DEFINER public RPC 當成一般預設方案。

理由：
1. 可沿用 Supabase Auth JWT 與現有 auth.uid()。
2. 維護表留在 private schema，不直接暴露成 REST 資料表端點。
3. RPC 使用 SECURITY INVOKER，讓呼叫者權限與 RLS 仍然生效。
4. 不需要額外資料庫登入角色、DB URL secret 或付費 Supabase branch。
5. 管理員授權由資料庫既有 public.is_admin() 作為 RLS／函式檢查依據。

## 2. 架構流程

1. 瀏覽器以既有 Supabase Auth session 呼叫維護 Edge Function。
2. 管理 Edge Function verify_jwt=true，使用 auth.getUser() 驗證呼叫者。
3. Edge Function 使用同一個 Authorization bearer token + publishable/anon key 建立 Supabase client；不得換成 service-role key。
4. Edge Function 呼叫 public RPC gateway。
5. RPC 函式為 SECURITY INVOKER，固定 search_path=''，完整限定所有 schema/table/function 名稱。
6. RPC 讀寫 private schema；private schema 的 USAGE 和所需 table grants 僅授予實際需要的角色。公開 status RPC 需要 anon 時，anon 僅取得 schema USAGE 與公開狀態資料所需 SELECT，並由專用 RLS policy 限定可見列；管理寫入仍僅 authenticated。
7. 寫入 RPC 先檢查 auth.uid() IS NOT NULL AND public.is_admin()；actor id 一律 auth.uid()。
8. 公開 status RPC 維持 SECURITY INVOKER，只回傳明確欄位白名單；anon 的 private schema SELECT 由 RLS 限定為可公開狀態資料，不回傳 internal_note、actor、audit、idempotency。

## 3. Schema / grants / RLS 原則

- private 不加入 Data API Exposed schemas。
- private schema 預設不授予 anon；唯一例外是公開 status RPC 經審查確實需要時，授予 anon schema USAGE 與最小 SELECT，且 RLS 僅允許讀取公開狀態資料。此例外不等於將 private schema 加入 Data API Exposed schemas。
- private tables 撤銷 PUBLIC、anon、authenticated 的直接 DML；但 invoker RPC 必須有其實際執行所需的最小 table privileges。故不能同時聲稱 authenticated 完全沒有 table grants，又期待 SECURITY INVOKER 能操作 private tables。
- 精確授權：公開狀態 SELECT 僅在必要時授予 anon，並由 RLS 僅暴露可公開資料；管理操作所需 SELECT/INSERT/UPDATE 等僅授予 authenticated 管理員並由 RLS 限制。audit/idempotency 僅授予管理 RPC 所需的最小權限，並由 RLS 限制 admin。由於 PostgreSQL grants/RLS 不區分查詢是否來自 RPC，不能宣稱 table DML 在資料庫權限層只能經 RPC；安全邊界還依賴 private schema 不暴露於 PostgREST、RLS 與應用程式只提供受控 RPC。若需求提升為資料庫層禁止 authenticated 直接寫 audit，須另立方案並獨立審查，不得自行改用 SECURITY DEFINER。
- RLS 啟用於所有 private tables；admin policies 使用 public.is_admin()，並加上 auth.uid() IS NOT NULL。
- RPC 預設撤銷 PUBLIC EXECUTE；寫入 RPC 僅授予 authenticated。公開狀態 RPC 明確授予 anon、authenticated。
- SECURITY INVOKER 函式使用 SET search_path='' 並全限定名稱。
- 不把 service_role 加入一般應用權限設計。

## 4. 五個 API 的實作方式

| Edge Function | RPC | 呼叫角色 | 權限 |
|---|---|---|---|
| maintenance-status | maintenance_status_public | anon / authenticated | 公開欄位白名單 |
| maintenance-admin-list | maintenance_admin_list | authenticated | is_admin() |
| maintenance-event-create | maintenance_event_create | authenticated | is_admin() |
| maintenance-event-update | maintenance_event_update | authenticated | is_admin() |
| maintenance-event-action | maintenance_event_action | authenticated | is_admin() |

Edge Function 不自行拆成多個 table REST calls 來完成交易。每個寫入 RPC 在單一 PostgreSQL 函式呼叫中完成鎖定、衝突檢查、事件、scope links、audit 與 idempotency；PostgreSQL function call 本身位於單一交易上下文。

## 5. 為何不採用其他方式

### 5.1 直接 DB URL
如果 Edge Function 使用 postgres 或 database owner 連線，這類角色可繞過 RLS；應用程式每一處都必須自己實作授權，容易出現漏檢。另需管理資料庫密碼與 pooler 連線設定，並不符合目前不新增 secret／維運負擔的目標。

### 5.2 service_role
service_role 可 bypass RLS，且不能代表一般使用者 JWT 身分。若用它執行管理 RPC，資料庫端 auth.uid() 不會自然等於真正呼叫者，必須額外傳遞並可信地驗證 actor，容易產生身分混淆。

### 5.3 SECURITY DEFINER public RPC
SECURITY DEFINER 會以函式 owner 權限執行，可能繞過 RLS；若確實需要，必須極少量、固定 search_path、完整限定名稱、內部 admin check、最小回傳，並逐函式測試與審查。第一版優先避免。

## 6. 必須在實作前驗證的細節

1. public.is_admin() 在 authenticated 使用者 JWT 呼叫時能正確讀取 auth.uid()。
2. private schema 的 USAGE、table grants 與 RLS 組合，能讓公開 status RPC 的 anon 唯讀及管理 RPC 的 authenticated 操作成立；同時確認 private schema 未加入 Data API Exposed schemas。
3. PostgREST 對 private schema 的不暴露設定生效；public RPC 可正常呼叫。匿名 status 必須驗證只讀取公開白名單資料。
4. Edge Function 轉送原始 bearer token，不會意外以 service role 建立 client。
5. Edge Function verify_jwt=true；status function 若允許匿名，需明確 verify_jwt=false 並只做公開讀取。
6. 所有寫入 RPC 在併發測試中保持單一交易、idempotency 與 advisory lock 語意。

## 7. 尚未做的事

- 未建立 private schema。
- 未建立任何 table 或 RPC。
- 未修改 Dashboard Data API Exposed schemas。
- 未新增 Edge Function secret。
- 未部署 Edge Function。
- 未修改正式 Supabase。

本文件為設計決策，需在隔離環境完成 anon/authenticated/admin JWT、RLS 與 grants 測試後才能轉成 migration。完整 PostgreSQL 還原測試依專案決定跳過，不能以此取代權限行為驗證。
