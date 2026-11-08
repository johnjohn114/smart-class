# 維護系統 SQL 生成前審查報告 v0.1

> 審查日期：2026-11-08
> 範圍：Supabase 專案唯讀資料、GitHub migration 目錄、既有 Edge Function、管理員驗證函式、Supabase 官方文件。
> 本輪未執行 DDL／DML、未建立 schema／role／function、未部署 Edge Function。

## 1. 結論

**目前不建議生成可直接部署的正式 Migration。**

原因不是維護資料表設計不可行，而是資料庫 migration 歷史尚未建立／無法對應，且現有執行身分模型必須先固定。若現在新增正式 migration，未來 CLI 部署、回滾或重建環境可能與目前資料庫狀態不一致。

## 2. 已核實的資料庫事實

### 2.1 現有結構

- PostgreSQL 版本：17.6。
- public.profiles 存在，欄位包含 id、role、nickname、member_no、growth_points、growth_level。
- public.is_admin() 存在，為 SECURITY DEFINER，設定 search_path=''；anon 無 EXECUTE，authenticated 有 EXECUTE。
- public.is_admin_user() 也存在，但設定 search_path=public，且 anon 與 authenticated 都有 EXECUTE。新維護功能不得採用此函式。
- private schema 不存在。
- 五張 maintenance 資料表都不存在。
- 未發現專用於此應用維護功能的自訂資料庫角色。
- service_role 的 rolbypassrls=true；postgres 也具 BYPASSRLS。不能把這些高權限連線當作受 RLS 限制的普通應用角色。
- 已部署 6 個 Edge Functions；既有 manage-visitors 使用 SUPABASE_SERVICE_ROLE_KEY，並以 ADMIN_EMAIL 比對信箱。這只是舊功能現況，不應複製為維護系統授權模式。

### 2.2 管理員驗證建議

新維護功能以已驗證的使用者 JWT 為授權上下文：
1. Edge Function 保持 verify_jwt=true。
2. 由 auth.getUser() 驗證請求使用者。
3. 以同一使用者 JWT 呼叫資料庫端管理操作。
4. 資料庫函式在交易內呼叫 public.is_admin()；actor id 由 JWT 的 auth.uid() 決定。
5. 不接受 body 的 actor id、role、email 作為授權依據。
6. 不用 service-role client 代表使用者呼叫需要 auth.uid() 的管理 RPC，因 service-role 請求不會保留一般使用者的 JWT 身分。

## 3. Migration 歷史重大差異

### 3.1 Supabase 目前回報

- Supabase list_migrations 回傳空集合。
- 唯讀檢查確認 supabase_migrations.schema_migrations 不存在。
- 因此目前不能把 Supabase migration history 當作已同步、可直接往後追加的正式版本紀錄。

### 3.2 GitHub repository 現況

feature/maintenance-system 的 supabase/migrations/ 有 3 個檔案：
- 202610310001_app_releases.sql
- 20261031_app_releases.sql
- 26.11.3_calendar_fields.sql

其中兩個 app releases 檔案定義不同：
- 202610310001_app_releases.sql 定義 published_at、created_by，沒有 is_latest。
- 20261031_app_releases.sql 定義 is_latest、apk_url HTTPS constraint，沒有 created_by，並建立依賴 is_latest 的索引。

正式資料庫目前 public.app_releases 欄位包含 published_at、created_by，沒有 is_latest，與第一個檔案的表格形狀相符。public.announcements 也已包含 calendar 欄位。

### 3.3 處理方式

正式 migration 生成前必須先決定 migration 基線：
- 將現有資料庫結構視為 baseline；
- 盤點 repository SQL 與實際 schema 差異；
- 明確處理重複／衝突的 app_releases 腳本；
- 再決定 CLI migration history 如何初始化／標記既有狀態。

不可直接重跑舊 SQL，也不可只因 Supabase migration list 為空就假設資料庫是空的。這一輪沒有執行 migration repair 或任何 migration。

## 4. 執行身分與 schema 設計

### 4.1 不採用的方案

不建議讓新 Edge Functions 以 service-role key 直接 CRUD private tables。service_role 具 BYPASSRLS，即使表啟用 RLS，也不能把 RLS 當成該連線的隔離邊界。

也不建議在未確認連線字串、角色權限、pooler 模式與 secret 管理前，直接引入新的 SUPABASE_DB_URL／專用登入角色。這可能需要額外 secret 設定與角色維運，且目前沒有證據證明專用角色已存在。

### 4.2 建議的第一版架構

