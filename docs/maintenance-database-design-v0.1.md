# 維護系統資料庫結構設計 v0.1

> 狀態：設計草案，待七個維護範圍名稱、前端使用情境及管理流程核實。
> 分支：`feature/maintenance-system`
> 本文件不是可直接執行的 Migration。尚未修改 Supabase 正式資料庫、未建立資料表、未部署 Edge Functions。

## 1. 設計目標

- 支援全站或指定範圍的維護公告。
- 支援立即建立、預約排程、取消、完成及查詢。
- 多範圍事件可同時影響多個維護範圍。
- 排程衝突在資料庫交易中檢查，避免兩位管理員同時建立衝突事件。
- 事件異動與稽核紀錄同一交易提交或回滾。
- 前台只讀取公開必要欄位；管理員備註及稽核資料不公開。
- 不要求新增 Supabase 專案或付費資源。

## 2. Schema 與權限邊界

建議將維護系統資料表放在非 Data API 公開的 `private` schema，而不是直接放在 `public`：

- `private.maintenance_scopes`
- `private.maintenance_events`
- `private.maintenance_event_scopes`
- `private.maintenance_audit_logs`
- `private.maintenance_idempotency`

部署前必須確認 Supabase Data API 的 Exposed schemas 不包含 `private`。一般訪客與登入使用者不取得這些資料表的直接寫入權限；五支 Edge Functions 經過驗證後，透過受控資料庫交易函式執行操作。

管理員驗證沿用目前 `public.profiles.role` 的資料來源：Edge Function 先驗證 JWT 使用者，再由伺服器端查核該使用者的 `profiles.role = 'admin'`。不得信任前端傳入的角色或 user id。Service role 僅能存在伺服器端環境，不可放進前端。

## 3. 資料表設計

### A. `private.maintenance_scopes` — 維護範圍目錄

| 欄位 | 型別 | 規則 | 用途 |
|---|---|---|---|
| id | uuid | PK | 範圍識別碼 |
| code | text | UNIQUE、NOT NULL | 穩定代碼，API 使用 |
| name | text | NOT NULL | 管理端／前台顯示名稱 |
| description | text | NULL | 範圍說明 |
| is_global | boolean | NOT NULL DEFAULT false | 是否代表全站 |
| sort_order | integer | NOT NULL DEFAULT 0 | 顯示順序 |
| enabled | boolean | NOT NULL DEFAULT true | 是否可供新事件選用 |
| created_at | timestamptz | NOT NULL DEFAULT now() | 建立時間 |
| updated_at | timestamptz | NOT NULL DEFAULT now() | 更新時間 |

設計規則：
- `code` 建立後不因顯示名稱修改而改變。
- 全站範圍若存在，必須唯一（以 partial unique index 保證）。
- 不先猜測七個範圍的正式代碼。必須先核對網站導覽、功能頁面與使用者原先定義的七個範圍，再建立 seed。
- 需確認「七個範圍」是否包含全站，或是七個子系統另加全站。

### B. `private.maintenance_events` — 維護事件主表

| 欄位 | 型別 | 規則 | 用途 |
|---|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() | 事件識別碼 |
| title | text | NOT NULL | 維護標題 |
| message | text | NOT NULL | 對外維護訊息 |
| internal_note | text | NULL | 僅管理員可見的備註 |
| status | text | NOT NULL | draft / scheduled / cancelled / completed |
| starts_at | timestamptz | NOT NULL | 預定開始時間 |
| ends_at | timestamptz | NOT NULL | 預定結束時間 |
| version | integer | NOT NULL DEFAULT 1 | 樂觀鎖版本 |
| created_by | uuid | FK auth.users(id) | 建立者 |
| updated_by | uuid | FK auth.users(id) | 最後修改者 |
| created_at | timestamptz | NOT NULL DEFAULT now() | 建立時間 |
| updated_at | timestamptz | NOT NULL DEFAULT now() | 更新時間 |
| cancelled_at | timestamptz | NULL | 取消時間 |
| completed_at | timestamptz | NULL | 完成時間 |

