# Maintenance RPC + JWT/RLS 整合實作決策草案 v0.1

> 日期：2026-11-08  
> 分支：`feature/maintenance-system`  
> 狀態：使用者已選定方向 B；此文件為開發分支實作基準草案，不是正式 production migration，不可直接部署。  
> 目的：將原始四表 SQL、目前 API v0.5、五支 Edge Functions 與 user-JWT/SECURITY INVOKER 安全模型收斂，作為 RPC SQL 與隔離測試的唯一實作基準候選。

## 1. 本輪採用的方向

建議採用 API/Edge 已使用的產品模型與較新的連線安全原則：

- Edge Functions 保留原始使用者 bearer JWT；不以 service_role 代表使用者執行管理操作。
- RPC 使用 `SECURITY INVOKER`、`SET search_path = ''`、完整 schema qualification。
- 管理 RPC 在資料庫端檢查 `auth.uid() IS NOT NULL AND public.is_admin()`。
- 維護資料表放在 `private` schema，不加入 Data API Exposed schemas。
- 以 API v0.5 的七個 scope code 為候選 canonical codes。
- 不把原始 SQL 的四表直接當成可執行 RPC 的 schema；它是產品需求與歷史設計來源，需明確記錄轉換。

使用者已明確選擇方向 B。這代表採用五表 private + user JWT + SECURITY INVOKER 作為後續開發方向；仍不代表已核准正式 migration，也未執行任何資料庫變更。

## 2. 為何不直接沿用原始四表

原始 SQL 的 `maintenance_state` singleton、`scope_mode`、`mode`、`expected_end_at`、`background_path`、`announcement_id` 與目前 API 的 `is_global`、`scope_codes`、`ends_at`、`message`、`internal_note`、version/idempotency 不完全相同。

原始 SQL 也只授權 service_role，沒有 authenticated invoker policies/grants；因此不能直接支援目前 Edge Function 轉送 user JWT 的 RPC 模式。

## 3. 候選資料模型（五表）

| Table | 用途 | 候選核心欄位 |
|---|---|---|
| `private.maintenance_scopes` | 七個範圍目錄 | code PK、label、enabled、sort_order |
| `private.maintenance_events` | 維護事件 | id、title、message、internal_note、is_global、status、starts_at、ends_at、version、created_by、timestamps |
| `private.maintenance_event_scopes` | 事件與範圍關聯 | event_id、scope_code、created_at；複合唯一鍵 |
| `private.maintenance_audit_logs` | 不可由一般管理 API 修改的稽核紀錄 | event_id、admin_id、action、reason、before_data、after_data、created_at |
| `private.maintenance_idempotency` | 寫入請求去重 | actor_id、idempotency_key、request_hash、response_json、created_at；actor/key 唯一 |

候選 scope code（直接取自目前 API/Edge validator）：
`site_core`, `announcements_info`, `events_competitions`, `video_content`, `membership_growth`, `store_support`, `downloads_app`。

### 3.1 與原始四表的明確差異

- singleton `maintenance_state` 不列入此候選模型；全站維護由事件的 `is_global` 表達。這代表原始 SQL 的全站狀態儲存方式被替換，需確認前端是否依賴 singleton。
- 原始 `maintenance_scopes` 是每個事件的 scope rows；新模型將它拆成 scope catalog + event-scope links。
- 新增 version 與 idempotency 儲存。
- 將 `expected_end_at` 對應為 `ends_at` 候選；`actual_started_at`、`actual_ended_at`、`mode`、`background_path`、`announcement_id` 不在目前 API v0.5 的第一版欄位中。不得靜默丟棄既有資料；若未來存在資料，需另訂搬遷映射。
- 原始 SQL scope keys 與 API scope codes 不相同；本提案以 API code 作新系統 canonical 值，不做未經核准的自動 mapping。

## 4. RPC 契約

五個 RPC 保持 Edge Function 現有名稱及單一 JSONB 參數 `p_request`：

1. `public.maintenance_status_public(p_request jsonb)`
2. `public.maintenance_admin_list(p_request jsonb)`
3. `public.maintenance_event_create(p_request jsonb)`
4. `public.maintenance_event_update(p_request jsonb)`
5. `public.maintenance_event_action(p_request jsonb)`

共同要求：
- 明確 `SECURITY INVOKER`、空 search_path、完整限定名稱。
- 新函式先撤銷 `PUBLIC` EXECUTE，再只授權必要角色。
- 管理 RPC 僅供 authenticated；函式內必須從 `auth.uid()` 取得 actor 並呼叫 `public.is_admin()`。
- status RPC 允許 anon/authenticated，但只可讀取公開狀態欄位；anon 的 private schema USAGE、SELECT 與 RLS 範圍必須極小。
- 所有事件寫入、scope links、audit、idempotency 在同一交易內完成。
- create/update/action 必須以資料庫交易鎖保護衝突檢查；不能只在 Edge Function 先查再寫。
- 不接受 request 中的 actor_id、user_id、role 或 is_admin。

