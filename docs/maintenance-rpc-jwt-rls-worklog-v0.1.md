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

對 SQL 草案做了結構性檢查，以下 9 項符合預期：

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

另以靜態 checker 的測試案例驗證 5 種 guardrail 情境，5/5 通過。這是 checker 邏輯測試，不等同於已在 repository 環境執行整套 Python 測試。

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

## 5. 下一步

1. 對 SQL 草案進行 PostgreSQL parser 檢查，修正所有語法錯誤。
2. 執行 Python 靜態 checker 與其 unit tests。
3. 執行既有 Deno Edge validation tests，修正 API/SQL 欄位契約差異。
4. 在不連接正式 Supabase 的前提下，準備 anon / non-admin / admin JWT 的隔離測試方案；若沒有現成免費隔離環境，明確保留為 NOT RUN，不建立付費資源。
