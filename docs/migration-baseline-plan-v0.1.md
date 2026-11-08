# Migration 基線整理方案 v0.1

> 分支：feature/maintenance-system
> 審查日期：2026-11-08
> 性質：文件與唯讀盤點；不是 migration，不執行 SQL，不修改正式資料庫。

## 1. 結論

目前正式資料庫已存在多個應用資料表與欄位，但 Supabase migration history 尚不存在／未能列出紀錄；repository 也沒有 `supabase/config.toml`。因此不能直接把現有 migrations 全部 repair 為 applied，也不能直接執行 `db push`。

建議先將「正式資料庫目前實際 schema」視為唯一現況基準，使用 Supabase CLI 的 remote schema pull 工作流程產生 baseline snapshot，經人工比對後再整理舊 migration 檔案與 history。這個流程需要在具備 CLI 的受控本機環境完成；目前 ChatGPT 執行環境未提供 Supabase CLI，因此本輪只完成計畫與遠端唯讀比對。

## 2. Repository Migration 逐檔比對

| 檔案 | 正式資料庫現況比對 | 基線判定 |
|---|---|---|
| `202610310001_app_releases.sql` | app_releases 欄位、版本正整數與唯一限制、created_by FK、RLS 及四個管理／公開 policy 均與遠端相符 | **結構吻合候選**；不能僅憑結構證明歷史上由此檔執行 |
| `26.11.3_calendar_fields.sql` | announcements 四個行事曆欄位、兩個 CHECK、calendar partial index 均與遠端相符 | **結構吻合候選**；不能僅憑結構證明歷史上由此檔執行 |
| `20261031_app_releases.sql` | 遠端沒有 is_latest 欄位與該檔索引；遠端也沒有該檔建立的 is_app_release_admin() | **與目前現況不吻合**；不可標記為已套用，也不可在正式資料庫重跑 |

### 2.1 特別注意

- 前兩個吻合候選只表示目前資料庫物件狀態相符，不代表能證明 SQL 檔案當時確實執行過。
- 第二個 app releases 腳本與第一個重複建立同名資料表，但結構、預設值、policy、索引及管理員函式不同。
- 不應將兩份同名功能的建立腳本同時保留為一般連續 migration 並期待重建結果一致。
- 在檢視 Git 歷史、部署紀錄與實際使用程式碼前，不要刪除或改寫舊檔，以免失去追溯依據。

## 3. 正式資料庫已確認的物件狀態

### app_releases
遠端欄位：
- id uuid
- version_code integer NOT NULL
- version_name text NOT NULL
- release_notes text NOT NULL DEFAULT ''
- apk_url text NOT NULL
- published boolean NOT NULL DEFAULT false
- created_at timestamptz NOT NULL DEFAULT now()
- published_at timestamptz NULL
- created_by uuid NULL REFERENCES auth.users(id)

遠端 constraints：
- primary key(id)
- unique(version_code)
- check(version_code > 0)
- FK(created_by -> auth.users.id)

遠端索引：
- app_releases_pkey
- app_releases_version_code_key

遠端 RLS policies：
- Public can read published app releases
- Admins can read all app releases
- Admins can insert app releases
- Admins can update app releases
- Admins can delete app releases

### announcements calendar
遠端已存在：
- event_date date
- event_end_date date
- event_date_source text
- event_date_confirmed boolean NOT NULL DEFAULT false
- event_date_source check（manual／auto）
- event_date_range check（結束日不可早於開始日）
- announcements_calendar_event_date_idx（published=true 且 event_date_confirmed=true 的 partial index）

以上是唯讀 catalog 查詢結果；未修改資料。

## 4. Migration 基線建議流程

### Phase A — 固定本次盤點快照
1. 在本分支保存本文件與本次 schema 盤點結果。
2. 取得正式資料庫完整 schema snapshot（至少 public；另確認 extensions、auth/storage 自訂物件是否需要納入）。
3. 記錄 Supabase project ref、PostgreSQL 版本、抓取時間及 CLI 版本；不記錄任何連線密碼或 secret。
4. 對 snapshot 做人工 review，避免把 managed schema 或 Supabase 內部物件誤納入應用 migration。

### Phase B — 本機 CLI 基線建立
1. 在使用者可控的本機環境安裝／確認 Supabase CLI 版本。
2. 取得 repository 分支並補齊與專案相符的 `supabase/config.toml`；config 需人工確認，不在本輪猜測建立。
3. 依目前 Supabase 官方流程執行 remote schema pull，產生描述現有遠端結構的 baseline migration。
4. 檢查 pull 結果，特別是 public、extensions、auth/storage 的自訂物件及 RLS policies。
5. 在本機空白測試資料庫測試 baseline 能否重建預期 schema；不得把這一步指向正式資料庫。

### Phase C — 舊 migration 整理
1. 以 schema snapshot 為現況基準。
2. 檢視 Git history／部署紀錄，查明兩個 app_releases migration 的來源與先後。
3. 將 `20261031_app_releases.sql` 判定為歷史衝突檔；確認不再被任何環境使用後，才另開 commit 移出 active migrations 或更名為明確的 archive 文件。
4. 對 `202610310001_app_releases.sql` 與 `26.11.3_calendar_fields.sql`，只有在完整物件比對和歷史證據足夠時，才建立對應的 history repair 計畫。
5. migration repair 只改 history 記錄，不執行 SQL；每筆 repair 都必須先確認現況物件完整吻合。
6. 不要手動建立或更新 `supabase_migrations.schema_migrations`，不要直接 INSERT／DELETE history rows。

### Phase D — 未來維護系統 migration
1. 在 baseline 和既有 migration 衝突解決後，再建立 maintenance migration。
2. 依 Supabase CLI 要求，使用 `supabase migration new <descriptive_name>` 建立正式 migration 檔；不要自行猜時間戳檔名。
3. 只將維護系統新增物件放入新 migration，不混入舊系統修復。
4. 先在本機測試資料庫執行 `supabase db reset`／migration 測試與 advisors。
5. 只有使用者另行明確授權，才討論正式資料庫套用；本方案不包含該授權。

## 5. 本輪已核對／未核對

| 項目 | 結果 |
|---|---|
| Supabase migration list | 空集合 |
| `supabase_migrations.schema_migrations` | 不存在 |
| repository migrations | 3 個 SQL 檔案 |
| repository `supabase/config.toml` | 未找到 |
| app_releases columns / constraints / indexes / policies | 已唯讀核對 |
| announcements calendar columns / constraints / index | 已唯讀核對 |
| 兩份 app_releases SQL 的差異 | 已確認 |
| CLI 可用性 | 目前執行環境未提供 Supabase CLI |
| Git 部署歷史／過往手動執行紀錄 | 尚未確認 |
| 完整 schema snapshot | 尚未產生 |
| history repair | 未執行 |

## 6. 安全界線

- 本輪只執行 SELECT、metadata 讀取與 GitHub 文件新增。
- 沒有執行 DDL／DML。
- 沒有建立 migration history table。
- 沒有執行 `migration repair`、`db push`、`apply_migration`。
- 沒有修改正式資料庫或部署網站。
- 沒有建立 Supabase branch/project，也沒有新增付費資源。
- 不要求使用者提供 DB 密碼、service role key 或其他 secret。

## 7. 下一個可執行步驟

先在 repository 取得完整 migration Git history，並在本機 CLI 可用後做一次 remote schema pull；確認 baseline snapshot 與目前正式 schema 一致後，再提出精確的 migration history repair 對照表。這些工作完成前，維護系統正式 SQL 仍維持 BLOCKED。
