# Maintenance SQL draft 靜態檢查工具 v0.1

本工具只檢查 SQL 草案的結構性安全條件，不會連線資料庫，也不是 PostgreSQL 語法解析器。

## 執行方式

從 repository root 執行：

```bash
python scripts/verify_maintenance_sql_draft.py
python -m unittest discover -s tests -p 'test_verify_maintenance_sql_draft.py' -v
```

## 檢查內容

- 五張 private tables 是否存在於草案。
- 五張資料表是否都啟用 RLS。
- 五個 public RPC 是否存在，且明確為 SECURITY INVOKER + 空 search_path。
- 不授予 service_role 維護表權限。
- 不出現 SECURITY DEFINER。
- audit UPDATE/DELETE/TRUNCATE 防護存在。
- idempotency actor/key 唯一鍵及 transaction advisory lock 存在。
- 不授予 maintenance_events DELETE。

## 限制

PASS 只代表靜態文字檢查符合規則，不代表 SQL 可成功解析或執行，也不代表 RLS/JWT 權限測試通過。SQL parser、Deno tests、真實 anon/user/admin JWT + PostgREST + RLS 隔離測試仍須分開驗收。不得使用正式 Supabase 作為測試環境。
