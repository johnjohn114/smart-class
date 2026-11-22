# Maintenance System API 規格 v0.7

> 日期：2026-11-17；狀態更新：2026-11-22
> 分支：`feature/maintenance-single-pass-migration-20261122`
> 狀態：整合規格 v0.7；PR #34 仍為 Draft、尚未合併。最新 commit 與 CI 結果請以 [PR #34 的 Commits / Checks](https://github.com/johnjohn114/smart-class/pull/34) 為準，避免文件中的固定編號落後於後續提交；正式 Supabase 尚未部署，合併至 `main` 仍待審核。  
> 本版承接 v0.6，定稿 v1 的錯誤碼與資料保留決策。舊版保留作為歷史紀錄。

## 1. 目標與範圍

五支 Supabase Edge Functions：
- `maintenance-status`
- `maintenance-admin-list`
- `maintenance-event-create`
- `maintenance-event-update`
- `maintenance-event-action`

對應五個 public RPC：
- `maintenance_status_public`
- `maintenance_admin_list`
- `maintenance_event_create`
- `maintenance_event_update`
- `maintenance_event_action`

五支 Edge Function 原始碼已提交，並通過 GitHub Actions 隔離環境的 Deno、GoTrue/JWT、PostgREST 與 PostgreSQL 17 測試；正式 Supabase 尚未部署。本文件定義契約，不代表 API 已在正式環境可用。資料表基準為 `maintenance_scopes`、`maintenance_events`、`maintenance_event_private_notes`、`maintenance_event_scopes`、`maintenance_audit_logs`、`maintenance_idempotency`；舊四表 `public.maintenance_state` 設計不屬於本版架構。

## 2. 已確認的產品規則

### 2.1 七個維護範圍

| 顯示名稱 | code |
|---|---|
| 網站核心 | `site_core` |
| 公告與資訊 | `announcements_info` |
| 活動與比賽 | `events_competitions` |
| 影音內容 | `video_content` |
| 會員與成長 | `membership_growth` |
| 商城與客服 | `store_support` |
| 下載與 App | `downloads_app` |

以上七個範圍名稱已確認；代碼是目前規格採用的技術識別值，需在 migration/seed 前再做最後核對。

### 2.2 全站維護與管理員

- 全站維護是獨立控制，不是第八個 scope。
- 全站事件使用 `is_global=true`，scope 關聯必須為空。
- 局部事件使用 `is_global=false`，且至少包含一個有效 scope。
- 全站維護期間，管理員仍可登入並使用管理後台。
- bypass 只控制前端維護遮罩，不略過登入、JWT 或管理員授權；不得建立公開後門。
- Auth 本身故障時不保證可登入，緊急復原另訂程序。

## 3. 共通 API 與安全規則

### 3.1 身分與權限

- 管理 Edge Functions 設定 `verify_jwt=true`，並在函式內使用 Supabase Auth 驗證呼叫者。
- Edge Function 使用原始使用者 bearer token 與 publishable/anon key 呼叫 RPC；不得使用 service_role 代表使用者執行管理 RPC。
- actor ID 一律取自資料庫端 `private.maintenance_uid()`，由 PostgREST 已驗證的 JWT subject claim 取得；不可採信前端傳入的 actor_id、user_id、role、isAdmin 或 email。
- 管理 RPC 必須在資料庫端檢查 `private.maintenance_uid() IS NOT NULL AND public.is_admin()`；新版 SQL 由專用 `pg_database_owner`（`NOLOGIN`、`NOBYPASSRLS`）擁有管理 RPC，管理 RPC 使用 `SECURITY DEFINER`，並在函式內執行上述檢查。
- `public.is_admin()` 是目前候選 helper；`public.is_admin_user()` 禁止用於此功能。
- 管理 API 的 Edge Function 驗證不能取代 RPC 內的授權檢查。

### 3.2 RPC / schema

