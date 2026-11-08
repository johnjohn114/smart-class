> **設計更新（2026-11-08）**：原先的資料庫連線模型已由 [maintenance-connection-architecture-v0.4.md](../maintenance-connection-architecture-v0.4.md) 統一為「使用者 JWT + public SECURITY INVOKER RPC + private schema + RLS」。舊草案中的 service_role／直接連線假設不得作為正式 SQL 依據。現有草案仍是不可部署的早期參考稿，必須依 v0.4 重新審查後才可使用。

# SQL 準備紀錄 v0.1

## 目前產物
- `docs/sql-drafts/maintenance-schema-draft-v0.1.sql`
- 對應設計：`docs/maintenance-database-design-v0.3.md`

## 本輪處理
先建立五張維護資料表的 DDL 草案、七個 scope seed、必要索引、RLS、拒絕 anon/authenticated/service_role 直接存取，以及 audit log 的 UPDATE／DELETE／TRUNCATE 阻擋觸發器。

## 刻意未處理
這份 SQL 不是可部署 migration。以下項目仍須完成：
1. 明確決定 Edge Function 的資料庫連線身分與最小權限。v0.3 文件提到伺服器端 `SUPABASE_DB_URL`，但若連線實際使用資料庫 owner／postgres，RLS 不會構成該連線的隔離邊界；不可把高權限連線字串交給前端。
2. 以受控交易函式落實全站／局部事件 scope 一致性、排程衝突鎖、版本檢查、idempotency、event + audit 原子寫入。
3. 確認管理員驗證可透過已驗證 JWT 呼叫既有 `public.is_admin()`，並確保 audit actor_id 由伺服器端驗證結果取得。
4. 在隔離的本地／測試資料庫實際執行與驗證 SQL，再由 Supabase CLI 產生正式 migration 檔。

## 重要限制
- 沒有執行 SQL。
- 沒有修改 Supabase 正式資料庫。
- 沒有部署 Edge Functions。
- 沒有建立 Supabase Branch 或其他可能產生費用的資源。
- 目前執行環境沒有安裝 Supabase CLI，因此尚未使用 `supabase migration new` 建立正式 migration。此檔先放在 docs/sql-drafts，避免誤認為可直接套用的 migration。
