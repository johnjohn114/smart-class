# Maintenance RPC + JWT/RLS 整合工作紀錄 v0.1

> 日期：2026-11-08  
> 分支：`feature/maintenance-system`  
> 架構方向：使用者已選定 B（五表 private + user JWT + SECURITY INVOKER）。  
> 狀態：開發草案已提交；未進入正式資料庫。

## 1. 本輪已完成

- 使用者選定方向 B，並更新架構決策文件。
- 修正 API 規格對 Edge Functions 狀態的錯誤描述：五支原始碼已提交，尚未測試/部署。
- 建立五表 private schema + 五個 SECURITY INVOKER RPC 的 SQL 開發草案：
  `supabase/sql/maintenance-private-schema-rpc-draft-v0.1.sql`
- 建立 SQL 靜態 guardrail：
  - `scripts/verify_maintenance_sql_draft.py`
  - `tests/test_verify_maintenance_sql_draft.py`
- 建立 JWT/RLS 隔離測試計畫：
  `docs/maintenance-jwt-rls-isolated-test-plan-v0.1.md`
- 更新 RPC 契約，連結至 SQL 草案。

## 2. 已做的靜態檢查

早期結構性檢查涵蓋下列項目（實際列出 10 項）：

- 五張 private tables 均存在。
- 五個 public RPC 均存在。
- 五個 RPC 均標示 SECURITY INVOKER + 空 search_path。
- 五張資料表均啟用 RLS。
- 沒有 SECURITY DEFINER。
- 沒有授予 service_role 維護表權限。
- audit UPDATE/DELETE/TRUNCATE 防護存在。
- idempotency actor/key 唯一鍵存在。
- transaction advisory lock 存在。
- 未授予 maintenance_events DELETE。

注意：上述是先前的人工結構檢視紀錄，不代表最新 SQL 版本已通過 parser 或資料庫執行。靜態 checker 與測試 fixture 已更新以檢查管理員列表的型別、限制數量、游標格式與 cast 錯誤處理；最新版本的 Python 測試尚未執行。

## 3. 尚未執行／不能宣稱通過

| 驗證項目 | 狀態 |
|---|---|
| PostgreSQL SQL parser | NOT RUN |
| Python repository test command | NOT RUN |
| Deno Edge validation tests | NOT RUN |
| anon / non-admin / admin 真實 JWT | NOT RUN |
| PostgREST + RLS 隔離測試 | NOT RUN |
| 併發、rollback、idempotency DB 測試 | NOT RUN |
| 完整 PostgreSQL restore test | 依先前決定跳過 |
| 正式 Supabase DDL/DML / migration | 未執行 |
| Edge Function deployment | 未執行 |

目前執行環境沒有可用的 Deno CLI，也沒有安裝 pglast；未因此安裝額外工具或建立付費資源。

## 4. 草案中的重要安全限制

- private schema 必須排除在 Supabase Data API Exposed schemas 之外。
- SECURITY INVOKER admin-list 需要 authenticated 取得事件欄位 SELECT 權限；RLS 是 row-level，不能在同一 role 下按欄位隱藏 internal_note。因此不暴露 private schema 是必要邊界，公開 status RPC 只回傳欄位白名單。
- status RPC 的 anon 路徑、管理員 helper ACL、RLS/grants 組合仍須在隔離環境驗證。
- SQL 草案不是 migration，不可對正式 Supabase 執行。
- 五表 schema 的 scope seed、保留期限與產品欄位仍需最後審查。

## 5. 2026-11-08 後續修正

- 管理員列表 RPC 的 limit 改為安全預設值，先驗證 JSON 型別與 1–100 範圍，再進行轉換。
- 管理員列表的 status、scope、is_global、from、to、cursor 加入型別／空值檢查；游標檢查分隔符形狀。
- status RPC 拒絕 null、非字串或空白 scope。
- create/update/action/list RPC 對常見格式轉換錯誤統一回傳 VALIDATION_ERROR，避免把無效輸入當成未處理資料庫錯誤。
- SQL 靜態 checker 與 fixture tests 已同步增加這些 guardrails。

以上仍屬程式碼層級修正，尚未執行 PostgreSQL parser、Python tests 或資料庫測試。

## 6. 下一步

1. 使用單一本機驗證流程執行 Python tests、靜態 checker、可用時的 pglast parser，以及 Deno validation tests。
2. 若 parser 或測試失敗，先修正分支中的程式碼，再重跑。
3. 在不連接正式 Supabase 的前提下，準備 anon / non-admin / admin JWT 的隔離測試方案；若沒有現成免費隔離環境，明確保留為 NOT RUN，不建立付費資源。