- 採用 Edge Function + 使用者 JWT + private schema tables + RLS。公開 status RPC 使用 `SECURITY INVOKER`；管理 RPC 使用專用 `pg_database_owner` 擁有的 `SECURITY DEFINER`，並在資料庫函式內檢查使用者 JWT 對應的管理員身分。
- private schema 不加入 Data API Exposed schemas。
- `private.maintenance_uid()` 以 `SECURITY INVOKER` 讀取 PostgREST 已驗證的 `request.jwt.claims` / `request.jwt.claim.sub`；它只回傳目前請求的 JWT subject，不接受外部參數。這讓管理 RPC owner 不必取得 Supabase 管理的 `auth` schema USAGE，也不必向 `auth.uid()` 轉授權限。公開 status RPC 的匿名呼叫會得到 NULL subject；anon、authenticated 與 executor 僅取得呼叫此 helper 所需的 EXECUTE 權限。
- 所有 RPC 固定 `search_path = ''`，所有 schema/table/function 名稱完整限定。`maintenance_status_public` 使用 `SECURITY INVOKER`；`maintenance_admin_list`、`maintenance_event_create`、`maintenance_event_update`、`maintenance_event_action` 使用 `SECURITY DEFINER`，owner 為專用 `pg_database_owner`。
- 新 RPC 先撤銷 `PUBLIC` EXECUTE，再明確授權。
- 管理 RPC 的 EXECUTE 僅授予 `authenticated`；公開 status RPC 的 EXECUTE 授予 `anon`、`authenticated`。管理 RPC 由 `pg_database_owner` 執行受 RLS 約束的資料表操作。
- `authenticated` 對部分 private tables 有 SELECT table grants，但 RLS 僅允許管理員讀取管理資料；管理寫入 grants 僅授予 `pg_database_owner`。`anon` 僅有公開 status 所需的欄位 SELECT 權限。
- 不使用 service_role bypass RLS，不新增 DB URL 或資料庫密碼 secret。
- private tables 全部啟用 RLS。RLS policy 必須限制 admin；必要時同時檢查 `private.maintenance_uid() IS NOT NULL`。
- 前端只呼叫 Edge Functions；不直接操作維護資料表。
- `internal_note` 雖然仍是 create/update/admin-list API 欄位，但資料庫草案存放於獨立的 `private.maintenance_event_private_notes`，不得放在一般維護事件資料列；該表啟用 RLS。authenticated 管理員可依 RLS 讀取，直接 table write 不授予 authenticated；寫入只能經過已驗證的管理 RPC。

### 3.3 請求與回應

- JSON request/response。
- 成功：`{ "ok": true, "data": ... }`
- 錯誤：`{ "ok": false, "error": { "code": "...", "message": "..." } }`
- 時間傳輸採 ISO 8601，含時區 offset；資料庫使用 `timestamptz`；管理介面以 Asia/Taipei 顯示。
- 生效判斷只使用資料庫/伺服器時間，不信任用戶端時鐘。
- 所有輸入驗證型別、必填、長度、格式、允許值及欄位白名單；未知欄位拒絕，不得直接展開寫入。
- 不在錯誤訊息中洩漏 SQL、schema、secret、資料庫內部細節或管理員判斷邏輯。


## 3.4 RPC 呼叫參數補充（開發契約）

五支 Edge Functions 統一以單一 JSONB 參數呼叫對應 RPC：`p_request`。呼叫 body 為 `{ "p_request": <validated request object> }`。SQL signature 與回傳格式以 `docs/maintenance-rpc-sql-contract-v0.1.md` 為準。五個 RPC 已在本分支的隔離 PostgreSQL 17、GoTrue-issued JWT 與 PostgREST 測試路徑驗證；此結果不代表正式 Supabase 已建立或部署。

## 4. API 契約

### 4.1 `maintenance-status` — 公開狀態讀取

**用途：** 讀取目前生效的全站維護事件，以及呼叫端明確指定 scope 的局部維護事件。

Request：
- 可選 `scope`，必須為七個 code 之一。
- 不帶 scope 時只回傳全站維護資訊，不推測頁面所屬 scope。
- 無須 request body。

成功 data 欄位白名單：
- `is_maintenance`
- `is_global`
- `scopes`
- `title`
- `message`
- `starts_at`
- `ends_at`
- `server_time`
- `admin_bypass`（僅在提供有效 bearer token 且資料庫確認 admin 時回傳 true；只供 UI 顯示，不是授權）

