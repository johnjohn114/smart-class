# Smart Class 免費本機 Schema 驗證流程

此流程不修改正式資料庫，不執行 db push、migration repair 或 linked reset，也不建立付費資源。

## 靜態檢查（不需 Docker / CLI）
在 repo 根目錄：
```powershell
python .\\scripts\\verify_schema_snapshot.py .\\docs\\schema-snapshots
python -m unittest discover -s .\\tests -v
```
這只檢查快照文字中的物件數量，不代表 SQL 可執行或可還原。

## Windows 本機準備
需安裝 Supabase CLI 與 Docker Desktop（或相容容器環境）。官方 Scoop 安裝：
```powershell
scoop bucket add supabase https://github.com/supabase/scoop-bucket.git
scoop install supabase
supabase --version
docker version
```

先查看命令參數，不要直接 repair 或 reset：
```powershell
supabase --help
supabase db dump --help
supabase db pull --help
supabase migration list --help
supabase migration repair --help
```

待審查 CLI 版本及 flags 後，才可在使用者控制的本機終端登入與 link：
```powershell
supabase login
supabase link --project-ref fsoowongtavlsrwvzbze
```
密碼只輸入 CLI 本機提示，不要貼到聊天或 GitHub。

正式 schema-only dump 命令須先依實際 CLI help 確認。預定目標是只讀匯出 schema 到本機檔案；不含資料、不執行 push。匯出後必須檢查檔案內容，再於未 link 正式專案的獨立本機 Supabase 環境還原。

**嚴禁**在已 link 正式專案的目錄執行 `supabase db reset --linked`。空白資料庫還原只能在獨立、未 link 的本機測試環境執行。

## 完成標準
CLI dump 成功、無資料列或 secrets、獨立本機重建成功，並比對 tables/views/functions/triggers/indexes/constraints/RLS/ACL。全部通過前不可標記 baseline ready。


## SQL 相依性檢查（新增）

最新工具已新增 `scripts/verify_schema_dependencies.py`、`tests/test_verify_schema_dependencies.py` 與 `docs/maintenance-local-dependency-check-v0.1.md`。請從最新分支 ZIP 將這三個檔案放入本機對應資料夾，再依該文件執行檢查。此工具只讀本機快照，不連線或修改 Supabase。
