# Smart Class SQL 相依性檢查工具 v0.1

## 用途

在本機靜態檢查 docs/schema-snapshots 內的 SQL 快照，找出部分明確可判定的物件相依性問題。

檢查範圍：
- 六個 SQL 快照是否都存在且可由 pglast 解析。
- 盤點 public 資料表、View、函數及 Trigger 數量。
- 資料表外鍵指向的 public／未限定 schema 目標是否存在於快照。
- View 的資料表／View 來源是否存在。
- 函數本文中明確寫成 public.object 的資料表參照是否存在；同時統計能對應到快照的未限定名稱。
- Trigger 的目標資料表與執行函數是否存在。

## 執行方式（Windows PowerShell）

在 maintenance-local-kit 或完整 repo 根目錄執行：

```powershell
.\.venv\Scripts\python.exe .\scripts\verify_schema_dependencies.py .\docs\schema-snapshots
```

執行單元測試：

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s .\tests -v
```

## 判讀限制

這是保守的靜態檢查，不會執行 SQL，也不會連線到 Supabase。

- PL/pgSQL 函數本文對外層 SQL parser 而言是字串；工具只做有限的文字參照掃描。
- 函數本文中未限定 schema 的名稱，可能是 public 資料表、CTE、區域變數、暫存物件或其他 search_path 物件；未知名稱不會直接判定為缺失。
- 不完整快照可能未包含 extension、auth/storage schema、role、sequence ownership、function ACL、動態 SQL 或其他外部相依性。
- PASS 不代表完整 dependency graph、權限正確、SQL 可成功執行或可還原。

## 安全界線

本工具只讀取本機 SQL 檔案，不會執行 SQL、不會呼叫 Supabase、不會修改資料庫、不需要 Docker、Supabase CLI 或付費資源。