不得回傳：
- `internal_note`
- actor/user IDs
- audit snapshots/logs
- idempotency keys/data
- 內部管理欄位

**權限決議：** 公開 status RPC 維持 SECURITY INVOKER。匿名角色僅取得 private schema USAGE 與讀取公開狀態所需的最小 SELECT，並由 RLS 限制只可見目前允許公開的狀態資料。private schema 不加入 Data API Exposed schemas；匿名使用者不得取得任何寫入權限。此設計已在目前 GoTrue-issued JWT + PostgREST 隔離 CI 中測試 anon、一般 authenticated 與 admin 的 status/RPC 存取；正式環境仍須重新驗證。

### 4.2 `maintenance-admin-list` — 管理員事件清單

**權限：** 有效 JWT + 資料庫端 admin check。

Request query：
- `status`（可選）
- `scope`（可選）
- `is_global`（可選）
- `from`、`to`（可選 ISO 8601）
- `limit`（預設 20；最大 100）
- `cursor`（可選，不透明游標）

Response：
- 事件清單
- scopes
- status
- version
- created_at / updated_at
- internal_note（僅 admin）
- next_cursor

排序必須穩定，例如 `created_at DESC, id DESC`；cursor 必須對應同一排序。不可讓一般登入者藉由查詢參數取得管理清單。

### 4.3 `maintenance-event-create` — 建立事件

**權限：** 有效 JWT + 資料庫端 admin check。

Request：
- `title`
- `message`
- `internal_note`（可空）
- `is_global`
- `scope_codes`
- `starts_at`
- `ends_at`
- `status`（建立時固定為 `draft`；不得直接建立 `scheduled`）
- `reason`（audit 原因）
- `idempotency_key`（UUID）

驗證：
- `starts_at < ends_at`。
- `is_global=true` 時 `scope_codes` 必須為空陣列。
- `is_global=false` 時至少一個有效且 enabled scope。
- 建立 RPC 僅允許 `draft`，不會直接建立 `scheduled`。
- 事件必須透過 `maintenance-event-action` 的 `schedule` 動作進入 `scheduled`；該動作會檢查開始時間必須晚於資料庫目前時間，並執行排程衝突檢查。
- title/message 長度及文字內容由資料模型/前端需求定稿前設定明確上限；不得無限制輸入。
- event、scope links、audit、idempotency 必須在同一 DB transaction 完成。

Response：event_id、建立後事件摘要、version。

### 4.4 `maintenance-event-update` — 修改事件

**權限：** 有效 JWT + 資料庫端 admin check。

Request：
- `event_id`
- `expected_version`
- 欲更新的白名單欄位
- `reason`
- `idempotency_key`

規則：
- expected_version 不符回傳 409 `VERSION_CONFLICT`。
- 僅允許修改 title、message、internal_note、is_global、scope_codes、starts_at、ends_at 等核准欄位；不得直接更新 status、actor、audit、version。
- 重新驗證 global/scope 關係與時間。
- 修改排程、scope 或 global 模式時重新檢查衝突。
- `cancelled`、`completed` 不可透過一般 update 重新排程；需另建新事件。
- event、scope links、audit、version 更新在同一交易完成。
- 已開始事件允許修改哪些欄位尚未由產品規則確認，故實作前須採保守限制：開始後不得一般修改排程時間或 scope；如需延長/提前結束，先走專門 action 的後續規格。

Response：更新後事件摘要及新 version。

### 4.5 `maintenance-event-action` — 事件生命週期動作

**權限：** 有效 JWT + 資料庫端 admin check。

Request：
- `event_id`
- `expected_version`
- `action`
- `reason`
- `idempotency_key`

第一版允許 action：
- `schedule`：draft → scheduled；必須重新檢查衝突。
- `cancel`：draft/scheduled → cancelled。
- `complete`：scheduled → completed；僅允許事件已到結束時間後執行，避免提早隱藏維護。

其他轉換一律拒絕並回 409。第一版不提供 `start_now`、`extend`、`end_early`。若日後需要，另訂產品規則及測試後再加入。

每個成功 action 記錄 actor、時間、reason、before/after snapshot，並更新 version。重複請求由 idempotency 機制安全回應。

