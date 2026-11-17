# Migration History 修復對照表與執行策略 v0.2

> 日期：2026-11-08
> 專案：smart-class / fsoowongtavlsrwvzbze
> 性質：只讀核對及程序決策；未執行 migration repair。

## 1. 現況

- Supabase migration list 回傳空集合。
- supabase_migrations.schema_migrations 在目前資料庫不存在。
- Repository 有三個既有 migration SQL。
- GitHub commit history 只能證明檔案進入版本庫的時間，不能證明 SQL 已在正式資料庫執行。
- 正式資料庫現況與其中兩個 SQL 的部分／主要物件吻合，但這不足以安全標記 applied。

## 2. 逐檔對照

| Migration | Git 來源 | 正式 DB 物件比對 | 決策 |
|---|---|---|---|
| 20261031_app_releases.sql | 2026-10-31 06:05:23 UTC，commit fb0b6b1a94821fbe384c9db391c3ae3b95741c19 | 不吻合：遠端缺 is_latest、對應索引及 is_app_release_admin() | 不可 repair 為 applied；保留歷史檔案，待封存 |
| 202610310001_app_releases.sql | 2026-10-31 06:06:00 UTC，commit 0573e012bba978acd158d6c48643976c4c9f6da9 | app_releases 欄位、約束、索引、RLS policies 目前相符 | 候選吻合，但缺完整證據；暫不 repair |
| 26.11.3_calendar_fields.sql | 2026-11-01 合併提交 929cd3564e1a6e4d6d2fae7fe0b897f876699ac7 | announcements calendar 欄位、check constraints、partial index 目前相符 | 候選吻合，但缺完整證據；暫不 repair |

## 3. 為何現在不能執行 repair

1. History table 不存在；CLI 可能需要先初始化或按版本採取特定程序，不能假設直接 repair 可用。
2. 兩個 app_releases 腳本衝突；若把舊檔標記 applied，會造成重建環境與正式環境結構不一致。
3. 結構吻合不代表執行來源與執行時間已證實。
4. 尚未有完整 pg_dump／CLI pull 的 schema snapshot，也沒有所有物件的完整比對。
5. 尚未查到 Dashboard SQL Editor 執行紀錄或正式部署紀錄。

## 4. 建議基線程序

### Phase A：凍結歷史
- 不改寫既有 SQL 內容。
- 先將三份檔案及其 Git commit 保留。
- 不以 Git commit timestamp 當 applied timestamp。

### Phase B：建立正式 baseline snapshot
- 在具備 Supabase CLI 的受控本機環境，確認 CLI 版本及該版本 db pull --help。
- 先 link 專案，再按官方 remote schema pull 流程匯出現有遠端 schema。
- 不匯出使用者資料，不把密碼或 access token 放入 Git。
- 檢查 snapshot 是否包含 public 自訂 objects、extensions、自訂 auth/storage objects；排除 Supabase managed system objects。
- 在空白本機 DB 執行 reset，驗證可重建。
- 目前 ChatGPT 執行環境沒有 supabase CLI、psql、pg_dump，故這步尚未完成。

### Phase C：處理 migration history
- 先確認 Supabase CLI 版本、history table 初始化狀態與 migration repair --help。
- 不手動建立／更新 supabase_migrations.schema_migrations。
- 只有在完整 schema snapshot 與部署證據足夠時，才提出精確的 history repair 命令。
- 對衝突檔 20261031_app_releases.sql 不標記 applied；待查明是否任何環境曾使用，再從 active migration chain 移除或改名封存。
- 對兩個吻合候選，在未取得執行證據前仍保持未確認；若採 snapshot baseline，需由 CLI 官方流程建立新的 baseline history，不可假造舊 migration 的執行日期。

### Phase D：新功能
- baseline 可重建且 migration history 一致後，再以 supabase migration new <name> 建立維護系統 migration。
- 不把維護系統 DDL 混進 baseline snapshot。
- 先在本機測試，再另行討論正式套用。

## 5. 本輪未執行

- 沒有 migration repair。
- 沒有 db pull、db push、db reset。
- 沒有手動建立 migration history table。
- 沒有修改任何正式 schema 或資料。
- 沒有建立 Supabase project／branch 或付費資源。