## 5. JWT/RLS 權限矩陣（必須實測）

| 身分 | status RPC | admin list | create/update/action | 直接讀寫 private tables |
|---|---|---|---|---|
| anon | 允許公開白名單 | 拒絕 | 拒絕 | 僅 status 必需的受限讀取；不得寫入 |
| authenticated 非管理員 | 允許公開白名單 | 拒絕 | 拒絕 | 不得讀取管理資料或寫入 |
| authenticated 管理員 | 允許公開白名單 | 允許 | 允許 | 僅 invoker RPC 所需最小 grants，RLS 限 admin |
| service_role | 不作為使用者路徑測試替代品 | 不作為使用者路徑測試替代品 | 不作為使用者路徑測試替代品 | 僅限管理/維運用途，不得用來證明 user JWT/RLS 通過 |

注意：SECURITY INVOKER 代表 table privileges 與 RLS 都會影響函式內 SQL。不能只建立 RPC 而不提供必要的最小 table grants；也不能以 service_role 測試結果代替上述三種使用者身分。

## 6. 必須通過的整合測試

### 身分與授權
- 缺少 JWT、無效 JWT、過期 JWT。
- anon 呼叫五個 RPC：只有 status 成功。
- authenticated 非管理員呼叫管理 RPC：全部拒絕。
- admin user JWT 呼叫管理 RPC：成功。
- 偽造 actor_id / role / is_admin 欄位不能提升權限；未知欄位應拒絕。
- audit admin_id 必須等於資料庫的 auth.uid()。

### RLS 與資料揭露
- anon status 只看到目前可公開的事件與 scope；不得看到 internal_note、audit、actor、idempotency。
- 一般 authenticated user 不得直接讀取管理清單、稽核資料或 idempotency。
- anon / 非管理員不能 INSERT/UPDATE/DELETE/TRUNCATE。
- 管理員只能經受控 RPC 做允許的操作；audit 不允許 UPDATE/DELETE。

### 交易、業務規則與併發
- global event 不可帶 scope；local event 至少一個有效 scope。
- global/local 與 local/local 排程衝突規則正確。
- 兩個併發請求不得同時建立互相衝突的事件。
- expected_version 不符回 VERSION_CONFLICT。
- 相同 actor/key + 相同 payload 重送回原結果；相同 key + 不同 payload 回 IDEMPOTENCY_KEY_REUSED。
- 任一寫入步驟失敗，event/scope/audit/idempotency 必須全部 rollback。
- status 使用資料庫時間與半開區間判斷，不依賴用戶端時鐘。

## 7. 執行分層與目前可做範圍

### 可在 GitHub 開發分支完成
- 完成 schema/RPC SQL 草案。
- 完成 Deno unit tests 與 SQL 靜態檢查規則。
- 完成 SQL parser 檢查（若目前免費本機工具可用）。
- 完成測試矩陣與操作說明。
- 對五支 Edge Functions 做契約一致性修正。

### 不能冒充已完成的測試
真實 anon/user/admin JWT、PostgREST、RLS 與併發交易測試，需要隔離 PostgreSQL/Supabase 環境與三種測試身分。若沒有現成免費隔離環境，不建立付費資源、不碰正式資料庫，該層標示 BLOCKED / NOT RUN。

### 明確禁止
- 不對正式 Supabase 執行 DDL/DML。
- 不執行 migration、repair、db push、reset 或 Edge Function deploy。
- 不新增 service_role secrets 或資料庫密碼。
- 不建立額外 Supabase project、付費分支或付費資源。
- 不宣稱未執行的 JWT/RLS 測試通過。
- 完整 PostgreSQL restore test 仍依先前決定跳過，不得標示 PASS。

## 8. 進入 SQL 實作前的阻擋項

1. 方向 B 已選定：新系統以 `is_global` 取代 singleton `maintenance_state`；仍需檢查前端/既有資料是否依賴舊 singleton，並記錄未來搬遷策略。
2. 確認原始 SQL 的 mode/background_path/announcement_id/actual timestamps 是否仍為產品必要欄位。
3. 確認七個 API scope codes 作為 canonical codes。
4. 完成 status anon SELECT grants + RLS 的隔離可行性驗證。
5. 定稿字元長度上限、audit/idempotency 保留期限與已開始事件的更新限制。

在上述阻擋項未定稿前，不應把此候選模型寫成正式 migration。可先撰寫不連接正式資料庫的測試 harness 與靜態檢查。
