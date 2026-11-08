> **已被 v0.4 取代（2026-11-08）**：本文件第 2、3、8、10 節所述的 SUPABASE_DB_URL + Postgres driver、直接連線及 grants 方案已不再採用。最新連線決策請看 [maintenance-connection-architecture-v0.4.md](./maintenance-connection-architecture-v0.4.md)。請勿依本文件 v0.3 的連線段落生成 SQL。欄位與事件規則仍是設計參考，待整合更新。

# 維護系統資料庫設計 v0.3（安全審核修正版）

> 依 2026-11-08 唯讀審核結果修正。
> 本文件是 migration 前設計，不是 SQL Migration。
> 沒有修改正式 Supabase 資料庫。

## 1. 已確認的產品規則

七個 scope：
- `site_core` — 網站核心
- `announcements_info` — 公告與資訊
- `events_competitions` — 活動與比賽
- `video_content` — 影音內容
- `membership_growth` — 會員與成長
- `store_support` — 商城與客服
- `downloads_app` — 下載與 App

全站維護使用 `maintenance_events.is_global`，不屬於第八個 scope。
全站維護期間管理員仍可登入及使用管理後台。

## 2. 資料庫 schema 與存取方式

目前 Supabase schema 清單尚無 `private` schema；Migration 需要建立它。

維護資料表全部放入 `private`：
- `private.maintenance_scopes`
- `private.maintenance_events`
- `private.maintenance_event_scopes`
- `private.maintenance_audit_logs`
- `private.maintenance_idempotency`

不將 `private` 加入 Data API Exposed schemas；不授予 anon/authenticated 直接讀寫權限。所有表仍啟用 RLS 作縱深防禦，並撤銷 PUBLIC、anon、authenticated 對維護表的直接權限。

Edge Functions 透過伺服器端 `SUPABASE_DB_URL` 與 Postgres driver 存取 private schema；不使用前端 Data API 存取 private 表。連線依 Supabase Edge／serverless 建議採 transaction pooler，連線池限制 1、關閉 prepared statements、要求 SSL。DB URL 僅存伺服器端環境變數，不進 Git、不回傳前端。

資料庫交易函式採固定名稱與固定參數；Edge Function 不接受任意 SQL、不拼接使用者提供的 SQL。查詢使用參數化語句。

## 3. 管理員授權

現有 `public.profiles.role` 是資料庫角色來源。現有 `public.is_admin()` 會檢查 `auth.uid()` 對應 profile 的 role 是否 admin，並已限制為 authenticated/service_role/postgres 可執行、search_path 為空。

新管理 Edge Functions：
1. `verify_jwt = true`。
2. 以呼叫者 JWT 呼叫 `auth.getUser()` 取得真實 user。
3. 使用同一 JWT 呼叫 `public.is_admin()`。
4. 驗證成功才執行管理操作。
5. audit actor_id 取自驗證後的 user.id。

不採用 `is_admin_user()`（anon 也有 EXECUTE），也不採用 `ADMIN_EMAIL` 作為新系統的角色來源。不得信任前端 role、isAdmin、actor_id 或 email。

## 4. 資料表欄位

### A. `private.maintenance_scopes`

- `id uuid PRIMARY KEY DEFAULT gen_random_uuid()`
- `code text UNIQUE NOT NULL`
- `name text NOT NULL`
- `description text`
- `sort_order integer NOT NULL DEFAULT 0`
- `enabled boolean NOT NULL DEFAULT true`
- `created_at timestamptz NOT NULL DEFAULT now()`
- `updated_at timestamptz NOT NULL DEFAULT now()`

Seed 七個 scope code。停用 scope 只阻止建立新事件，不會自動取消已存在事件。全站維護不在此表。

### B. `private.maintenance_events`

- `id uuid PRIMARY KEY DEFAULT gen_random_uuid()`
- `title text NOT NULL`
- `message text NOT NULL`
- `internal_note text`
- `is_global boolean NOT NULL DEFAULT false`
- `status text NOT NULL CHECK (status IN ('draft','scheduled','cancelled','completed'))`
- `starts_at timestamptz NOT NULL`
- `ends_at timestamptz NOT NULL`
- `version integer NOT NULL DEFAULT 1 CHECK (version >= 1)`
- `created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL`
- `updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL`
- `created_at timestamptz NOT NULL DEFAULT now()`
- `updated_at timestamptz NOT NULL DEFAULT now()`
- `cancelled_at timestamptz`
- `completed_at timestamptz`
- CHECK：`starts_at < ends_at`

事件不提供一般硬刪除；以 cancelled／completed 保留歷史。若未來確有刪除需求，需另訂資料保留與稽核政策。

### C. `private.maintenance_event_scopes`

- `event_id uuid NOT NULL REFERENCES private.maintenance_events(id) ON DELETE CASCADE`
- `scope_id uuid NOT NULL REFERENCES private.maintenance_scopes(id) ON DELETE RESTRICT`
- `created_at timestamptz NOT NULL DEFAULT now()`
- PRIMARY KEY：`(event_id, scope_id)`

跨表規則由單一受控交易函式檢查：
- `is_global=true` 時不得有 scope 關聯。
- `is_global=false` 時至少有一個已啟用 scope。
- 不允許全站與局部範圍混在同一事件。

### D. `private.maintenance_audit_logs`

