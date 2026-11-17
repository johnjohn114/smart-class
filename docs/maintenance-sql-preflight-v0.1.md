# 維護系統 SQL 生成前定稿檢查 v0.1

> 目標：完成正式 Migration SQL 生成前的設計凍結與測試規格。
> 本文件不是 SQL，不建立任何資料庫物件。
> 本輪不生成 SQL、不執行 SQL、不修改 Supabase、不部署 Edge Functions。

## 1. 已確認的產品決策

- 七個範圍：`site_core`、`announcements_info`、`events_competitions`、`video_content`、`membership_growth`、`store_support`、`downloads_app`。
- 全站維護獨立控制，不算第八個 scope。
- 全站維護期間，管理員仍可登入並使用後台。
- 時間欄位使用 `timestamptz`；UI 使用 Asia/Taipei；API 傳 ISO 8601。
- 時間區間使用半開區間 `[starts_at, ends_at)`。
- 不使用 pg_cron；是否生效由伺服器時間判斷。
- 事件以取消／完成保留歷史，不提供一般硬刪除。
- 不新增 Supabase 專案、付費資源或背景排程。

## 2. 正式交易操作契約

所有會改變排程占用或事件狀態的寫入，必須由資料庫端單一交易操作完成。Edge Function 不可先查衝突、再分開寫入。

建議資料庫內部操作（名稱是設計識別，不是已建立函式）：

| 操作識別 | 用途 | 主要輸入 |
|---|---|---|
| `maintenance_create_event` | 建立 draft 或 scheduled 事件 | 驗證後 actor、事件欄位、scope codes、idempotency key |
| `maintenance_update_event` | 更新允許欄位 | event id、expected version、欄位白名單、reason、key |
| `maintenance_apply_event_action` | schedule／cancel／complete | event id、expected version、action、reason、key |
| `maintenance_read_status` | 公開安全狀態讀取 | optional scope code、server time |
| `maintenance_admin_list` | 管理員清單 | filters、cursor、limit |

上列為邏輯契約；正式 SQL 生成前仍須凍結實際函式簽章、回傳型別及呼叫權限。

## 3. 交易固定順序

對 create、會影響排程的 update、schedule/cancel/complete action，統一採以下順序：

1. Edge Function 驗證 JWT，使用同一 JWT 呼叫 `auth.getUser()` 與 `public.is_admin()`。
2. actor id 只取驗證成功的 `user.id`，不接受 request body 的 actor id、role、email。
3. 驗證並正規化輸入；檢查 scope code 白名單、時間、文字長度、欄位白名單。
4. 開始資料庫交易。
5. 取得同一把固定的 transaction-scoped advisory lock。第一版採單一全域維護排程鎖，避免多 scope 多鎖死結；目前管理操作量低，先以正確性優先。
6. 在鎖內檢查／取得 idempotency key：
   - 同 actor + key + operation + request hash：回放已保存結果。
   - 同 actor + key 但 operation 或 hash 不同：409 `IDEMPOTENCY_KEY_REUSED`。
   - 新 key：繼續處理。
7. 若為 update/action，鎖定事件列並檢查 expected_version。
8. 驗證狀態轉換與跨表規則。
9. 若新狀態會佔用排程，執行時間與 scope 衝突檢查。
10. 寫入 event 與 scope links；version 僅在成功變更時加一。
11. 同一交易寫入 audit log（actor、action、reason、before/after 業務快照、request id）。
12. 同一交易保存 idempotency response。
13. commit。任一步失敗 rollback，不能留下只有 event 沒 audit 或只有 idempotency 沒結果的半成品。

注意：交易鎖必須在資料庫交易中取得，不能使用 session-level advisory lock；transaction pooler 下不可依賴連線固定性。

## 4. 排程規則凍結候選

### 4.1 佔用排程的狀態

- `draft`：不佔用。
- `scheduled`：佔用。
- `cancelled`：不佔用。
- `completed`：不佔用。

事件是否正在生效由 `status='scheduled'` 且 `starts_at <= server_now < ends_at` 計算，不增加可手動改寫的 active 狀態。

### 4.2 衝突條件

時間重疊條件：

`existing.starts_at < requested.ends_at AND requested.starts_at < existing.ends_at`

- global vs global：重疊即衝突。
- global vs local：重疊即衝突。
- local vs global：重疊即衝突。
- local vs local：只有 scope 交集非空且時間重疊才衝突。
- 同一事件更新時，衝突查詢排除自身 event id。
- draft/cancelled/completed 不參與衝突查詢。

### 4.3 跨表不變條件

- `is_global=true`：scope links 必須為空。
- `is_global=false`：至少一個 scope link，且所有 scope 必須存在、enabled。
- 不允許一個事件同時代表 global 與 local。
- 關閉 scope 不自動取消既有 scheduled event；但是否允許停用已有未來排程使用的 scope，應在管理 API 規則中阻止或要求先調整排程。

## 5. 狀態轉換凍結候選

| 目前狀態 | 操作 | 新狀態 | 規則 |
|---|---|---|---|
| draft | schedule | scheduled | 必須通過完整衝突檢查 |
| draft | cancel | cancelled | 記錄取消時間與原因 |
| scheduled | cancel | cancelled | 立即釋放未來排程占用 |
| scheduled | complete | completed | 僅允許管理員明確封存；需記錄原因 |
| cancelled | 任何一般更新／schedule | 拒絕 | 不復活舊事件；建立新事件 |
| completed | 任何一般更新／schedule | 拒絕 | 保留歷史 |
| draft | complete | 拒絕 | 不可略過排程狀態 |
| completed/cancelled | cancel/complete | 冪等回傳或 409 | 最終選擇需在 API contract 凍結 |