必要限制：
- `starts_at < ends_at`。
- `status` 僅允許上述四種值。
- 更新時必須比對呼叫端傳入的 `expected_version`；成功更新才將 version + 1。
- `active` 不建議儲存成另一個可手動修改的狀態。是否正在維護應由 `status = scheduled` 且伺服器時間落在 `[starts_at, ends_at)` 計算，避免時間到期後狀態不同步。
- 已取消、已完成事件保留作為歷史紀錄，不硬刪除。

### C. `private.maintenance_event_scopes` — 事件與範圍關聯

| 欄位 | 型別 | 規則 | 用途 |
|---|---|---|---|
| event_id | uuid | FK maintenance_events(id) ON DELETE CASCADE | 事件 |
| scope_id | uuid | FK maintenance_scopes(id) | 範圍 |
| created_at | timestamptz | NOT NULL DEFAULT now() | 建立時間 |

主鍵：`(event_id, scope_id)`。每個事件至少要有一個範圍。事件可以選擇多個範圍；是否允許「全站」與其他範圍同時選取，需由產品規則決定，初步建議全站選取時不再混選子範圍。

### D. `private.maintenance_audit_logs` — 不可任意修改的稽核紀錄

| 欄位 | 型別 | 規則 | 用途 |
|---|---|---|---|
| id | bigint | GENERATED ALWAYS AS IDENTITY、PK | 紀錄序號 |
| event_id | uuid | NULL、FK maintenance_events(id) | 關聯事件；刪除事件時保留紀錄，故採適當的 SET NULL 策略 |
| actor_id | uuid | NULL、FK auth.users(id) | 執行者 |
| action | text | NOT NULL | created / updated / scheduled / cancelled / completed |
| before_data | jsonb | NULL | 異動前快照 |
| after_data | jsonb | NULL | 異動後快照 |
| reason | text | NULL | 操作原因 |
| request_id | uuid | NOT NULL | 請求追蹤識別碼 |
| created_at | timestamptz | NOT NULL DEFAULT now() | 發生時間 |

權限規則：
- 僅伺服器端交易函式可新增紀錄。
- 不提供一般角色 UPDATE／DELETE 權限。
- 不記錄 JWT、密碼、service role key 或不必要的個人資料。
- 建立、更新、取消、完成等操作都必須寫入稽核紀錄。

### E. `private.maintenance_idempotency` — 重複請求保護

| 欄位 | 型別 | 規則 | 用途 |
|---|---|---|---|
| actor_id | uuid | NOT NULL、FK auth.users(id) | 操作者 |
| idempotency_key | uuid | NOT NULL | 用戶端每次操作產生的唯一鍵 |
| operation | text | NOT NULL | API／操作名稱 |
| request_hash | text | NOT NULL | 正規化請求內容雜湊 |
| response_data | jsonb | NULL | 已完成操作的結果 |
| created_at | timestamptz | NOT NULL DEFAULT now() | 建立時間 |
| expires_at | timestamptz | NOT NULL | 保留期限 |

主鍵建議：`(actor_id, idempotency_key)`。同一操作者以同一 key、同一內容重送時回傳先前結果；同一 key 卻帶不同內容時回傳 409 `IDEMPOTENCY_KEY_REUSED`。保留期限與清理策略需在實作前確認。

## 4. 排程衝突與併發控制

時間區間採半開區間 `[starts_at, ends_at)`：前一事件在 12:00 結束，下一事件 12:00 開始，不視為重疊。

建立或修改排程時，必須在同一資料庫交易中：

1. 取得維護排程專用的 transaction-level advisory lock，將所有排程異動序列化。
2. 讀取事件狀態與選取範圍，排除 cancelled / completed / draft 事件。
3. 比對時間區間是否重疊。
4. 若任一方是全站範圍，與任何其他範圍的重疊都視為衝突。
5. 若雙方都是局部範圍，只有至少一個相同 scope 才視為衝突。
6. 無衝突才寫入事件、範圍關聯、稽核紀錄及 idempotency 結果；任一步驟失敗全部回滾。

衝突條件：`existing.starts_at < requested.ends_at AND requested.starts_at < existing.ends_at`。

重要：只在 Edge Function 先 SELECT 再 INSERT 並不足以防止兩個同時送出的請求互相穿透。鎖定、檢查與寫入必須在同一個資料庫交易函式內完成。所有新增、修改時間或範圍、排程啟用的路徑都必須使用同一套衝突檢查。

