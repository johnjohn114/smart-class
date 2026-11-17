# 三項 SQL 前置工作整合審查結果 v0.1

> 日期：2026-11-08
> 分支：feature/maintenance-system
> 範圍：DDL snapshot、migration history reconciliation、DB connection model。

## 1. 結果總覽

| 工作 | 結果 | 是否可視為完成 |
|---|---|---|
| public schema catalog snapshot | 已建立多份 catalog reconstruction，涵蓋 tables、columns、constraints、indexes、RLS policies、table grants、views、functions、triggers、types/sequences、ACL inventory | **部分完成；不是完整 pg_dump/CLI baseline** |
| Migration history 修復對照表 | 三份 migration 已逐檔比對 Git commit 與正式 DB 物件；沒有足夠證據可 repair applied | **審查對照表完成；實際 repair 刻意未做** |
| DB connection model 統一 | 已決策為使用者 JWT + public SECURITY INVOKER RPC + private schema + RLS；舊 v0.3 文件加上 superseded 提示 | **設計決策完成；實作驗證未做** |

## 2. 主要決策

- 不以 postgres／database owner 連線直接 CRUD private tables。
- 不使用 service_role 代表一般使用者呼叫維護 RPC。
- private schema 不加入 Data API Exposed schemas。
- RPC 優先 SECURITY INVOKER，固定 search_path=''，完整限定名稱。
- 由 Edge Function 驗證原始使用者 JWT，再以同一 bearer token 呼叫 RPC。
- 管理寫入 RPC 僅授權 authenticated，內部檢查 auth.uid() 與 public.is_admin()。
- 公開狀態 RPC 只回傳白名單欄位。
- invoker RPC 所需的最小 private schema/table grants 仍須授予對應角色，再由 RLS 限制資料列；不可錯誤地同時撤銷所有 table grants 又期待 invoker function 可執行。

## 3. Migration History 結論

- 20261031_app_releases.sql：遠端物件不吻合，不可標記 applied。
- 202610310001_app_releases.sql：物件形狀吻合候選，但沒有執行證據，不 repair。
- 26.11.3_calendar_fields.sql：物件形狀吻合候選，但沒有執行證據，不 repair。
- migration list 空集合且 schema_migrations 不存在；必須用 CLI 官方 baseline workflow 在受控環境處理，不能手動造 history。

## 4. DDL Snapshot 限制

已提交 catalog reconstruction 文件，但它們不是完整、可直接重建資料庫的 DDL dump。原因：
- 執行環境沒有 Supabase CLI、psql、pg_dump。
- 有些檔案只保存 inventory 或定義文字，尚未完整還原所有 owner、ACL、default privileges、sequence dependencies、view options、managed schema customizations。
- table SQL 的 FK dependency ordering 尚未驗證，不能直接執行。

因此此項目目前只能標示「catalog 盤點已建立；正式完整 snapshot 待 CLI pull」。

## 5. 下一階段的安全門檻

1. 使用者在本機可控環境取得 Supabase CLI，執行 version/help 確認。
2. 使用官方 remote schema pull 產生 baseline，不匯出資料。
3. 在空白本機資料庫 reset，確認可重建。
4. 以 authenticated 與 anon 的實際 JWT 做權限測試：private table 不可直接由 Data API 存取；public invoker RPC 可按預期執行；非管理員不能管理；管理員可管理。
5. 完成以上後才決定 migration history repair 對照表與正式維護 migration。

## 6. 安全紀錄

本輪沒有執行 DDL/DML、migration repair、db push、db reset；沒有建立 private schema、table、role、function；沒有修改正式 Supabase；沒有部署 Edge Function；沒有建立 Supabase branch/project 或付費資源；沒有輸出 secrets。