## 5. 事件狀態與時間規則

狀態：
- `draft`：草稿，不對前台生效，不佔用排程。
- `scheduled`：已排程；是否目前生效由 `starts_at <= server_time < ends_at` 計算。
- `cancelled`：取消，不生效、不佔用排程。
- `completed`：完成，不生效、不佔用排程。

允許轉換：
- create → draft 或 scheduled
- draft → scheduled 或 cancelled
- scheduled → cancelled
- scheduled → completed（僅在 server_time >= ends_at）
- 其他轉換拒絕

自然到期後，status 欄位仍可維持 scheduled，但 status API 必須依時間窗停止回傳為目前生效；不依賴 pg_cron。管理員可在到期後執行 complete 封存。

時間區間採半開區間 `[starts_at, ends_at)`，重疊條件：
`existing.starts_at < requested.ends_at AND requested.starts_at < existing.ends_at`。

## 6. 排程衝突規則

只對 `scheduled` 事件進行衝突判斷：
- global/global：時間重疊即衝突。
- global/local 或 local/global：時間重疊即衝突。
- local/local：時間重疊且 scope 交集非空才衝突；但 `site_core` 是全站共用核心範圍，與任何局部 scope 都視為衝突。前端每個頁面都會額外查詢 `site_core`，因此不可讓 `site_core` 與其他局部維護事件在相同時間並行。
- draft、cancelled、completed 不佔用排程。
- 同一事件 update 不得與自己比對而誤判衝突。

衝突檢查、鎖定、事件更新、scope links、audit、idempotency 必須在同一 PostgreSQL transaction。不得只在 Edge Function 先 SELECT 再 INSERT。

## 7. Idempotency、版本與交易

- 所有 create/update/action 都必須有 idempotency key。
- key 以 actor + key 作唯一識別；同 key 同 payload 回傳原結果；同 key 不同 payload 回 409 `IDEMPOTENCY_KEY_REUSED`。
- request hash 由伺服器端對正規化輸入計算，不接受 client 自報 hash。
- update/action 必須帶 expected_version；版本不符回 409 `VERSION_CONFLICT`。
- 寫入交易流程：驗證呼叫者 → 驗證輸入 → 開始函式交易 → 取得 transaction-scoped lock → 檢查 idempotency → 驗證狀態/version → 檢查衝突 → 寫 event/scopes → 寫 audit → 儲存 idempotency response → commit。
- 任一步失敗必須 rollback，不能留下半套事件或稽核資料。
- 所有寫入 RPC 使用相同 transaction-scoped advisory lock，避免跨 scope 的排程競態。
- v1 不設定自動清理；冪等記錄永久保留，以維持同一 actor + key 的重送語意。若未來要刪除，必須先設計過期 key 重送的明確行為。

## 8. 錯誤碼

| HTTP | code | 意義 |
|---|---|---|
| 400 | `INVALID_REQUEST` | JSON/參數格式錯誤 |
| 401 | `UNAUTHENTICATED` | 未登入、JWT 無效或過期 |
| 403 | `FORBIDDEN` | 非管理員或無權操作 |
| 404 | `NOT_FOUND` | 事件不存在 |
| 409 | `CONFLICT` | 排程/狀態衝突 |
| 409 | `VERSION_CONFLICT` | 版本已更新 |
| 409 | `IDEMPOTENCY_KEY_REUSED` | 同 key 不同 payload |
| 422 | `VALIDATION_ERROR` | 欄位或業務規則驗證失敗 |
| 500 | `INTERNAL_ERROR` | 未預期錯誤 |

錯誤回應不得包含 SQL、stack trace、secret、DB schema 名稱或敏感授權細節。

## 9. 已決議的架構事項與仍待定稿事項

### 9.1 匿名 status 與 private schema / SECURITY INVOKER 權限決議

**採用方案 A：status RPC 維持 SECURITY INVOKER；四個管理 RPC 使用 SECURITY DEFINER，owner 為內建 `pg_database_owner`。**

理由：避免在 exposed `public` schema 增加以高權限 owner 執行的公開函式，降低繞過 RLS 的風險。

