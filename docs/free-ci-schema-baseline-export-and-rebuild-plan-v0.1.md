# 免費 CI：正式 Schema 匯出與重建驗證方案 v0.1

> 日期：2026-11-25（Asia/Taipei）  
> 專案：`johnjohn114/smart-class`  
> Supabase project ref：`fsoowongtavlsrwvzbze`  
> PR：#34（Draft；未合併）  
> 狀態：可行性與執行設計；**目前尚未執行正式匯出或重建**。

## 1. 結論先行

可以使用 GitHub Actions 的免費 CI runner 與 PostgreSQL 17 容器執行**離線重建驗證**，不必建立 Supabase paid branch，也不必新增付費服務。

但免費 CI runner 本身不能憑空讀取正式 Supabase 資料庫。要取得真正的 `pg_dump --schema-only`，仍需要一條已授權的資料庫連線或 Supabase CLI 可用的正式匯出途徑。

目前使用者已明確表示不重設資料庫密碼；而現有 Supabase MCP 能查詢目錄與執行 SQL，沒有提供完整 schema dump 檔案的匯出工具。故目前**不能安全地把正式 DB dump 自動送進 GitHub Actions**。不應為了自動化而要求重設密碼、建立新的正式資料庫角色、把憑證放入 GitHub Secrets，或開啟付費分支。

建議分成兩段：
1. 先在免費 CI 建好「只接受已核准 schema-only dump」的離線驗證流程。
2. 等將來存在不需重設密碼、且獲授權的匯出途徑時，再將正式 dump 作為受控輸入；在此之前 CI 只能驗證現有參考快照，不能宣稱重建正式 baseline。

## 2. 目前已知資料與差異

### 2.1 2026-11-25 正式目錄唯讀盤點

- PostgreSQL 17.11。
- 44 張 `public` tables、412 個欄位、1 個 view。
- 98 條 public RLS policies。
- 38 個 public functions、7 個 public user triggers。
- public tables 全部啟用 RLS；目前沒有 public table 啟用 FORCE RLS。
- migration 清單為空，標準 `supabase_migrations.schema_migrations` 不存在。
- 完整 schema-only dump 尚未取得。

### 2.2 現有 2026-11-08 參考快照

`docs/schema-snapshots/README.md` 已明確聲明：這些檔案由 catalog 唯讀查詢整理，**不是 pg_dump，也不是可直接還原的完整 baseline**。

快照文件記錄 420 個 public columns；2026-11-25 最新目錄查詢是 412 個，已有 8 欄差異。快照也缺少完整的 Auth/Storage/Realtime/Vault 管理 schema、object ownership、完整 ACL/default ACL、sequence current values、view options、完整 dependency order 等必要項目。

因此，現有快照只能作為人工比對材料，不能拿來當作重建輸入。

## 3. 免費 CI 能做什麼

GitHub Actions runner 可使用免費額度內的 Ubuntu runner，啟動一次性 PostgreSQL 17 service/container。工作完成後整個 CI 資料庫即丟棄。

建議離線驗證工作分成：

| 工作 | 工具 | 目的 |
|---|---|---|
| 輸入完整性檢查 | SHA-256、檔案清單、來源 manifest | 確認 dump 未缺檔、未被意外替換 |
| SQL 語法解析 | PostgreSQL 17、`psql` | 在空白 disposable DB 執行 schema-only SQL |
| 依賴重建 | `pg_dump` 產生的完整排序 SQL | 驗證 tables、types、functions、views、triggers 等建立順序 |
| 結構比對 | catalog SQL + `pg_dump --schema-only` | 比對物件、欄位、constraints、indexes、policies、owners、ACL |
| 第二次重播 | 同一份 dump 在另一個全新 DB 執行 | 確認結果可重複、不是依賴舊資料庫狀態 |
| migration replay | 已核准的 repository migration sequence | 只有在 migration history 被證實後才執行 |
| 報告 | GitHub Actions job summary | 輸出成功/失敗、物件數、差異摘要；不輸出憑證或資料列 |

### 重要限制

- CI 不應連接 production 做寫入測試。
- CI 不需要任何 production 使用者資料列；只處理 schema-only SQL。
- 不應把正式資料庫密碼、service_role key、JWT secret 或其他憑證寫入 workflow、log、artifact 或 repository。
- 不應在 PR workflow 自動下載或執行來路不明的 SQL。
- 若 dump 內含敏感函式內容或內部結構，artifact 必須限制存取與保留時間；不可假設 GitHub Actions artifact 一定適合公開儲存。

