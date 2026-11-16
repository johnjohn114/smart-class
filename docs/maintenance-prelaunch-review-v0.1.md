# Maintenance System 上線前全面審核 v0.1

> 日期：2026-11-16  
> 審核分支：`feature/maintenance-system`  
> 審核基準 commit：`4f581437f06ba24f6ee755d66dd267cc14169a46`  
> GitHub Actions：`43890950642`（Deno、isolated PostgreSQL、GoTrue/PostgREST 三項皆成功）  
> 範圍：功能分支原始碼、SQL 草案、API 規格、CI 測試與既有唯讀 Supabase 審查文件。  
> 本審核沒有連線修改正式 Supabase，沒有執行 Migration、部署、合併或付費資源操作。

## 1. 已確認通過項目

- 五支 Edge Function 的入口分別使用預期 HTTP method；四支管理 API 要求登入，公開 status 使用 optional bearer token。
- 管理 RPC 在資料庫端檢查 `auth.uid() IS NOT NULL AND public.is_admin()`；actor 由 `auth.uid()` 取得。
- SQL 草案五個 RPC 均為 `SECURITY INVOKER`，設定空的 `search_path`，並使用完整限定物件名稱。
- 六張 private tables 全部啟用 RLS；匿名角色沒有管理 RPC EXECUTE，也沒有 private table 寫入 grant。
- `internal_note` 獨立存放於 `private.maintenance_event_private_notes`；公開 status RPC 使用明確欄位白名單。
- SQL 草案未使用 `service_role`，亦未把 private schema 加入 PostgREST schema 清單；CI 的 PostgREST 設定只暴露 `public`。
- Create/update/action 的冪等性改為伺服器端 SHA-256；建立與修改的雜湊會正規化文字、scope 順序及時間表示。internal note 寫入值亦與正規化結果一致。
- CI 已測試 create 的等價輸入重播、同 key 不同內容拒絕；GoTrue/PostgREST 測試亦覆蓋 update 重播、key reuse、version conflict、schedule、cancel 與 action 重播。
- 最新 Actions run `43890950642` 三項工作全部成功。

## 2. 尚未通過正式上線門檻的項目

以下是待完成事項，不代表已發現正式環境遭入侵或已發生資料外洩。

### 高優先：正式環境尚未驗收

- 正式 Supabase 目前沒有 private schema、六張維護資料表、五個 RPC 或五支已部署 Edge Functions。
- 正式 Data API Exposed schemas 的實際設定仍需在部署前確認，確保 `private` 不在 exposed schemas。
- Migration baseline/history 尚未完成釐清；不可直接把現有 SQL 草案放進 migrations 後對正式環境執行。
- 真實正式環境的 Edge Function secrets、CORS allowlist、Gateway 設定與部署後 smoke test 尚未驗證。

### 高優先：權限邊界需在發布前再確認

- SECURITY INVOKER 必須取得實際 table grants 才能執行寫入；目前 authenticated admin 的部分 table grants 包含 event insert/update、scope link insert/delete、private note insert/update。private schema 不暴露於 Data API 是重要邊界，但這不等於資料庫權限層能證明「只能透過 RPC 寫入」。
- Audit log 已限制一般 UPDATE/DELETE，並以 trigger 阻止 row mutation/TRUNCATE；但 authenticated admin 仍有 audit INSERT 權限。規格已記載這個限制，不能把 audit 宣稱為資料庫層完全不可偽造。
- 上線前需確認產品接受上述 SECURITY INVOKER 權限模型；若要求更強的 DB 層「RPC-only」或 audit 防竄改保證，必須另行設計及隔離測試，不可臨時改成 SECURITY DEFINER。

### 中優先：產品與維運決策未定

- API 規格列有 `429 RATE_LIMITED`，但目前 Edge Function 程式碼未實作應用層 rate limiting。需決定是否依賴既有平台限制，或另設不需付費的限流方案；在未決定前不可宣稱已具備 API rate limit。
- Audit 與 idempotency 保留期限及清理方式尚未定稿；目前不應假設使用 pg_cron。
- 七個 scope code 仍需產品端最後核對。
- Status API 目前只回傳正在生效的維護事件；是否要顯示未來排程尚待確認。
- 已開始事件的欄位限制目前採保守策略；若要延長或提前結束，需另訂 action 規格。

## 3. 建議補強的隔離測試

現有 CI 已成功，但以下案例仍值得補齊後才進入正式 migration 核准：

1. anon 對四個管理 RPC（list/create/update/action）逐一確認拒絕。
2. authenticated 非管理員對 create/update/action 逐一確認拒絕。
3. 嘗試傳入偽造 actor/user/role 欄位，確認 SQL 白名單拒絕且 audit actor 不受影響。
4. 局部 scope 交集、`site_core` 與其他局部 scope、global/local 重疊的併發衝突測試。
5. `complete` 只能在事件結束時間後執行；未到期時拒絕。
6. update 的等價時間格式/文字正規化重播案例。

## 4. Supabase 近期相容性備註

Supabase 2026-04-28 公告：新建 public schema tables 不再自動暴露於 Data API，並於 2026-10-30 對所有專案強制執行。此維護設計使用 private schema，仍須明確確認 Data API schema allowlist；不能把「未自動暴露」當成 grants/RLS 的替代品。  
Supabase CLI v3（2026-11-04）改為預設 local-first 並在 hosted 變更前確認；本專案目前沒有用 CLI 對 hosted project 執行變更，本審核也沒有執行 CLI migration。

## 5. 結論

**功能分支 CI：通過。正式發布核准：尚未通過。**

目前可繼續完成測試補強、產品決策及 migration baseline 審核；在正式環境 schema、權限、設定與部署後驗收未完成前，不應執行正式 Migration 或部署。

本文件僅記錄審核結果，不授權修改正式 Supabase。
