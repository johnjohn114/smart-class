# Maintenance System 架構基準決策 v0.1

> 日期：2026-11-15
> 分支：`feature/maintenance-system`
> 性質：依網站正常運作、安全與不增加付費服務為優先的設計基準；只記錄架構選擇，不代表已部署或已通過整合測試。

## 1. 決策

採用目前分支已實作並由 API v0.5 契約描述的六表架構，作為後續維護系統唯一的目標資料模型：

1. `private.maintenance_scopes` — 全域 scope catalog。
2. `private.maintenance_events` — 維護事件。
3. `private.maintenance_event_private_notes` — 管理員內部備註。
4. `private.maintenance_event_scopes` — 事件與 scope 關聯。
5. `private.maintenance_audit_logs` — 操作稽核。
6. `private.maintenance_idempotency` — 寫入冪等記錄。

存取架構採 Edge Functions + 原始使用者 JWT + public SECURITY INVOKER RPC + private schema tables + RLS。維護管理操作必須在資料庫端檢查 `auth.uid() IS NOT NULL AND public.is_admin()`。不以 service_role 代表使用者執行管理 RPC。

`site_core` 是跨頁面的共用核心維護範圍：前端每個頁面都會同時查詢 `site_core` 與頁面專屬 scope，因此 `site_core` 必須與任何其他局部 scope 的重疊時段互斥。SQL 草案的 create、update、schedule 三條寫入路徑都需維持此規則。

## 2. 舊四表 SQL 的處理

舊版 `public.maintenance_state`、`public.maintenance_events`、`public.maintenance_scopes`、`public.maintenance_audit_logs` 是不同資料模型，含 singleton global state、每事件 scope rows 及 service_role 存取方向。

舊 SQL 不執行、不與新版混用，也不直接轉成 migration。保留其歷史紀錄；如未來需要其中的功能（例如 emergency mode、background_path、announcement link），必須先確認產品需求，再以新架構重新設計，不可直接把舊欄位塞入新版 schema。

## 3. 目前程式／文件基準

- API 規格：`docs/maintenance-api-spec-v0.4.md`（文件內文標示整合規格 v0.5）。
- 連線架構：`docs/maintenance-connection-architecture-v0.4.md`。
- RPC 呼叫契約：`docs/maintenance-rpc-sql-contract-v0.1.md`。
- SQL 草案：`supabase/sql/maintenance-private-schema-rpc-draft-v0.1.sql`。
- Edge Functions：`maintenance-status`、`maintenance-admin-list`、`maintenance-event-create`、`maintenance-event-update`、`maintenance-event-action`。

SQL 草案目前包含六張 private tables、五個 public RPC。SQL 仍是未驗證草案，不可當作正式 migration。

## 4. 安全與上線限制

- private schema 不加入 Supabase Data API Exposed schemas；此設定尚未由本次 GitHub 靜態檢查確認。
- SECURITY INVOKER 所需的最小 schema/table grants 與 RLS 必須成套檢查；不得一面撤銷所有必要 table grants，一面期待 invoker RPC 能讀寫。
- 不可宣稱 grants/RLS 能辨識 SQL 是從 RPC 內部還是其他資料庫路徑發出。
- 需以 anon、一般 authenticated、admin 的真實 JWT 在隔離環境驗證 RPC、RLS、PostgREST、交易、排程併發、version conflict、idempotency。
- 正式 Supabase migration history 仍未建立／未完成基線整理；不得直接執行 maintenance SQL。
- 不部署 Edge Functions、不修改正式 Supabase、不建立付費資源，除非使用者日後另行明確授權。
- 完整 PostgreSQL restore test 依既有專案決策跳過，不能標示通過。

## 5. 下一步順序

1. 統一其餘文件中「五表／六表」、`scope_id`／`scope_code`、舊連線模型等過時敘述。
2. 靜態核對六表 SQL 草案與五支 Edge Functions 的欄位、參數、回應契約。
3. 在可用的免費本機工具範圍內完成靜態檢查與單元測試；如環境缺少 PostgreSQL/Deno/Supabase CLI，明確標示未測，不以正式資料庫試錯。
4. 完成 migration baseline 與隔離 JWT/RLS 測試前，不核准正式 migration 或部署。

## 6. 本決策的範圍

本決策只統一目標架構，不宣稱網站已整合完成、資料庫已建立、測試已通過或功能已上線。
