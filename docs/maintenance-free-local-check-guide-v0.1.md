# Maintenance System 免費本機檢查指南 v0.1

> 適用分支：`feature/maintenance-system`
> 目的：不連線正式 Supabase、不執行 SQL、不部署，先做本機靜態與語法檢查。

## 1. 需要的工具

必需：
- Python 3（建議 3.10 或更新版本）。
- Node.js（只用來檢查瀏覽器 JavaScript 語法）。

可選：
- Deno（只用來檢查 Edge Functions TypeScript）。

本輪維護系統的 Python 靜態測試只使用 Python 標準函式庫，不需要 `pip install` 或 `npm install`。沒有 `package.json`，不需要安裝前端套件。

## 2. Windows PowerShell：維護系統 Python 檢查

先在 PowerShell 切換到專案根目錄（包含 `maintenance-client.js`、`scripts`、`tests` 的資料夾），再執行：

```powershell
py --version
py -m unittest discover -s tests -p "test_verify_maintenance_sql_draft.py" -v
py scripts/verify_maintenance_sql_draft.py
```

預期：
- 單元測試全部顯示 `ok`，最後為 `OK`。
- SQL 靜態檢查顯示 `failed: []` 且結束碼為 0。

若電腦沒有 `py` 指令，可將 `py` 改成 `python`。

## 3. JavaScript 語法檢查

確認已安裝 Node.js 後，在專案根目錄執行：

```powershell
node --version
node --check maintenance-client.js
node --check admin.js
node --check app.js
```

`node --check` 只解析語法，不會執行網頁程式，也不會連線 Supabase。

## 4. 可選：Edge Functions TypeScript 檢查

若已安裝 Deno，執行：

```powershell
deno --version
deno check supabase/functions/_shared/maintenance.ts supabase/functions/maintenance-status/index.ts supabase/functions/maintenance-admin-list/index.ts supabase/functions/maintenance-event-create/index.ts supabase/functions/maintenance-event-update/index.ts supabase/functions/maintenance-event-action/index.ts
```

這是型別／模組檢查，不會部署 Edge Functions。若 Deno 需要下載快取依賴，先確認網路及下載提示；不要提供 Supabase service-role key 或其他秘密。

## 5. 本輪刻意不做的事

- 不執行 maintenance SQL 草案或任何 migration。
- 不連線正式 Supabase，不查詢或修改正式資料。
- 不建立本機 Supabase Docker stack。
- 不執行 PostgreSQL restore test。
- 不部署 Edge Functions 或 GitHub Pages。
- 不安裝付費工具、不新增付費資源。

## 6. 檢查能力界線

Python 靜態檢查只檢查已列出的文字規則，不是 PostgreSQL parser。JavaScript `--check` 不代表瀏覽器功能測試；Deno `check` 不代表 Edge Function 已部署或能成功呼叫資料庫。

完成以上本機檢查後，仍須另行安排隔離環境的 PostgreSQL／JWT／RLS 整合驗證，才可考慮正式 migration。任何正式 Supabase 操作都需要另行確認。
