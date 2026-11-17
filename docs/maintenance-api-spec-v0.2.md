# 維護系統 API 規格 v0.2

> 本版依使用者確認的七個維護範圍與全站維護規則更新。
> 狀態：規格草案，尚未實作；不得視為已部署 API。

## 1. 維護範圍代碼

| 顯示名稱 | 建議 code |
|---|---|
| 網站核心 | `site_core` |
| 公告與資訊 | `announcements_info` |
| 活動與比賽 | `events_competitions` |
| 影音內容 | `video_content` |
| 會員與成長 | `membership_growth` |
| 商城與客服 | `store_support` |
| 下載與 App | `downloads_app` |

以上七個名稱已由使用者確認；技術代碼為建議值，正式 seed 前需最後核准。

**全站維護是獨立控制，不是第八個 scope。** 建議事件 payload 使用 `is_global: true`；全站事件不得同時帶 scopes。局部事件使用 `is_global: false` 並至少帶一個已啟用 scope code。

## 2. 共通規則

- 五支 Edge Functions 均待建置。
- 管理 API 必須驗證 JWT 並在伺服器端檢查 admin role；不信任前端傳入的 role、isAdmin 或 actor id。
- 全站維護期間，管理員仍可進入管理後台；maintenance bypass 不會略過 JWT／admin 驗證。
- 公開 status 只回傳標題、公開訊息、is_global、scope code、開始與結束時間及必要狀態，不回傳 internal_note、actor 或 audit snapshots。
- 時間以 ISO 8601 傳輸；管理端時區 Asia/Taipei，DB 使用 timestamptz，生效判斷使用伺服器時間。
- 成功格式：`{ "ok": true, "data": ... }`；錯誤格式：`{ "ok": false, "error": { "code": "...", "message": "..." } }`。
- 建立／更新／動作操作須支援 idempotency key 與 version 檢查；排程衝突在同一 DB transaction 中檢查。

## 3. API

### `maintenance-status`（公開讀取）

輸入：可選頁面 scope code；若未提供，回傳目前生效的全站維護狀態及適用於該入口的必要維護資訊。

回傳欄位建議：`is_maintenance`、`is_global`、`scopes`、`title`、`message`、`starts_at`、`ends_at`、`server_time`。

管理員已登入時，可回傳 `admin_bypass: true` 作為前端顯示依據；這不構成授權，管理 API 必須重新驗證 admin。

### `maintenance-admin-list`（管理員）

輸入：status、scope、is_global、from、to、limit、cursor。
回傳：事件、scope、is_global、status、version、建立者／更新者摘要及管理員備註（限 admin）。

### `maintenance-event-create`（管理員）

輸入：title、message、internal_note、is_global、scope_codes、starts_at、ends_at、status、reason、idempotency_key。
驗證：starts_at < ends_at；is_global=true 時 scope_codes 必須為空；is_global=false 時至少一個 scope code 且全部有效。建立事件、關聯、audit 與 idempotency 記錄須同交易提交。

### `maintenance-event-update`（管理員）

輸入：event_id、expected_version、可更新欄位、reason、idempotency_key。
驗證：version 相符、global/scope 模式正確、狀態允許更新、重新檢查排程衝突。更新與 audit 同交易。

### `maintenance-event-action`（管理員）

輸入：event_id、expected_version、action、reason、idempotency_key。
初步 action：schedule、cancel、complete。是否支援 start_now、extend、end_early 待產品規則定稿。狀態轉換不合法時回傳 409。

## 4. 錯誤碼

- 400 `INVALID_REQUEST`
- 401 `UNAUTHENTICATED`
- 403 `FORBIDDEN`
- 404 `NOT_FOUND`
- 409 `CONFLICT`、`VERSION_CONFLICT`、`IDEMPOTENCY_KEY_REUSED`
- 422 `VALIDATION_ERROR`
- 429 `RATE_LIMITED`
- 500 `INTERNAL_ERROR`

## 5. 排程規則

時間區間採 `[starts_at, ends_at)`。重疊判斷為 existing.starts_at < requested.ends_at 且 requested.starts_at < existing.ends_at。
- global 與任何 global/local 重疊：衝突。
- local 與 local：只有 scope 交集非空且時間重疊才衝突。
- cancelled、completed、draft 不佔用排程時段（draft 是否可預留時段仍待決策，正式實作前需定稿）。
- 所有排程變更透過同一 DB transaction lock + conflict check + write + audit。

## 6. 尚待定稿

1. 開始後可修改欄位及是否允許延長／提前結束。
2. 自然到期是否自動改為 completed。
3. draft 是否佔用排程時段。
4. 各 scope 維護期間是封鎖、唯讀或提示。
5. 每個 scope 的完整頁面/API 依賴映射。
6. 稽核紀錄保留期與查詢介面。

## 7. 本版狀態

七個維護範圍名稱、獨立全站控制、管理員全站維護期間可用，均已由使用者確認。API 與資料表仍待實作。

**本文件更新不會執行 Migration、不會修改 Supabase 正式資料庫，也不會部署 Edge Functions。**