- `id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY`
- `event_id uuid REFERENCES private.maintenance_events(id) ON DELETE SET NULL`
- `actor_id uuid REFERENCES auth.users(id) ON DELETE SET NULL`
- `action text NOT NULL`
- `before_data jsonb`
- `after_data jsonb`
- `reason text`
- `request_id uuid NOT NULL`
- `created_at timestamptz NOT NULL DEFAULT now()`

audit 只追加、不提供一般 UPDATE／DELETE。FK 採 SET NULL，避免使用者或事件刪除時破壞歷史紀錄。實務上事件以取消／完成保留，不硬刪除。

### E. `private.maintenance_idempotency`

- `actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE`
- `idempotency_key uuid NOT NULL`
- `operation text NOT NULL`
- `request_hash text NOT NULL`
- `response_data jsonb`
- `created_at timestamptz NOT NULL DEFAULT now()`
- `expires_at timestamptz NOT NULL`
- PRIMARY KEY：`(actor_id, idempotency_key)`

同一 actor/key/payload 重送回傳既有結果；同 key 不同 payload 回傳 409。hash 由伺服器端對正規化輸入計算，不接受用戶端自報 hash。過期資料先以查詢忽略；清理機制另行選擇，不預設新增 pg_cron 工作。

## 5. 排程交易

所有排程建立、修改、排程啟用與 action 都走相同交易流程：

1. 驗證輸入與 expected_version。
2. 開始 DB transaction。
3. 取得固定的 `pg_advisory_xact_lock`（transaction-scoped）。
4. 檢查 idempotency key。
5. 驗證事件 status、scope、is_global 與時間。
6. 檢查排程衝突。
7. 寫入 event 與 event_scopes。
8. 寫入 audit log。
9. 寫入 idempotency response。
10. commit；任一步失敗 rollback。

時間採半開區間 `[starts_at, ends_at)`，重疊判斷：
`existing.starts_at < requested.ends_at AND requested.starts_at < existing.ends_at`。

衝突：
- 全站與任何全站／局部事件重疊皆衝突。
- 局部事件只有在 scope 交集非空且時間重疊時衝突。
- draft 不佔用時段；scheduled 佔用時段。
- cancelled／completed 不佔用時段。

不可只在 Edge Function 做 SELECT 後再 INSERT；鎖、檢查與寫入必須在同一 DB transaction。

## 6. 狀態與時間

- 狀態初步採 draft → scheduled → cancelled／completed。
- scheduled 是否正在生效由伺服器時間與 starts_at／ends_at 計算，不另外存一個可手動修改的 active 狀態。
- 自然到期不需要 pg_cron 才能停止顯示維護；狀態 API 依時間窗判斷即可。
- 是否自動將到期事件改成 completed，暫不做自動更新；管理端可在後續操作中封存，避免為此增加背景排程。
- 管理端顯示／輸入 Asia/Taipei；DB timestamptz；API ISO 8601。

## 7. 索引

- `maintenance_events(status, starts_at, ends_at)`
- `maintenance_event_scopes(scope_id, event_id)`
- `maintenance_audit_logs(event_id, created_at DESC)`
- `maintenance_audit_logs(actor_id, created_at DESC)`
- `maintenance_idempotency(expires_at)`

scope.code UNIQUE 已提供索引。最終索引依實際查詢計畫檢查，不重複建立相同索引。

## 8. Edge Functions 對應

| Function | JWT | 用途 |
|---|---|---|
| `maintenance-status` | false；可選驗證 bearer token 以判斷 admin bypass | 公開唯讀，僅回傳白名單欄位 |
| `maintenance-admin-list` | true | admin only |
| `maintenance-event-create` | true | admin only |
| `maintenance-event-update` | true | admin only |
| `maintenance-event-action` | true | admin only |

所有函式只在伺服器端使用 SUPABASE_DB_URL；不得將 DB URL、資料庫密碼或高權限金鑰傳給瀏覽器。

## 9. 管理員 bypass 行為

- 全站維護畫面不可阻擋 `admin.html`、登入頁、Auth callback 或必要 Auth API。
- 管理員需先完成登入，再經 `is_admin()` 確認。
- bypass 只略過前端維護遮罩，不略過管理 API 的 JWT／admin 驗證。
- Auth 本身故障時無法保證登入，另訂緊急復原方式，不提供公開後門。

## 10. Migration 前的檢查清單

- 確認 SUPABASE_DB_URL 在 Edge Function 環境可用且連線模式適合 serverless；不輸出秘密值。
- 確認 Postgres driver 版本固定、lockfile 可追蹤。
- 確認 private schema 未列入 Data API Exposed schemas。
- 確認 RLS、schema grants、table grants 與 function execute 權限。
- 確認 transaction-scoped advisory lock 在實際使用的連線模式中有效。
- 確認七個 scope seed、狀態機與每個頁面的 scope mapping。
- 在本地／隔離測試環境跑 migration 與 pgTAP／整合測試。
- 執行 advisors，再審查 Migration；不可直接套用正式資料庫。

## 11. 本版結論

已修正 v0.2 中管理員授權來源不一致、private schema 存取方式不明、audit FK 不完整及 transaction lock 描述不足等問題。建議 private schema + server-side Postgres driver + JWT/is_admin 驗證。

此文件仍未成為 Migration；未修改正式 Supabase 資料庫。
