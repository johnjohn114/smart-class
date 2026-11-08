# 維護系統資料庫結構設計 v0.2

> 狀態：依使用者於 2026-11-08 確認的七個維護範圍與全站／管理員規則更新。
> 本文件為設計稿，不是 Migration。沒有修改 Supabase 正式資料庫、沒有建立資料表、沒有部署 Edge Functions。

## 1. 已確認的產品決策

使用者已確認七個維護範圍：

1. 網站核心
2. 公告與資訊
3. 活動與比賽
4. 影音內容
5. 會員與成長
6. 商城與客服
7. 下載與 App

另已確認：
- **全站維護是獨立的全站維護控制**，不計入上述七個範圍。
- **全站維護時管理員仍可登入管理後台**。
- 一般使用者依全站／個別範圍維護狀態顯示維護提示或限制功能。
- 管理員繞過維護畫面不等於繞過資料庫權限；每個管理 API 仍須重新驗證 JWT 與管理員角色。

## 2. 七個範圍的建議穩定代碼

以下代碼為依已確認名稱所擬定的資料庫/API key；名稱已由使用者確認，代碼尚未經實際 migration 建立。

| 顯示名稱 | 建議 code | 初步涵蓋範圍（需在前端接入時逐頁確認） |
|---|---|---|
| 網站核心 | `site_core` | 首頁、網站內容、快速連結 |
| 公告與資訊 | `announcements_info` | 最新消息、公告管理、行事曆、AI 公告 |
| 活動與比賽 | `events_competitions` | 活動／比賽、達人榜、相關報名與簽到 |
| 影音內容 | `video_content` | 影音頻道 |
| 會員與成長 | `membership_growth` | 訪客帳號、個人中心、會員成長、獎勵、優惠券、通知 |
| 商城與客服 | `store_support` | 商品、訂單、客服中心 |
| 下載與 App | `downloads_app` | 檔案下載、App 更新、App 設定 |

頁面映射目前是根據網站導覽與後台模組的靜態檢視所做的初步分組。正式接入前應逐頁確認所有 API、共用元件、登入流程及背景任務是否也屬於該範圍。

## 3. 全站維護的資料模型決策

全站維護**不新增為第八個 scope**，也不塞入七個範圍的 scope list。建議在 `maintenance_events` 增加獨立欄位：

| 欄位 | 型別 | 規則 | 用途 |
|---|---|---|---|
| is_global | boolean | NOT NULL DEFAULT false | 此事件是否為全站維護 |

規則：
- `is_global = true` 時，事件不得同時建立七個 scope 關聯；此時 `maintenance_event_scopes` 必須為空。
- `is_global = false` 時，事件必須至少關聯一個已啟用的 scope。
- 一筆事件只採一種模式：全站或一個以上局部範圍。
- 全站事件與任何局部事件時間重疊時，視為排程衝突。
- 局部事件之間，只有範圍交集非空且時間重疊才衝突。
- 全站事件彼此時間重疊亦視為衝突。

資料庫可用交易函式與 constraint trigger（若採用）共同保護此規則；不可只在前端檢查。

## 4. 五張核心資料表

### A. `private.maintenance_scopes`
欄位：`id uuid PK`、`code text UNIQUE NOT NULL`、`name text NOT NULL`、`description text`、`sort_order integer NOT NULL DEFAULT 0`、`enabled boolean NOT NULL DEFAULT true`、`created_at timestamptz NOT NULL DEFAULT now()`、`updated_at timestamptz NOT NULL DEFAULT now()`。

Seed 預定為上表七個代碼。代碼建立後不可因顯示名稱變更而任意改動。此表不包含全站控制項。

### B. `private.maintenance_events`
欄位：`id uuid PK DEFAULT gen_random_uuid()`、`title text NOT NULL`、`message text NOT NULL`、`internal_note text`、`is_global boolean NOT NULL DEFAULT false`、`status text NOT NULL`、`starts_at timestamptz NOT NULL`、`ends_at timestamptz NOT NULL`、`version integer NOT NULL DEFAULT 1`、`created_by uuid REFERENCES auth.users(id)`、`updated_by uuid REFERENCES auth.users(id)`、`created_at timestamptz NOT NULL DEFAULT now()`、`updated_at timestamptz NOT NULL DEFAULT now()`、`cancelled_at timestamptz`、`completed_at timestamptz`。

限制：`starts_at < ends_at`；status 初步限定 `draft`、`scheduled`、`cancelled`、`completed`。是否需增加 `in_progress` 狀態，仍依狀態機決策。使用 version 樂觀鎖。是否全站由 is_global 表示，不能把全站字串偽裝成 scope code。

### C. `private.maintenance_event_scopes`
欄位：`event_id uuid REFERENCES maintenance_events(id)`、`scope_id uuid REFERENCES maintenance_scopes(id)`、`created_at timestamptz NOT NULL DEFAULT now()`；複合主鍵 `(event_id, scope_id)`。

限制：局部事件至少一個 scope；全站事件不允許任何 scope 關聯。此跨表限制需由受控交易函式驗證。

