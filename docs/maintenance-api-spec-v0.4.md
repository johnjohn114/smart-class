# Maintenance System API 規格 v0.4

> 日期：2026-11-08  
> 分支：`feature/maintenance-system`  
> 狀態：整合規格草案；尚未實作、尚未部署，未核准正式 Migration。  
> 本版整合 v0.1～v0.3、資料庫連線模型 v0.4 與權限/RPC 安全審查 v0.1。舊版保留作為歷史紀錄，實作以本版為準；若本版標示待決，不得自行猜測。

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

目前五支 Edge Functions、五個 RPC、private schema 與維護資料表均未建立。本文件只定義契約，不代表 API 已存在。

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
- actor ID 一律取自資料庫端 `auth.uid()`；不可採信前端傳入的 actor_id、user_id、role、isAdmin 或 email。
- 管理 RPC 必須在資料庫端檢查 `auth.uid() IS NOT NULL AND public.is_admin()`。
- `public.is_admin()` 是目前候選 helper；`public.is_admin_user()` 禁止用於此功能。
- 管理 API 的 Edge Function 驗證不能取代 RPC 內的授權檢查。

### 3.2 RPC / schema

- 採用 Edge Function + 使用者 JWT + public SECURITY INVOKER RPC + private schema tables + RLS。
- private schema 不加入 Data API Exposed schemas。
- RPC 使用 `SECURITY INVOKER`、固定 `search_path = ''`，所有 schema/table/function 名稱完整限定。
- 新 RPC 先撤銷 `PUBLIC` EXECUTE，再明確授權。
- 管理 RPC 僅授予 `authenticated`；公開 status RPC 的 anon 權限方案尚有架構待決事項，見第 9 節。
- SECURITY INVOKER 執行 private table 操作時，authenticated 必須取得實際所需的最小 schema/table privileges，並由 RLS 限制。不得宣稱完全沒有 table grants 卻仍期待 invoker RPC 操作資料表。
- 不使用 service_role bypass RLS，不新增 DB URL 或資料庫密碼 secret。
- private tables 全部啟用 RLS。RLS policy 必須限制 admin；必要時同時檢查 `auth.uid() IS NOT NULL`。
- 前端只呼叫 Edge Functions；不直接操作維護資料表。

### 3.3 請求與回應

- JSON request/response。
- 成功：`{ "ok": true, "data": ... }`
- 錯誤：`{ "ok": false, "error": { "code": "...", "message": "..." } }`
- 時間傳輸採 ISO 8601，含時區 offset；資料庫使用 `timestamptz`；管理介面以 Asia/Taipei 顯示。
- 生效判斷只使用資料庫/伺服器時間，不信任用戶端時鐘。
- 所有輸入驗證型別、必填、長度、格式、允許值及欄位白名單；未知欄位拒絕，不得直接展開寫入。
- 不在錯誤訊息中洩漏 SQL、schema、secret、資料庫內部細節或管理員判斷邏輯。

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

**待決：** 匿名使用者可否呼叫 SECURITY INVOKER public RPC 並讀取 private schema 中的公開狀態資料，見第 9 節。在決議前不得實作此 RPC 權限。

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
- `status`（僅允許初始狀態 `draft` 或 `scheduled`）
- `reason`（audit 原因）
- `idempotency_key`（UUID）

驗證：
- `starts_at < ends_at`。
- `is_global=true` 時 `scope_codes` 必須為空陣列。
- `is_global=false` 時至少一個有效且 enabled scope。
- 初始 `draft` 不佔用排程；`scheduled` 必須通過排程衝突檢查。
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
- local/local：時間重疊且 scope 交集非空才衝突。
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
- advisory lock 的 key 計算/鎖定範圍需在 SQL 設計階段定稿，並確保所有寫入入口採同一鎖定策略。
- idempotency 清理不得預設新增 pg_cron；保留期限在上線前定稿。

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
| 429 | `RATE_LIMITED` | 請求過於頻繁 |
| 500 | `INTERNAL_ERROR` | 未預期錯誤 |

錯誤回應不得包含 SQL、stack trace、secret、DB schema 名稱或敏感授權細節。

## 9. 必須先解決的架構待決事項

### 9.1 匿名 status 與 private schema / SECURITY INVOKER 相容性

目前架構決策同時要求：
- `maintenance-status` 可匿名呼叫；
- RPC 為 SECURITY INVOKER；
- private schema 不暴露 Data API；
- private schema USAGE 主要授予 authenticated。

匿名呼叫者若透過 SECURITY INVOKER RPC 讀取 private tables，仍需要相應的 private schema USAGE、table SELECT 與 RLS 可見資料列權限。現有文件尚未完整定義這組 grant/RLS，因此目前不能直接實作並宣稱相容。

可供下一輪審查的兩種方案：
A. 保持 status RPC 為 SECURITY INVOKER：明確評估是否授予 anon private schema USAGE + 最小 SELECT + 嚴格公開資料 RLS；private schema 仍不得加入 Data API Exposed schemas。  
B. status RPC 單獨採用極窄 SECURITY DEFINER：固定空 search_path、完整限定名稱、只讀公開欄位白名單、不接受任意查詢、不回傳內部資料，並獨立審查 owner/ACL。

不得在未審查前自行選擇或執行任一方案。管理寫入 RPC 仍維持 SECURITY INVOKER。

### 9.2 Audit log 寫入邊界

SECURITY INVOKER 寫入 audit 時，authenticated 需要最小 INSERT 權限與 RLS policy。因 private schema 不暴露 Data API，前端不會經 PostgREST 直接呼叫 table endpoint；但若日後變更 exposed schema 或 grants，需重新審查。若要求資料庫權限層也禁止 authenticated 直接 INSERT audit，須另行審查極窄 SECURITY DEFINER audit writer。

### 9.3 仍需在實作前定稿

- 七個 scope code 最終 seed 核准。
- title/message/internal_note/reason 的字元長度上限。
- status API 是否需要回傳未來即將開始的維護事件（本版目前只定義目前生效事件）。
- 已開始事件的管理操作限制；本版採保守限制。
- audit 保留期限與查詢分頁上限。
- idempotency key 保留期限。
- advisory lock key 策略與 RLS/grants 的隔離測試。

## 10. 驗收條件

- anon 不能呼叫任何管理 list/create/update/action RPC。
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
- 五個 Edge Functions：未建立。
- 五個 RPC：未建立。
- private schema/tables：未建立。
- Migration：未執行。
- 完整 PostgreSQL 還原測試：依使用者決定跳過，文件必須如實標示未測。
- 正式 Supabase：未修改。

本規格更新不會執行 DDL/DML、不會建立資料庫物件、不會部署、不會建立付費資源。