採用「private tables + public RPC gateway + 使用者 JWT」：
- 五張資料表建立在 private schema，不加入 Data API Exposed schemas。
- private tables 不授權 anon／authenticated 直接存取。
- 在 public 建立少量、固定簽章的 RPC gateway；這些函式採 SECURITY DEFINER，SET search_path=''，所有物件使用完整 schema 名稱。
- 寫入 RPC 只授權 authenticated EXECUTE，函式內必須檢查 public.is_admin()。
- 公開狀態 RPC 若需匿名使用，只回傳明確白名單欄位，不能包含 internal_note、actor、audit、idempotency 等資料。
- Edge Function 使用使用者 JWT 呼叫 RPC，不用 service-role 代替使用者。
- 對每個 gateway 函式撤銷 PUBLIC EXECUTE，明確授權必要角色。
- SECURITY DEFINER RPC 會被 Advisor 視為需要人工檢查的項目；這是刻意設計的權限邊界，不可因此省略函式內授權、固定 search_path、最小化回傳與測試。

此方案沿用現有 public.is_admin()，不要求新增付費 Supabase project/branch，也不要求新增資料庫登入角色。仍需驗證 Data API 是否只暴露 public；目前 SQL 工具無法讀取 Dashboard API Exposed schemas 設定，必須在 Dashboard 人工確認或用受控測試驗證。

官方文件參考：
- Supabase Custom Schemas：https://supabase.com/docs/guides/api/using-custom-schemas
- Supabase Securing your data：https://supabase.com/docs/guides/database/secure-data

## 5. 早期 SQL 草案必須修正的地方

docs/sql-drafts/maintenance-schema-draft-v0.1.sql 不可直接轉成正式 migration，後續正式版至少要修正／補齊：

1. schema 權限：private 不暴露；確認 schema owner、USAGE、default privileges 與函式 owner。
2. RPC gateway：補上 public RPC 的明確簽章、回傳型別、EXECUTE grants/revokes 和管理員檢查。
3. 交易：寫入 event、scope links、audit、idempotency response 必須同一交易。
4. Idempotency：以唯一鍵原子 claim（例如 INSERT ... ON CONFLICT 流程）處理併發，不能只先 SELECT 再 INSERT。
5. 排程衝突：單一 transaction-scoped advisory lock 可作為第一版簡化方案；所有可能改變排程占用的操作必須遵循同一把鎖。
6. 狀態與欄位白名單：凍結 scheduled 事件可否修改 title/message/internal_note；取消／完成後的重複 action 行為；明確禁止復活歷史事件。
7. 稽核：actor 由 JWT 決定；before/after snapshot 移除 secrets 與不必要個資。append-only trigger 只防一般 DML，不等於資料庫 owner／superuser 無法竄改。
8. 私有 schema 未暴露：不能只靠 REVOKE 取代 Dashboard Exposed schemas 設定。
9. 早期草案的 service_role revoke/grant 必須與 RPC gateway 模型一致，不可產生「Edge Function 無權呼叫」或「service_role 直接讀寫資料表」的錯誤配置。

## 6. Supabase Advisor 基線

本輪 security Advisor 回報：
- 2 個 INFO：member_no_counter、visitor_profiles 啟用 RLS 但沒有 policy。
- 1 個 ERROR：public.activity_member_stats 是 security definer view。
- 34 個 WARN：SECURITY DEFINER functions 可由 anon/authenticated 執行。
- 1 個 WARN：Auth leaked password protection 未啟用。

這些是目前專案既有基線，不是本次維護 SQL 新增造成；本輪沒有修改。新維護 RPC 必須獨立完成最小權限審查，不應把既有 Advisor 數量誤報為維護系統的新增問題。

## 7. 仍需關閉的阻擋項目

| 項目 | 狀態 |
|---|---|
| 七個 scope、全站維護與管理員後台規則 | 已確認 |
| 目前資料表／欄位盤點 | 已唯讀確認 |
| 現有 is_admin() 權限 | 已唯讀確認 |
| private schema 不存在 | 已唯讀確認 |
| migration history 缺失／不同步 | 已確認，需先定 baseline |
| repository app_releases migration 衝突 | 已確認，需處理 |
| Data API Exposed schemas 設定 | 尚未驗證 |
| 事件狀態轉換與已排程事件文字欄位可編輯範圍 | 尚待產品規則定稿 |
| public RPC gateway 簽章與授權 | 本報告提出建議，尚未實作 |
| SQL 本地／隔離環境實際測試 | 尚未執行 |
| 正式 Migration SQL | 尚未生成 |

## 8. 本輪執行紀錄

- Supabase 所有查詢均為唯讀 SELECT／metadata 查詢。
- GitHub 只讀取 repository 內容；本報告另存於功能分支。
- 沒有執行 SQL DDL/DML。
- 沒有新增 schema、table、role、function 或 migration history。
- 沒有建立 Supabase branch/project。
- 沒有部署 Edge Function。
- 沒有讀取或輸出任何 secret 值。
- Organization plan metadata 顯示目前為 Free；本輪沒有新增會產生費用的資源。

## 9. 最終判定

**SQL 生成狀態：BLOCKED（暫停正式生成）。**

下一步先建立 migration baseline 整理方案，並完成 Dashboard Exposed schemas 核對及狀態規則定稿。完成後再生成可供本地測試的 Migration SQL；通過隔離測試後才考慮正式套用。
