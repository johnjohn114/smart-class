# Maintenance RPC SQL 契約 v0.1

> 狀態：Edge Function 呼叫端契約；對應 SQL function 草案已建立於 `supabase/sql/maintenance-private-schema-rpc-draft-v0.1.sql`，但尚未完成 PostgreSQL parser、資料庫整合測試或 migration。

## 1. 呼叫參數

五個 RPC 必須提供同一個單一參數：

- 名稱：`p_request`
- 型別：`jsonb`
- 呼叫方式：PostgREST RPC JSON body `{ "p_request": <validated request object> }`

Edge Functions 會呼叫：

- `public.maintenance_status_public(p_request jsonb)`
- `public.maintenance_admin_list(p_request jsonb)`
- `public.maintenance_event_create(p_request jsonb)`
- `public.maintenance_event_update(p_request jsonb)`
- `public.maintenance_event_action(p_request jsonb)`

SQL 草案目前已提供五個 RPC 的 function body、private tables、RLS、最小必要 table grants 與 EXECUTE ACL；各 RPC 均宣告 SECURITY INVOKER、固定空 search_path，並使用完整限定物件名稱。這些內容仍是未驗證的開發草案，不代表可直接套用或已通過 PostgreSQL、PostgREST、JWT/RLS 測試。若後續 schema、欄位、policy 或權限設計變更，必須同步更新 SQL 草案與本契約。

## 2. 身分上下文

Edge Function 對管理 RPC 轉送原始使用者 bearer token；RPC 內部必須檢查 `auth.uid() IS NOT NULL AND public.is_admin()`。actor 必須由 `auth.uid()` 取得，不讀取 request 中的 actor/user ID。

公開 status RPC 允許 anon，僅可讀取公開欄位。可選 bearer token 若有效則保留使用者上下文；無效或缺少 token 時按匿名讀取處理，絕不因此取得 bypass 權限。

## 3. 回傳格式

建議 RPC 回傳 JSONB object，讓 Edge Function 包裝成：

```json
{ "ok": true, "data": {} }
```

若 RPC 已回傳含 `ok` 欄位的標準 envelope，Edge Function 會原樣回傳，不重複包裝。

## 4. 錯誤映射

RPC 可使用 SQLSTATE/受控錯誤訊息供 Edge Function 對應：
- `42501` → 403 FORBIDDEN
- `P0002` → 404 NOT_FOUND
- `22023` → 422 VALIDATION_ERROR
- `23505` 或受控 CONFLICT → 409 CONFLICT
- 受控 `VERSION_CONFLICT` → 409 VERSION_CONFLICT
- 受控 `IDEMPOTENCY_KEY_REUSED` → 409 IDEMPOTENCY_KEY_REUSED

不得把 SQL、schema、table、stack trace 或敏感授權細節放進使用者可見錯誤。

## 5. 重要限制

目前 API 規格未提供實際五個 RPC 的 SQL signature；本契約是為了讓 Edge Function 呼叫介面明確化而新增的開發決策。實作 SQL 前必須逐項確認與最終 schema 一致，並在隔離環境測試 JWT、RLS、transaction、concurrency 與 idempotency。不得在正式 Supabase 以試錯方式補齊。
