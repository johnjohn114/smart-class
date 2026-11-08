# Maintenance 本機整合驗證流程 v0.1

> 僅在本機 repository 執行；不連線 Supabase、不執行 SQL、不部署 Edge Functions，也不需要付費資源。

## Windows PowerShell（整批執行）

先在 smart-class repository 根目錄開啟 PowerShell，貼上以下整段：

```powershell
$ErrorActionPreference = "Stop"

$branch = (git branch --show-current).Trim()
if ($branch -ne "feature/maintenance-system") {
  throw "目前分支是 '$branch'；請先切換到 feature/maintenance-system，再重新執行。"
}

git pull --ff-only origin feature/maintenance-system
if ($LASTEXITCODE -ne 0) { throw "git pull 失敗，停止驗證。" }

python -m unittest tests.test_verify_maintenance_sql_draft tests.test_verify_schema_snapshot tests.test_verify_schema_dependencies
if ($LASTEXITCODE -ne 0) { throw "Python unit tests 失敗。" }

python scripts/verify_maintenance_sql_draft.py
if ($LASTEXITCODE -ne 0) { throw "Maintenance SQL static checker 失敗。" }

# pglast 已安裝才解析 SQL；不自動安裝套件。
python -c "import importlib.util,sys; sys.exit(0 if importlib.util.find_spec('pglast') else 3)"
if ($LASTEXITCODE -eq 0) {
  python -c "from pathlib import Path; from pglast import parse_sql; files=[Path('supabase/sql/maintenance-private-schema-rpc-draft-v0.1.sql'), *sorted(Path('docs/schema-snapshots').glob('*.sql'))]; [(parse_sql(p.read_text(encoding='utf-8')), print('PASS:', p)) for p in files]; print('Parsed SQL files:', len(files))"
  if ($LASTEXITCODE -ne 0) { throw "pglast SQL parsing 失敗。" }
} else {
  Write-Warning "未安裝 pglast：略過 PostgreSQL syntax parse；不會自動安裝。"
}

if (Get-Command deno -ErrorAction SilentlyContinue) {
  deno test supabase/tests/functions/maintenance-validation.test.ts
  if ($LASTEXITCODE -ne 0) { throw "Deno Edge validation tests 失敗。" }
} else {
  Write-Warning "找不到 Deno：略過 Edge validation tests；不會自動安裝。"
}

Write-Host "本機可執行驗證流程結束。請保留完整輸出。"
```

## 結果回報

請貼回整段輸出，尤其是：
- Python unit tests 的總測試數與 PASS/FAIL。
- SQL static checker 的 JSON 結果。
- pglast 是否執行，以及解析檔案數。
- Deno 是否執行，以及測試數與結果。

## 驗證界線

- Python tests 與 static checker 只驗證本機程式／靜態規則。
- pglast 只驗證 SQL 語法可解析，不代表 SQL 能成功套用或權限正確。
- Deno tests 只驗證 Edge Function request validation，不代表 Edge Function 已部署。
- 本流程不包含真實 JWT、PostgREST、RLS、交易併發或正式 Supabase 測試。
- 不執行 migration、DDL/DML、db push、db reset、migration repair 或 deployment。
