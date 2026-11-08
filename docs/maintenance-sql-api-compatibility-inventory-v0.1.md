# Maintenance SQL 與 API v0.5 相容性盤點 v0.1

> 日期：2026-11-08  
> 分支：`feature/maintenance-system`  
> 性質：唯讀盤點；不是 migration，不可執行。  
> 結論：原始四表 SQL 尚未取得，因此本文件只記錄可由現有證據確認的事項與阻擋條件。

## 1. 本輪實際可取得的來源

目前可讀取的使用者附件：
- `啟動第一步檢查.txt`

該附件內容是先前 SQL 審查摘要，列出四個預期資料表名稱：
- `maintenance_state`
- `maintenance_events`
- `maintenance_scopes`
- `maintenance_audit_logs`

但附件沒有 SQL 原始碼，不包含 `CREATE TABLE`、欄位定義、constraint、index、trigger、RLS policy 或 GRANT statement。附件中提及的 `v26.11.7_maintenance_migration_review.sql` 並未隨本輪附件提供；不能以先前對話中的下載連結或摘要代替實際 SQL 檔案。

## 2. 現有 Supabase schema snapshot 核對

檢查 `docs/schema-snapshots/20261108-public-tables-policies.sql`：

- 找不到上述四個 maintenance table 名稱。
- 因此目前快照沒有證據顯示這四張維護資料表已存在於 public schema。
- 本輪不推論 private schema 也不存在於當前遠端以外的任何環境；以既有 pre-SQL verification 記錄為準，當時 private schema 尚不存在。

### 2.1 可確認的既有關聯欄位

`public.announcements`：
- `id uuid DEFAULT gen_random_uuid() NOT NULL`
- 可支持「若 maintenance event 要關聯公告，UUID 型別可相容」這項初步判斷。
- 但 API v0.5 尚未確認維護事件是否必須關聯 announcement；不得因此自行新增 FK。

`public.profiles`：
- `id uuid NOT NULL`，FK 指向 `auth.users(id)`
- `role text DEFAULT 'visitor' NOT NULL`
- 現有 `public.is_admin()` 候選 helper 依此 profile/role 模型判斷管理員；仍需真實 JWT 測試。
- 不得在 maintenance tables 再建立另一套可由客戶端任意指定的 actor/admin 欄位作為授權來源。

## 3. 依 API v0.5 必須滿足的資料模型能力

這些是需求能力，不是已核實的欄位名稱：

1. 維護事件：標題、公開訊息、內部備註、全站/局部旗標、開始/結束時間、狀態、version、建立/更新時間及 actor/audit 關聯。
2. Scope 關聯：支援七個既定 scope code；全站事件不得帶 scope links；局部事件至少一個 scope。
3. Audit：與事件變更同交易寫入，actor 取自 `auth.uid())，不得由 request 指定。
4. Idempotency：create/update/action 的 key 與 payload/result 關聯必須在交易內一致處理。
5. 衝突控制：排程建立/修改需在資料庫交易內處理競爭條件，不能只靠 Edge Function 先查再寫。
6. 公開狀態：只能回傳 API v0.5 白名單欄位；不得洩漏 internal note、actor IDs、audit 或 idempotency 資料。
7. 權限：private schema、SECURITY INVOKER RPC、最小 grants、RLS；不使用 service_role 代表使用者。

## 4. 與舊 SQL 摘要的待核對項目

| 項目 | 摘要提及 | 原始 SQL 證據 | 狀態 |
|---|---|---|---|
| 四張表 | 有 | 無 | 阻擋 |
| 欄位與型別 | 無完整資料 | 無 | 阻擋 |
| announcement FK | 摘要稱 UUID 相容 | 無 FK SQL | 未核實 |
| 七個 scope codes | 有 | 無 CHECK/seed SQL | 未核實 |
| RLS policies | 摘要稱四表啟用 | 無 policy SQL | 未核實 |
| anon/authenticated grants | 摘要稱不授權 | 無 GRANT/REVOKE SQL | 未核實 |
| service_role grants | 摘要稱曾過寬且已修正 | 無修正版 SQL | 未核實 |
| audit truncate trigger | 摘要稱已增加 | 無 trigger/function SQL | 未核實 |
| indexes/unique constraints | 未完整列出 | 無 | 阻擋 |
| RPC signature/body | 未提供 | 無 | 尚待撰寫 |

## 5. 與目前 Edge Function 呼叫端的介面

本分支 Edge Functions 已採用開發契約：
- RPC 位於 `public`。
- 每個 RPC 使用單一 `p_request jsonb` 參數。
- Edge Function 以原始 user bearer token 呼叫 RPC。
- 管理 RPC 必須在 DB 端再次檢查 `auth.uid() IS NOT NULL AND public.is_admin()`。
- 所有管理操作及 audit/idempotency/衝突控制必須在單一 DB transaction 內完成。

此為呼叫端目前採用的契約，不代表資料庫已存在這些 signature。原始 SQL 若採不同結構，需先修正呼叫契約或設計 adapter；不得靜默假設相容。

## 6. 開始撰寫 migration 前的阻擋條件

取得原始 `v26.11.7_maintenance_migration_review.sql` 後，逐項核對：
1. CREATE TABLE 與欄位型別/default/nullability。
2. PK/FK/CHECK/UNIQUE 與索引。
3. 所有 trigger/function 及觸發時機。
4. RLS enable/force 與每一條 policy。
5. schema/table/function ACL、PUBLIC/anon/authenticated/service_role 權限。
6. audit append-only 保護的實際邊界及 owner/superuser 限制。
7. 與 API v0.5 五個 RPC 所需交易能力的差距。
8. private schema Data API exposure、SECURITY INVOKER grants 與 RLS 的可行性。

在以上核對完成前，不產生聲稱可直接執行的最終 migration SQL，不執行任何 Supabase DDL/DML。

## 7. 本輪執行紀錄

- 已讀取使用者附件全文。
- 已讀取目前 branch 的 public schema snapshot 與 API v0.5、安全審查文件。
- 已確認 snapshot 未包含四張 maintenance tables。
- 已確認 `public.announcements.id` 為 UUID，`public.profiles.id` 為 UUID 且 role 欄位存在。
- 未修改 Supabase。
- 未執行 SQL。
- 未部署或建立付費資源。