### D. `private.maintenance_audit_logs`
欄位：`id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY`、`event_id uuid`、`actor_id uuid`、`action text NOT NULL`、`before_data jsonb`、`after_data jsonb`、`reason text`、`request_id uuid NOT NULL`、`created_at timestamptz NOT NULL DEFAULT now()`。

稽核紀錄由交易函式新增，不開放一般角色 UPDATE／DELETE。快照不得包含 token、密碼或 service role key。

### E. `private.maintenance_idempotency`
欄位：`actor_id uuid NOT NULL`、`idempotency_key uuid NOT NULL`、`operation text NOT NULL`、`request_hash text NOT NULL`、`response_data jsonb`、`created_at timestamptz NOT NULL DEFAULT now()`、`expires_at timestamptz NOT NULL`；複合主鍵 `(actor_id, idempotency_key)`。

同一 key 同一 payload 回傳既有結果；同一 key 不同 payload 回傳 409。

## 5. 權限與管理員維護通道

- 資料表放在非公開 `private` schema；需確認 Supabase Exposed schemas 不包含該 schema。
- 訪客及一般登入者不直接讀寫維護資料表。
- Edge Function 驗證 JWT 後，伺服器端查核 `profiles.role = 'admin'` 或使用經權限審核的管理員驗證函式。
- 全站維護時管理員可以進入管理後台並呼叫維護管理 API；但 API 的 JWT 與 admin check 不得因 maintenance bypass 而略過。
- 維護狀態 API 只回傳公開訊息、scope、開始／結束時間與必要狀態；不得回傳 internal_note、actor、稽核快照。
- 若登入／認證服務本身故障，管理員仍可登入的保證可能失效；應設計獨立緊急復原流程，不得用公開後門或共用秘密繞過認證。

## 6. 排程衝突與交易一致性

使用半開區間 `[starts_at, ends_at)`，重疊判斷：
`existing.starts_at < requested.ends_at AND requested.starts_at < existing.ends_at`。

建立、修改、排程啟用都必須在同一資料庫交易內：
1. 取得 transaction-level advisory lock（統一使用同一把維護排程鎖）。
2. 檢查狀態、scope、is_global、時間。
3. 排除 draft、cancelled、completed 等不佔用時段的事件。
4. 執行全站／局部衝突判斷。
5. 寫入事件與 scope 關聯。
6. 寫入 audit log 與 idempotency 結果。
7. 全部成功才 commit，任何步驟失敗全部 rollback。

所有排程異動入口必須走相同交易函式，不能讓管理端有另一條未檢查衝突的更新路徑。

## 7. 狀態、時間及索引

- 管理端輸入／顯示使用 `Asia/Taipei`。
- DB 使用 `timestamptz`；API 使用 ISO 8601 時間。
- 事件是否正在維護依伺服器時間判斷，不接受前端自報 now。
- 初步狀態：draft → scheduled → cancelled/completed；scheduled 依時間窗判斷目前是否生效。
- 事件開始後是否允許修改、自然到期是否自動 completed，仍需在 API v0.2 決定。
- 索引：events(status, starts_at)、events(ends_at)、event_scopes(scope_id,event_id)、audit(event_id,created_at DESC)、audit(actor_id,created_at DESC)、idempotency(expires_at)。

## 8. API 對應

- `maintenance-status`：讀取 active global event 及符合頁面 scope 的 active local events；管理員回應可帶 bypass 狀態，但不得洩露內部資料。
- `maintenance-admin-list`：admin only，讀取全站及局部事件與關聯範圍。
- `maintenance-event-create`：admin only，建立全站或局部事件，不允許兩種模式混用。
- `maintenance-event-update`：admin only，version check、scope/global 模式驗證、衝突檢查。
- `maintenance-event-action`：admin only，狀態轉換與 audit 同交易。

## 9. 尚待定稿的項目

1. 事件開始後允許修改哪些欄位。
2. 自然到期是否自動轉 completed，及是否需要排程任務。
3. 是否需要立即開始、延長、提前結束等 action。
4. 稽核紀錄保留期限及管理端查詢介面。
5. 每個 scope 的完整頁面/API 映射，尤其共用登入、通知與跨模組服務。
6. 維護期間非管理員的具體行為：封鎖操作、唯讀或只顯示警示。

## 10. 驗收測試

- 七個 scope seed 的 code 唯一且全部可被選用。
- 全站事件不關聯 scope；局部事件至少關聯一個 scope。
- 全站與任何局部範圍的重疊排程拒絕。
- 同一局部 scope 重疊拒絕，不同局部 scope 可同時維護。
- 時間相鄰事件允許。
- 併發建立衝突事件只能一筆成功。
- 非 admin 無法讀取管理清單、備註及 audit，也無法 create/update/action。
- 管理員在全站維護時仍可使用後台維護管理功能。
- version 過期回傳 409。
- audit 寫入失敗時事件操作整筆 rollback。
- idempotency key 防止重複操作。
- public status 不回傳 internal_note 或 audit data。

## 11. 本版結論

七個維護範圍已由使用者確認；全站維護為獨立控制；管理員全站維護期間保留後台存取。建議使用五張核心資料表，並以 `is_global` 與七個 scope 分離表示。

**本版仍是設計文件。未執行 DDL、未建立 Migration、未修改 Supabase 正式資料庫、未部署任何 Edge Function。**
