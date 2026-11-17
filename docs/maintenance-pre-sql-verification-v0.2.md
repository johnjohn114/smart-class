# 維護系統 SQL 前置驗證報告 v0.2

> 驗證日期：2026-11-08
> Supabase project：fsoowongtavlsrwvzbze
> Git branch：feature/maintenance-system
> 範圍：唯讀資料庫 catalog、Migration metadata、Supabase Edge Function inventory、GitHub snapshot 靜態檢查。

## 1. 驗證總結

| 項目 | 結果 | 判定 |
|---|---|---|
| Migration History | Supabase migration list 為空；supabase_migrations.schema_migrations 不存在 | 阻擋正式 baseline / repair |
| Schema | PostgreSQL 17.6；public 44 tables + 1 view；private schema 不存在 | 盤點確認 |
| RLS | 44/44 public tables 啟用 RLS；98 policies；0 tables FORCE RLS | 需保留在風險清單 |
| RPC admin helper | public.is_admin() 是 SECURITY DEFINER、search_path=''、authenticated 可執行、anon 不可執行 | 可作為候選管理員 helper；仍需真實 JWT 測試 |
| Legacy helper | public.is_admin_user() 是 SECURITY DEFINER、search_path=public、anon 可執行 | 維護系統不得採用 |
| Snapshot 靜態計數 | 44 CREATE TABLE、98 CREATE POLICY、49 CREATE INDEX、38 functions、1 view、7 triggers；sequence 清單列出 2 筆 | 文字盤點吻合；sequence 數量與先前報告有差異，待重新核對 catalog |
| Edge Functions | 遠端存在 6 個函式；未見 maintenance-* 函式 | 維護 Edge Functions 尚未部署 |
| 完整 CLI DDL | 本執行環境未執行 Supabase CLI db pull / pg_dump | 未完成 |

## 2. 連線模型的實際資料庫核對

### 2.1 public.is_admin()

實際 catalog 定義：
- signature：public.is_admin()
- SECURITY DEFINER：true
- search_path：空字串（固定）
- owner：postgres
- EXECUTE：authenticated=true、service_role=true、anon=false
- 函式內容以 auth.uid() 查詢 public.profiles.role='admin'。

這個 helper 不是 SECURITY INVOKER；它是被刻意縮限的 SECURITY DEFINER 權限檢查函式。這與「維護 RPC 優先 SECURITY INVOKER」並不衝突，但必須明確記錄為唯一受控 helper，並驗證其 owner、ACL、search_path 與函式內容不被不當改動。

### 2.2 不得使用 public.is_admin_user()

此函式同樣為 SECURITY DEFINER，但 search_path=public，且 anon 具有 EXECUTE。維護系統不可使用此 helper 作為管理權限依據；應統一使用 public.is_admin()，並在 migration review 中確認其 ACL 未擴大。

### 2.3 private schema 與 PostgREST

目前 private schema 不存在。故以下項目尚無法實測：
- private schema USAGE 與 table grants 的最小授權組合。
- public SECURITY INVOKER RPC 對 private tables 的實際存取。
- private 未列入 Data API Exposed schemas 時，REST 端點是否不可直接存取。
- RLS policies 在 authenticated admin／non-admin JWT 下的實際結果。

這些必須在隔離環境測試；不可在正式資料庫先建立 private schema 來試。

## 3. RLS 與現有 view 注意事項

- public 44 tables 全部啟用 RLS，但沒有任何一張 table 設定 FORCE ROW LEVEL SECURITY。
- public 有 98 policies。
- activity_member_stats view 的 reloptions 為 NULL，owner 為 postgres，ACL 包含 anon、authenticated、service_role。這代表 view 沒有明確設定 security_invoker=true；與先前 Advisor 的 security_definer_view 警示一致。
- 此 view 是既有安全加固範圍，不應在維護系統 migration 中順便修改；須由獨立 security-hardening 分支處理並驗證。

## 4. Edge Function 現況

遠端列出 6 個已部署 Edge Functions：
- manage-visitors（verify_jwt=true）
- create-visitor（列表中另有 clever-service alias，verify_jwt=false；另有 create-visitor，verify_jwt=true）
- set-visitor-password（verify_jwt=false）
- ai-generate-announcement（verify_jwt=false）
- send-announcement-push（verify_jwt=true）

未見 maintenance-status、maintenance-admin-list、maintenance-event-create、maintenance-event-update、maintenance-event-action。此結果只代表目前 Supabase Edge Function inventory，不能推論 GitHub 中不存在未部署程式碼。

## 5. Snapshot 靜態檢查

已提交 snapshot 檔案的靜態物件計數：
- tables/policies/indexes SQL：44 tables、98 policies、49 indexes。
- views SQL：1 view。
- functions SQL：38 functions。
- triggers SQL：7 triggers。
- enum types：無。
- sequences inventory：快照檔案列出 2 個 public sequences；先前報告記載 1 個，兩者不一致，需重新執行唯讀 catalog 查詢確認實際數量。

已將 snapshot README 的 trigger 數由 9 修正為 7。

**限制：** 靜態計數只證明文字中物件定義數量，不證明 SQL 可執行、依賴順序正確或可重建整個 Supabase 專案。Snapshot 不是 pg_dump 或 CLI db pull。

## 6. 本輪阻擋項目與後續測試

1. 完整 schema baseline：需在使用者可控本機環境執行 Supabase CLI db pull，再檢查完整 schema-only DDL。
2. Migration history：先確認 CLI 版本與 migration repair 行為；history table 不存在且目前 migration list 空集合，不可直接 repair。
3. 連線模型：先在隔離環境建立 private schema 測試架構；用匿名、一般 authenticated、admin JWT 驗證 public RPC 與 private table 權限。
4. RPC 權限：測試非管理員呼叫所有管理 RPC 均拒絕；管理員呼叫成功；anon 只能讀公開狀態 RPC。
5. Edge Function：驗證 verify_jwt=true、轉送原始 bearer token、絕不以 service_role 替代使用者 JWT。
6. transaction：對 create/update/action 執行併發、重複 idempotency key、衝突與 audit atomicity 測試。
7. view security_invoker 警示維持在獨立 security-hardening 分支，不混入本維護功能。

## 7. 本輪沒有執行

- 沒有 DDL 或 DML。
- 沒有 migration repair / db push / db reset。
- 沒有建立 private schema、table、RPC 或 role。
- 沒有部署或修改 Edge Function。
- 沒有修改正式資料庫。
- 沒有建立 Supabase project/branch 或付費資源。