目前不開放 start_now、extend、end_early、delete。開始後是否允許修改 title/message/internal_note，仍需產品決策；若未明確允許，第一版採最保守規則：scheduled 事件不可修改排程核心欄位（scope、global、starts_at、ends_at），需取消後建立新事件。

## 6. 管理員權限邊界

目前確認的既有基礎：
- `public.profiles.role` 是角色來源。
- `public.is_admin()` 是新 Edge Function 管理員檢查入口。
- 不使用 `is_admin_user()` 或 `ADMIN_EMAIL` 作為新功能角色來源。

正式 SQL 前必須選定資料庫連線授權模型。安全候選：
- Edge Function 使用伺服器端 DB URL；憑證不可進前端、Git 或 log。
- 優先評估專用、最小權限的資料庫登入角色；不得直接假設使用 postgres/superuser 連線就是合格設計。
- 若內部交易函式採 SECURITY DEFINER，必須由不可登入的受限 owner 擁有、固定空 search_path、完整限定物件名稱、撤銷 PUBLIC/anon/authenticated EXECUTE，只授權專用 server role。
- 不把 private schema 加入 Data API Exposed schemas。
- 不授予 anon/authenticated 直接維護資料表權限。
- RLS 是縱深防禦，不能誤以為可限制 superuser 或 BYPASSRLS 連線。
- public status 必須透過固定、只回傳白名單欄位的讀取路徑；不得直接暴露 internal_note、actor、audit 或 idempotency 資料。

**尚未確認**：目前 Supabase 專案實際 `SUPABASE_DB_URL` 是否已配置、使用何種 pooler／資料庫角色，以及能否在現有免費資源內安全配置專用角色。不可讀取或輸出密碼值來確認；只核對變數是否存在及非敏感連線設定。

## 7. 稽核與冪等規則

- 每次成功 create/update/action 必須有且只有一筆對應 audit operation record。
- audit 寫入與 event mutation 同交易。
- audit 只追加，不允許一般 UPDATE／DELETE/TRUNCATE。
- actor_id 取自 Edge Function 已驗證 user，不取 request body。
- audit snapshot 不得含 JWT、密碼、DB URL、service key 或不必要個資。
- idempotency key 由客戶端每次操作產生 UUID；request hash 由伺服器端對正規化後 payload 計算。
- 相同 key 相同 payload 重送回傳同一結果；相同 key 不同 payload 回傳 409。
- idempotency 到期清理由後續低頻管理操作或手動維護，不新增 cron。

## 8. 必要測試矩陣（SQL／整合測試階段執行）

| 類別 | 測試 | 預期 |
|---|---|---|
| Schema | private schema 未暴露 Data API | anon/authenticated 無法經 Data API 讀取 |
| 權限 | anon 直接讀寫五表 | 全部拒絕 |
| 權限 | authenticated 非 admin 呼叫管理 API | 403 |
| 權限 | admin JWT + is_admin true | 允許管理 API |
| 權限 | body 偽造 actor_id/role | 不影響授權，actor 仍取 JWT user |
| scope | global=true 且有 scope | 拒絕 |
| scope | local 且零 scope | 拒絕 |
| scope | disabled scope 建立新事件 | 拒絕 |
| time | starts_at >= ends_at | 拒絕 |
| overlap | global 與任一 local 時間重疊 | 拒絕 |
| overlap | local scopes 有交集且時間重疊 | 拒絕 |
| overlap | local scopes 無交集 | 允許 |
| overlap | 前一事件 ends_at 等於下一事件 starts_at | 允許（半開區間） |
| state | draft -> scheduled 並無衝突 | 成功 |
| state | cancelled/completed 復活 | 拒絕 |
| version | expected_version 過期 | 409 |
| idempotency | 同 key、同 payload 重送 | 回傳同結果，不重複寫 audit |
| idempotency | 同 key、不同 payload | 409 |
| transaction | audit 寫入故意失敗 | event mutation rollback |
| transaction | 兩個併發重疊 create | 最多一個成功 |
| audit | 一般角色 UPDATE/DELETE/TRUNCATE audit | 拒絕 |
| time | 查詢跨時區／夏令時間顯示 | DB instant 一致、UI Asia/Taipei |

## 9. SQL 生成前必須關閉的阻擋項目

| 阻擋項目 | 狀態 |
|---|---|
| 七個 scope、global、admin bypass 產品決策 | 已確認 |
| 表格欄位、FK、索引初稿 | 已有草案，需隨函式簽章一起定稿 |
| transaction lock 與衝突規則 | 已提出候選，需最終凍結 |
| 狀態轉換與已開始事件可編輯範圍 | 部分未決 |
| DB URL／pooler／角色授權模型 | 未驗證 |
| private schema 是否未暴露 | 需再次唯讀確認設定 |
| repository migration 與 Supabase migration history 差異 | 未解決 |
| 本地 PostgreSQL／Supabase CLI 測試工具 | 尚未具備／未驗證 |
| SQL 靜態審查與測試計畫 | 已列出，未執行 |

## 10. 本輪結論

目前已完成正式 SQL 生成前的交易順序、排程衝突、狀態轉換候選、權限邊界、稽核／冪等契約與測試矩陣。

**尚未生成新的 SQL，也未修改現有 SQL 草案。** 原有 `maintenance-schema-draft-v0.1.sql` 仍只是早期 DDL 草案，不能直接部署。

只有在第 9 節阻擋項目處理完、簽章及狀態規則凍結、測試環境可用後，才進入正式 Migration SQL 生成。