必要 grants/RLS：
- `anon`、`authenticated` 可 EXECUTE `public.maintenance_status_public`；先撤銷 `PUBLIC` 預設 EXECUTE，再明確授權。
- `anon` 僅在此功能確實需要時取得 private schema `USAGE` 與公開狀態資料所需的最小 `SELECT`；不得取得 INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER 等寫入或管理權限。
- `authenticated` 取得 status 查詢及受 RLS 保護的管理資料 SELECT 權限；管理 RPC 由 `pg_database_owner` 依其最小 table grants 與 RLS policy 執行。使用者角色不直接取得管理寫入 table grants。
- status 相關 RLS policy 必須明確限制可公開資料列，並以公開欄位白名單控制 RPC 回傳；不得依賴前端過濾敏感欄位。
- private schema 不加入 Data API Exposed schemas。這只阻止 PostgREST 將 private tables 作為一般 REST endpoints 暴露，不會取代 PostgreSQL grants/RLS。
- 若未來發現這組 grants/RLS 無法安全滿足公開讀取需求，停止實作並重新審查；不得自行將公開 status RPC 改為 SECURITY DEFINER。

此方案已在 GoTrue-issued JWT + PostgREST 隔離 CI 中測試 anon、一般 authenticated 與 admin 的 status/RPC 存取；測試中的 `public.is_admin()` 是 disposable CI helper，不等同已核實正式資料庫中的 helper 定義。正式環境部署前仍須唯讀檢查該 helper 的 owner、security mode、search_path、依賴與 ACL。管理 RPC 的 SECURITY DEFINER owner 與 RLS 限制另依本節前述設計。

### 9.2 Audit log 寫入邊界決議

目前 single-pass SQL 草案的管理 RPC 使用 SECURITY DEFINER，owner 為內建 `pg_database_owner`；audit 寫入由管理 RPC 在同一交易內執行。未新增可由一般使用者直接呼叫的 audit writer。

- audit table 的必要 INSERT 權限授予 `pg_database_owner`，並由 RLS policy 限制為 `private.maintenance_uid() IS NOT NULL AND public.is_admin()`；`authenticated` 僅有 SELECT grant，且受管理員 RLS policy 限制，不取得 INSERT/UPDATE/DELETE 權限。
- actor 一律取自 `private.maintenance_uid()`；不可接受 client 傳入 actor/user ID。
- audit table 不授予 anon 任何權限；`authenticated` 僅有 SELECT grant，且受管理員 RLS policy 限制；不授予 UPDATE/DELETE 給 `authenticated` 或 `pg_database_owner`，並以 trigger 拒絕一般資料庫操作路徑對 audit row 執行 UPDATE/DELETE/TRUNCATE；資料庫 owner、superuser 或具足夠權限者仍可能停用 trigger 或修改 schema，因此不得宣稱對高權限操作者絕對不可竄改。
- private schema 不加入 Data API Exposed schemas；前端只呼叫受控 RPC。
- 重要限制：PostgreSQL grants/RLS 不會辨識 SQL 是由 RPC 內部或其他資料庫路徑發出；目前 `authenticated` 對 audit table 有 SELECT grant，但沒有寫入 grant。安全邊界仍依賴 private schema 不暴露、RLS、RPC 授權與應用程式入口限制。
- 若產品要求更強的資料庫層防竄改，需另行提出方案、審查 SECURITY DEFINER 的 owner/ACL/search_path/RLS 影響，並在隔離環境測試後才可採用。

### 9.3 已由現有 UI、Edge Function 與 SQL 對齊的欄位限制

以下限制已逐一比對管理介面 `admin.html`、Edge Function 共用驗證 `supabase/functions/_shared/maintenance.ts` 與 SQL 草案；三處數值一致，並新增 GoTrue/PostgREST 隔離測試驗證資料庫端邊界：

| 欄位 | 上限 | 證據／用途 |
|---|---:|---|
| `title` | 200 字元 | 管理介面 maxlength、Edge Function parser、SQL CHECK/validation |
| `message` | 4,000 字元 | 管理介面 maxlength、Edge Function parser、SQL CHECK/validation |
| `internal_note` | 4,000 字元 | 管理介面 maxlength、Edge Function parser、SQL validation |
| `reason` | 500 字元 | 管理介面 maxlength、Edge Function parser、SQL validation |

