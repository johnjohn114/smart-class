# Maintenance System 權限與 RPC 安全審查 v0.1

> 日期：2026-11-08  
> 分支：`feature/maintenance-system`  
> 性質：唯讀設計審查；未修改正式 Supabase，未建立 schema/RPC，未部署 Edge Functions。

## 1. 審查範圍與限制

本輪依據：
- `docs/maintenance-connection-architecture-v0.4.md`
- `docs/maintenance-pre-sql-verification-v0.2.md`
- `docs/schema-snapshots/20261108-public-functions.sql`
- `docs/schema-snapshots/20261108-public-acl-inventory.json`
- `docs/schema-snapshots/20261108-public-tables-policies.sql`

目前 maintenance private schema、tables、RPC 與五個 Edge Functions 均尚未建立。因此本文件是**設計與現有 catalog 證據審查**，不是執行測試，也不能宣稱 maintenance 權限已驗證。

## 2. 現有管理員 helper 審查

### 2.1 `public.is_admin()`

快照顯示：
- `SECURITY DEFINER`
- owner：`postgres`
- `search_path = ""`
- EXECUTE：`authenticated`、`service_role`、owner；沒有 `anon` 或 `PUBLIC`
- 函式內容以 `auth.uid()` 比對 `public.profiles.id`，並要求 `role = 'admin'`

**判定：可作為 maintenance 管理員檢查的候選 helper。**

必要限制：
1. 寫入 RPC 必須同時檢查 `auth.uid() IS NOT NULL` 與 `public.is_admin()`。
2. actor 欄位只能使用 `auth.uid()`，不得信任前端傳入的 actor/user ID。
3. 不得擴大此 helper 的 EXECUTE 權限。
4. 真正實作後仍須用匿名、一般登入者、管理員三種 JWT 驗證。

此 helper 本身是受控的 SECURITY DEFINER，不代表 maintenance RPC 也應使用 SECURITY DEFINER。

### 2.2 `public.is_admin_user()`

快照顯示：
- `SECURITY DEFINER`
- `search_path = public`
- ACL 明確包含 `anon` EXECUTE

**判定：maintenance system 禁止使用。**

原因是它具有較寬的執行權限與非空 search_path；maintenance 一律以 `public.is_admin()` 為候選授權 helper，不得混用兩套管理員判斷。

## 3. RPC 權限設計審查

### 3.1 公開狀態 RPC

`maintenance_status_public`：
- 僅供讀取維護狀態。
- EXECUTE 明確授予 `anon`、`authenticated`；先撤銷 `PUBLIC` 預設 EXECUTE，再明確授權。
- 僅回傳前端需要的欄位白名單。
- 不回傳 internal note、actor ID、audit log、idempotency key、內部事件識別資訊。
- 不得提供任何寫入能力。

### 3.2 管理寫入 RPC

以下 RPC 僅授予 `authenticated`，並撤銷 `PUBLIC` 與 `anon` EXECUTE：
- `maintenance_event_create`
- `maintenance_event_update`
- `maintenance_event_action`

每個寫入 RPC 必須：
1. 驗證 `auth.uid() IS NOT NULL`。
2. 以 `public.is_admin()` 驗證管理員；不能只檢查 JWT role 或前端傳入的管理員 ID。
3. 使用 `auth.uid()` 寫入 actor/audit 欄位。
4. 驗證輸入型別、允許的狀態轉換、scope 白名單與時間範圍。
5. 在單一 RPC 交易內完成衝突檢查、狀態變更、scope 關聯、audit 與 idempotency。
6. 使用固定 `search_path = ''`，所有 schema/table/function 名稱完整限定。
7. 不回傳不必要的內部欄位或敏感錯誤細節。

`maintenance_admin_list` 僅授予 `authenticated`，並在 RPC 內再次檢查 `auth.uid() IS NOT NULL AND public.is_admin()`。

## 4. SECURITY INVOKER 與 private table grants 的重要界線