## 4. 正式 dump 的可行取得方式與目前狀態

| 途徑 | 是否可行 | 本專案目前狀態 |
|---|---|---|
| Supabase CLI `db dump --schema-only` | 官方 CLI 可輸出 schema-only SQL；通常仍需要可用的 DB 連線憑證 | 目前執行環境沒有 CLI/pg_dump；使用者已明確不重設 DB 密碼 |
| 本機 `pg_dump --schema-only` | 可直接產生完整 schema-only SQL；需要資料庫連線 | 同樣需要可用連線；目前未具備 |
| Supabase MCP catalog 查詢 | 可取得很多 catalog 資訊，適合唯讀盤點 | 不能直接輸出完整可還原 dump；不能替代 pg_dump |
| Supabase SQL Editor 手動查詢 | 可補充個別目錄資訊 | 仍不是完整、排序正確、可還原的 pg_dump |
| 建立新的 read-only DB role | 技術上可提供最小權限連線，但需要正式 DB DDL 與新憑證 | 未獲授權；不執行 |
| Supabase paid branch | 可提供隔離測試資料庫 | 使用者要求免費方案；不建立 |

**目前選擇：不要求任何密碼、不重設密碼、不建立新 DB role、不建立 paid branch。** 正式匯出保持待辦，直到有已授權且不違反上述限制的連線方式。

## 5. 建議的 CI workflow 設計

建議新增一個手動觸發 workflow，例如 `.github/workflows/schema-baseline-rebuild.yml`，但只有在受控 schema-only dump 的交付方式確定後才啟用正式重建 job。

### Job A — Reference snapshot audit（可先執行）

1. Checkout repository。
2. 執行 `scripts/verify_schema_snapshot.py`。
3. 執行 `scripts/verify_schema_dependencies.py`（安裝固定版本的 pglast）。
4. 將結果標示為「reference snapshot static checks」，不可標示為「production restore passed」。
5. 若參考快照統計與最新目錄盤點不一致，CI 顯示 drift warning，不自動覆寫快照。

### Job B — Schema-only restore（等待正式 dump）

1. 只接受經核准的 schema-only dump 輸入。
2. 驗證 manifest、SHA-256、來源時間、PostgreSQL major version。
3. 啟動乾淨 PostgreSQL 17 容器。
4. 使用 `psql -v ON_ERROR_STOP=1` 執行 dump。
5. 若 dump 需要 Supabase managed roles/extensions，先在測試容器建立與正式環境相容的必要角色/extension stub；不能將 stub 當作完整 Supabase managed service replay。
6. 再啟動第二個全新 PostgreSQL 17 容器，重播一次。
7. 比較兩次 catalog 輸出，確保重建結果一致。
8. 輸出 summary，不上傳未經核准的 SQL dump。

### Job C — Repository migration replay（最後才執行）

只有在正式 migration history 的權威來源已釐清後才啟用：
1. 在乾淨 DB 重播確認過的歷史 baseline。
2. 依時間順序逐份套用唯一有效的 migration。
3. 對照每份 migration 的預期變更。
4. 檢查 Migration A/B 衝突、Growth hardening、Default Privileges hardening 的順序與重複執行風險。
5. 最後才將 Maintenance final migration 加入測試；目前的 Maintenance SQL 仍是 development draft，不可列入正式 migration replay。

## 6. 不可採用的捷徑

- 不使用 `supabase db pull --remote` 來假裝只讀匯出；此命令可能更新 remote migration history。
- 不執行 `db push`、`db reset` 或 migration repair。
- 不手動建立 `supabase_migrations` ledger 或填入猜測的時間戳。
- 不將 2026-11-08 的 catalog 快照標記為完整 baseline。
- 不以成功解析 SQL 取代 PostgreSQL 真正 restore。
- 不將 Supabase Auth/Storage/Realtime 內部 migration ledger 當成 app schema migration history。
- 不在正式 DB 建立角色、改權限或改 schema 以方便 CI。
- 不要求使用者重設資料庫密碼。

## 7. 下一步建議

**先執行 Job A 的參考快照靜態稽核，並建立 workflow 的安全骨架；Job B 保持停用，直到取得合法的 schema-only dump。**

本文件不授權正式資料庫操作，也不代表正式 baseline 已建立。任何連線方式、憑證管理或 production DDL 都需要另行審核與明確授權。
