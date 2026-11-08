# Maintenance JWT / RLS 隔離整合測試計畫 v0.1

> 狀態：測試案例已整理；尚未建立隔離環境、尚未執行。  
> 測試目標：五表 private schema + user JWT + SECURITY INVOKER RPC。  
> 禁止：不得使用正式 Supabase project 執行測試，不建立付費 branch/project。

## 1. 測試環境前提

隔離環境必須具備：
- PostgreSQL / Supabase Auth / PostgREST 與正式環境相容的版本。
- 專用測試資料庫，與正式 project 完全分離。
- 一個 anon request context。
- 一個 authenticated 非管理員測試帳號。
- 一個 authenticated 管理員測試帳號。
- 可在隔離環境套用 SQL draft、重建資料及清除測試資料。

不得把 service_role 測試結果當成 user JWT/RLS 測試結果。測試帳號與 JWT 不可提交到 GitHub，也不可貼入對話。

## 2. 身分與 RPC ACL

| 測試 | 預期 |
|---|---|
| anon 呼叫 maintenance_status_public | 成功，只回公開欄位 |
| anon 呼叫 admin_list/create/update/action | 42501 / FORBIDDEN |
| 無 JWT 呼叫 status | 成功，視為 anon |
| 無 JWT 呼叫管理 RPC | 拒絕 |
| 無效/過期 JWT 呼叫管理 Edge Function | 401 |
| authenticated 非管理員呼叫管理 RPC | 403 |
| authenticated 管理員以原始 user JWT 呼叫管理 RPC | 依操作規則成功 |
| 偽造 actor_id / role / is_admin 欄位 | 不得改變授權；未知欄位拒絕 |
| audit admin_id | 必須等於 auth.uid() |

## 3. RLS 與資料揭露

- anon 只能讀取當前生效事件所需的安全欄位。
- anon 無法讀取 internal_note、audit logs、idempotency records。
- authenticated 非管理員無法列出管理事件或讀取 audit/idempotency。
- authenticated 非管理員只能透過公開 status RPC 取得公開維護狀態。
- authenticated 管理員可透過管理 RPC 讀取管理欄位。
- anon / 非管理員不得 INSERT、UPDATE、DELETE 或 TRUNCATE 任一維護資料表。
- authenticated 管理員不得 UPDATE/DELETE/TRUNCATE audit logs。
- 確認 private schema 未加入 Data API Exposed schemas；確認直接 REST table endpoints 不可用。
- 確認五個 RPC 均為 SECURITY INVOKER、空 search_path，且 EXECUTE ACL 僅符合規格。

重要限制：管理 RPC 需要 authenticated SELECT 權限讀取 event 欄位，而 RLS 是 row-level，不是 column-level。故 private schema 不暴露於 Data API 是必要邊界；status RPC 只回傳白名單欄位。此限制必須在隔離環境驗證並記錄。

## 4. 業務規則與交易

- global event 的 scope_codes 必須為空。
- local event 至少一個 enabled scope。
- disabled/unknown scope 拒絕。
- starts_at 必須早於 ends_at。
- draft 不佔排程；scheduled 事件依半開區間檢查衝突。
- global/global、global/local 重疊拒絕；local/local 僅同 scope 重疊拒絕。
- update 必須合併 patch 與資料庫現值後驗證最終狀態。
- 已開始事件不得一般修改時間或 scope。
- schedule 只允許 draft → scheduled；cancel 只允許 draft/scheduled；complete 只允許到期 scheduled。
- expected_version 不符回 VERSION_CONFLICT。
- 同 actor + key + 同 payload 重送回傳原結果。
- 同 actor + key + 不同 payload 回 IDEMPOTENCY_KEY_REUSED。
- 兩個併發寫入不得建立互相衝突的 scheduled events。
- 寫入任一階段失敗，event/scope/audit/idempotency 必須全部 rollback。
- audit before_data / after_data 必須分別反映操作前與操作後狀態。

## 5. 驗收分層

1. Python 靜態 guardrail：只檢查 SQL 文字結構。
2. PostgreSQL parser：確認 SQL 語法可解析。
3. Deno tests：確認 Edge request validators。
4. 隔離環境整合測試：真實 anon / non-admin / admin JWT、PostgREST、RLS、併發與 rollback。
5. 正式部署前審查：只在以上必要測試全部通過、使用者另行明確授權後進行。

目前第 1 層的 checker 已提交；第 2–4 層尚未執行。完整 schema restore test 依專案決定跳過，不列為 PASS。