七個 scope code 也已逐一比對管理介面 checkbox、Edge Function `SCOPE_CODES`、SQL CHECK/seed，三處一致：`site_core`、`announcements_info`、`events_competitions`、`video_content`、`membership_growth`、`store_support`、`downloads_app`。這是程式碼一致性核對，不代表已在正式資料庫建立 seed。

status API 第一版只回傳目前生效事件；未來預告事件不在本版範圍。已開始事件採保守限制：不得一般修改排程時間或 scope。

### 9.4 v1 已定稿的流量與資料保留決策

- v1 不承諾 HTTP 429 `RATE_LIMITED`，因此已從錯誤碼契約移除。現有 Edge Functions 沒有自建的 per-IP/per-user 限流器，不得宣稱已有應用層限流。
- 公開 status API 是唯讀查詢，只接受七個固定 scope code，回傳欄位白名單；這些限制不等同於防 DDoS 或完整限流。CORS 只控制瀏覽器跨來源讀取，不是 API 身分驗證。
- 正式功能仍維持關閉。啟用公開端點前，必須完成正式環境監控與濫用處理方案審查；若需要 per-IP 限流，須先確認 Supabase 受信任用戶端 IP 標頭契約，不能盲信呼叫端可偽造的轉送標頭。
- v1 的 audit log 採 append-only，永久保留；不建立自動刪除、pg_cron 或額外付費排程。Audit snapshots 會保留管理操作的 before/after 資料，管理員不得把密碼、驗證碼或其他秘密寫入 internal note。
- v1 的 idempotency 記錄永久保留，不自動刪除，以免舊 key 被重用後重複執行操作。若未來需清理，必須另行設計可驗證的過期與重送規則。
- 上述永久保留策略適用於目前低頻管理用途；若資料量或隱私需求改變，必須另做 retention migration，不能直接刪除資料。

### 9.5 仍需在正式部署前人工確認

- Supabase Dashboard 的 Data API Exposed schemas 必須確認 `private` 未暴露。
- 正式環境 CORS、Edge Function 環境變數與 runtime smoke test 尚未驗證。
- 完整正式 schema baseline 與 migration history 空缺的安全處理方式仍未完成。
- 現有正式專案的 Security Advisor 警告屬於獨立修補工作，不包含在本次維護系統 Migration。

## 10. 驗收條件

- anon 不能呼叫任何管理 list/create/update/action RPC；anon 只能呼叫公開 status RPC，且不能寫入任何 private table。
- 一般 authenticated user 不能列出或變更維護事件。
- admin 可以透過原始使用者 JWT 呼叫管理 RPC。
- 前端傳入假 role/actor_id 不會改變授權結果或 audit actor。
- status 只回傳公開白名單欄位。
- global/local scope 規則與排程衝突規則在併發情境仍成立。
- version conflict、idempotency 重送與 key reuse 均有測試。
- audit 與事件資料交易一致。
- 所有 private tables 啟用 RLS，所有 RPC 的 EXECUTE ACL 明確最小化。
- 真實 JWT/RLS 行為未能在隔離環境驗證前，不得核准正式 migration 或部署。

## 11. 實作前狀態與禁止事項

目前：
- 五支 Edge Functions：原始碼已提交，隔離 CI 已通過；正式環境尚未部署。
- 五個 RPC、private schema 與六張資料表：已在隔離 PostgreSQL 17 / GoTrue / PostgREST 測試環境驗證；正式環境尚未建立。
- Migration：現有雙 migration legacy 路徑及 single-pass draft 均已在隔離 CI 通過；是否採用 single-pass 作為最終正式 migration，仍受 migration history / 各環境套用紀錄確認 gate 約束，尚未核准正式執行或合併。
- 正式 Supabase：未修改；正式 migration history 與 schema baseline 尚未核准。

本規格與 Migration 合併不代表正式資料庫已部署。隔離 CI 已使用 GoTrue 簽發 JWT 與 PostgreSQL 17 / PostgREST 驗證核心授權與 RLS 行為；正式環境仍須完成 schema baseline、Data API Exposed schemas、CORS/env 與 smoke test。