SECURITY INVOKER RPC 會以呼叫者權限執行。若 RPC 需要操作 private tables，`authenticated` 必須具備所需的 schema USAGE 與最小 table privileges，並由 RLS 限制資料列。

因此，不能同時宣稱「authenticated 完全沒有 table privileges」又期待 SECURITY INVOKER RPC 能讀寫這些 tables。

另外，PostgreSQL grants/RLS 本身不會辨識某個查詢是從 RPC 內部發出還是直接查表。若授予 authenticated 必要的 table privileges，安全邊界必須依賴：
- private schema 不加入 Data API Exposed schemas；
- private schema 不授予 anon USAGE；
- RLS policies 僅允許必要管理員操作；
- 不提供其他可直接存取 private tables 的 API 路徑。

**文件措辭修正建議：** 不應寫成「table DML 只能透過 RPC」這種由 SQL grants 本身無法保證的絕對描述。應寫成「private schema 不暴露於 PostgREST；authenticated 只取得 invoker RPC 所需的最小 table privileges，並由 RLS 限制；應用程式只提供受控 RPC 入口」。

若未來要求 audit log 在資料庫權限層也不能由一般 authenticated 直接 INSERT，則目前 SECURITY INVOKER 模型可能不足；需另行評估一個極窄、固定 search_path、明確 admin/actor 檢查的 SECURITY DEFINER audit writer，並經獨立人工審查，不可自行擴權。

## 5. Edge Function 身分傳遞

五個 Edge Functions 的共同要求：
- 管理功能設定 `verify_jwt = true`。
- 驗證登入者的 JWT；不可只相信 request body 的 user ID 或 role。
- 使用原始 bearer token 呼叫 RPC，讓資料庫端的 `auth.uid()` 對應真正呼叫者。
- 不得使用 `service_role` 代替使用者身分執行管理 RPC。
- Edge Function 的管理員檢查不能取代 RPC 內的資料庫授權檢查。
- 公開 status 若允許匿名，才將該 function 設為 `verify_jwt = false`，且只能讀取公開狀態 RPC。

## 6. 現階段發現與判定

| 項目 | 判定 | 後續要求 |
|---|---|---|
| `public.is_admin()` | 候選可用 | 保持 ACL/search_path，完成真實 JWT 測試 |
| `public.is_admin_user()` | 禁止使用 | 不得用於 maintenance |
| PUBLIC 預設 EXECUTE | 必須明確撤銷 | 每個新 RPC 都要明確 GRANT |
| private schema exposure | 尚未建立/測試 | 不加入 Data API Exposed schemas |
| SECURITY INVOKER table grants | 設計需精確化 | 以實際 RPC 操作逐項列出最低權限 |
| audit log 防竄改 | 設計尚未定案 | 確認是否接受 authenticated 最小 INSERT + RLS，否則另審受控 writer |
| Edge bearer forwarding | 尚未實作 | 禁止 service_role 冒充使用者 |
| 真實 JWT/RLS 測試 | 尚未執行 | 隔離環境驗證前不得核准正式 migration |

## 7. 本輪結論

**設計方向有條件可行，但尚未達到 migration 核准狀態。**

目前最重要的設計注意事項是 SECURITY INVOKER 所需的 table grants 與「只允許透過 RPC 操作」之間的界線，以及 audit log 是否需要比一般 RLS 更強的寫入隔離。

下一步先定稿 API 行為與事件衝突規則，再把每個 RPC 的輸入、輸出、權限、交易步驟與錯誤碼寫成可審查規格。完成後才進入 Edge Function 開發。

## 8. 本輪未執行

- 沒有執行 DDL/DML。
- 沒有建立 private schema、table、RPC 或 role。
- 沒有修改 Data API Exposed schemas。
- 沒有修改 migration history。
- 沒有部署 Edge Functions。
- 沒有修改正式 Supabase 或建立付費資源。