## 5. 初步狀態機

| 目前狀態 | 允許動作 | 新狀態 |
|---|---|---|
| draft | 排程 | scheduled |
| draft | 取消 | cancelled |
| scheduled | 修改排程 | scheduled（version + 1） |
| scheduled | 取消 | cancelled |
| scheduled | 時間到達 | 仍為 scheduled；前台計算為維護中 |
| scheduled | 管理員標記完成 | completed |
| scheduled | 時間結束 | 前台計算為已結束；資料仍保留 scheduled，直到清理／封存規則確認 |
| cancelled | 無 | 終態 |
| completed | 無 | 終態 |

此表是保守的初步建議，尚待確認：事件開始後是否允許修改訊息、結束時間；事件自然到期是否自動轉 completed；是否需要「立即開始」動作。正式狀態轉換必須在 API 與資料庫交易函式中共同驗證。

## 6. 索引建議

- `maintenance_events(status, starts_at)`
- `maintenance_events(ends_at)`
- `maintenance_event_scopes(scope_id, event_id)`
- `maintenance_audit_logs(event_id, created_at DESC)`
- `maintenance_audit_logs(actor_id, created_at DESC)`
- `maintenance_idempotency(expires_at)`
- `maintenance_scopes(code)`（由 UNIQUE constraint 提供）

索引名稱、查詢計畫與是否需要額外 GIN index，待實際查詢模式確認後再決定。

## 7. 五支 API 與資料表對應

| Edge Function | 讀取／寫入資料 |
|---|---|
| maintenance-status | 讀 scopes、events、event_scopes；只回傳公開欄位 |
| maintenance-admin-list | 讀 events、event_scopes、scopes；管理員可讀內部備註 |
| maintenance-event-create | 寫 events、event_scopes、audit_logs、idempotency |
| maintenance-event-update | 更新 events、重建 event_scopes、寫 audit_logs、idempotency |
| maintenance-event-action | 更新 events 狀態欄位、寫 audit_logs、idempotency |

資料庫交易函式建議集中處理 create/update/action，Edge Function 負責驗證 JWT、管理員權限、輸入格式與回應格式。公開 status API 也由 Edge Function 讀取必要資料，避免公開直接存取內部資料表。

## 8. 實作前仍需核對的產品決策

1. 七個範圍的正式名稱與代碼；「全站」是否算在七個之內。
2. 全站範圍與子範圍能否同時選取。
3. 已開始事件是否允許修改標題、訊息、結束時間或範圍。
4. 事件到期後是否自動標記 completed，或只依時間計算前台狀態。
5. 是否需要草稿、立即開始、延長維護、提前結束等操作。
6. 管理員清單是否需要搜尋、日期篩選、分頁及匯出。
7. 稽核紀錄保留期限，以及是否需要管理員可查詢稽核紀錄的介面。

## 9. 驗收測試設計

- 一般訪客及一般登入者無法讀取管理備註或稽核紀錄。
- 非管理員無法呼叫任何管理端寫入操作。
- 開始時間晚於或等於結束時間時拒絕。
- 同 scope 重疊事件拒絕；不同 scope 不重疊事件可建立。
- 全站事件與任一 scope 重疊時拒絕。
- 12:00 結束與 12:00 開始的相鄰事件可建立。
- 兩個併發請求搶同一時段，只能有一個成功。
- version 過期的更新回傳 409，不覆蓋較新的資料。
- 事件寫入成功但 audit 寫入失敗時，整筆交易回滾。
- 同 idempotency key 重送不會重複執行；同 key 不同 payload 回傳 409。
- cancelled / completed 事件不可再次排程或被一般 update 改回 scheduled。

---

## 本版結論

目前建議採用五張核心資料表、private schema、資料庫交易函式與伺服器端管理員驗證。七個範圍的正式代碼及狀態機仍保留為待確認項目，避免在沒有證據時自行猜測。

**下一階段**：先從網站前端與既有管理介面核實七個範圍及操作需求，再把本草案收斂為可供 Migration 實作的 v0.2。確認前不執行 SQL DDL、不建立正式資料表、不部署。
