# Schema Snapshot 套件索引 v0.1

> 專案：fsoowongtavlsrwvzbze
> 日期：2026-11-08
> 分支：feature/maintenance-system

## 重要限制

以下檔案是使用 PostgreSQL catalog 唯讀查詢重建的 public schema 參考資料，**不是 Supabase CLI db pull，也不是 pg_dump --schema-only 的完整、可直接還原 dump**。不可以直接拿來重建正式資料庫或視為完整 baseline migration。

目前執行環境沒有 supabase CLI、psql、pg_dump。為避免誤導，所有檔案均標註重建範圍與限制。

## 檔案清單

| 檔案 | 收錄內容 | 限制 |
|---|---|---|
| 20261108-public-tables-policies.sql | public tables、欄位、constraints、RLS enablement、indexes、policies、table grants | 表格排序未必符合 FK 依賴順序；未完整重建所有 sequence owner/default ACL；不是可直接執行的 migration |
| 20261108-public-views.sql | public view definitions | view options（例如 security_invoker）、owner、grants 需另核 |
| 20261108-public-functions.sql | public functions/procedures definitions | owner、ACL、comment、依賴順序與 extension-owned routines 需另核 |
| 20261108-public-triggers.sql | public triggers definitions | trigger function 需先存在；觸發器啟用狀態與依賴需再核 |
| 20261108-public-types-sequences.sql | enum types 與 sequence inventory | sequence current values、owner、ownership dependencies、完整參數需 pg_dump |
| 20261108-public-acl-inventory.json | schema、function、relation owner 與 ACL inventory | 是 metadata 記錄，不是可直接執行的 GRANT 腳本 |

## Snapshot 統計基線

- PostgreSQL 17.6。
- public relations 45（44 tables + 1 view）。
- public columns 420。
- public RLS policies 98。
- public triggers 9。
- public functions 38。
- private schema 不存在。
- Supabase migration list 空集合；supabase_migrations.schema_migrations 不存在。

## 尚未納入的必要項目

- Supabase CLI 正式 remote schema pull／pg_dump schema-only。
- public table constraints / index / grants 與實際重建的完整 dependency ordering。
- views 的 security_invoker options、owner、ACL。
- function owner、ACL、search_path、volatility、parallel settings 的可還原 DDL。
- trigger enable/disable 狀態、trigger function 依賴。
- sequence 完整設定、owned-by 關係及目前值。
- schema、default privileges、role memberships、column-level grants。
- auth/storage 等 Supabase managed schemas 中的專案自訂 objects。
- Dashboard Data API Exposed schemas 設定。

## 正確用途

目前套件只供人工檢查差異、找出 migration 漂移、設計維護系統時參照。要建立正式 baseline，仍須在有 Supabase CLI 的受控本機環境執行官方 remote schema pull，review 後在空白本機 DB reset 驗證。
