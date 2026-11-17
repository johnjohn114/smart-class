# 維護系統 API 規格草案 v0.1

> 狀態：待資料表與既有 Edge Function 程式核對；本文件是功能契約草案，不代表已完成實作或可部署。
> 目標：第二階段維護系統後端。前端不得直接寫入維護事件或稽核紀錄。

## 1. 共通規則

- 五支 Supabase Edge Functions：`maintenance-status`、`maintenance-admin-list`、`maintenance-event-create`、`maintenance-event-update`、`maintenance-event-action`。
- 管理端請求必須帶有效登入 JWT，並由伺服器端重新驗證管理員身分；不可只相信前端傳入的 role、user id 或 isAdmin。
- `maintenance-status` 僅回傳前台顯示所需資訊，不回傳管理員資料、內部備註或稽核內容。
- 所有輸入均須驗證型別、必填欄位、長度、日期格式及允許值；未知欄位不應被直接寫入資料庫。
- 回應採 JSON。成功回應使用 `{ "ok": true, "data": ... }`；錯誤使用 `{ "ok": false, "error": { "code": "...", "message": "..." } }`。
- 時間在 API 傳輸時使用 ISO 8601；資料庫實際欄位型別及時區策略待核對後定稿。

## 2. API 契約

### A. `maintenance-status`

- 語意：讀取目前生效及即將生效的維護狀態。
- 權限：公開讀取；只回傳前台必要欄位。
- 輸入：無必要 body；可選擇性接受查詢時間，但伺服器不得信任任意未驗證的時間值作為授權依據。
- 成功資料草案：
  - `is_maintenance`
  - `scope` 或作用範圍清單
  - `title`、`message`
  - `starts_at`、`ends_at`
  - `updated_at`
- 規則：依伺服器時間判定生效；過期事件不得繼續被視為目前維護。是否回傳排程中的未來事件，需依前端需求確認。

### B. `maintenance-admin-list`

- 語意：管理員查詢維護事件清單。
- 權限：管理員 JWT；伺服器端驗證管理員。
- 輸入草案：`status`、`scope`、`from`、`to`、`limit`、`cursor`。
- 規則：限制單次筆數並使用穩定排序；不得讓一般登入者藉由參數取得管理清單。
- 成功資料：事件清單及分頁資訊；內部備註是否顯示，需依管理端 UI 權限確認。

### C. `maintenance-event-create`

- 語意：建立新的維護事件。
- 權限：管理員 JWT；伺服器端驗證管理員。
- 輸入欄位草案：標題、訊息、作用範圍、開始時間、結束時間，以及必要的管理端備註。
- 規則：
  1. 驗證開始時間早於結束時間。
  2. 驗證作用範圍屬於系統允許的七個維護範圍。
  3. 建立事件與稽核紀錄必須具備一致性；若其中一項失敗，不可留下半套資料。
  4. 排程衝突規則待定稿，不可只靠前端檢查。
- 成功資料：新事件識別碼及建立後事件摘要。

### D. `maintenance-event-update`

- 語意：修改尚允許編輯的維護事件。
- 權限：管理員 JWT；伺服器端驗證管理員。
- 輸入草案：事件識別碼及允許修改的欄位。
- 規則：
  1. 只接受白名單欄位。
  2. 重新驗證時間區間與作用範圍。
  3. 使用版本欄位或等效方式防止管理員互相覆蓋更新。
  4. 更新內容與稽核紀錄應在同一交易內完成。
- 成功資料：更新後事件摘要及新版本資訊。

### E. `maintenance-event-action`

- 語意：執行事件生命週期動作，例如啟用、取消、完成或其他經核准的動作。
- 權限：管理員 JWT；伺服器端驗證管理員。
- 輸入草案：事件識別碼、動作名稱、必要的原因或備註。
- 規則：動作名稱採白名單；依目前事件狀態檢查是否允許轉換；重複送出相同動作須安全處理；每次成功動作都留下稽核紀錄。
- 成功資料：更新後狀態及動作結果。
- 最終允許的狀態轉換表尚待確認，不在本草案自行定義。

## 3. 共通錯誤碼

| HTTP | 錯誤碼 | 意義 |
|---|---|---|
| 400 | INVALID_REQUEST | 請求格式錯誤 |
| 401 | UNAUTHENTICATED | 未登入或 JWT 無效 |
| 403 | FORBIDDEN | 非管理員或無權執行 |
| 404 | NOT_FOUND | 事件不存在 |
| 409 | CONFLICT | 排程重疊、狀態衝突或版本已更新 |
| 422 | VALIDATION_ERROR | 欄位或業務規則驗證失敗 |
| 429 | RATE_LIMITED | 請求過於頻繁 |
| 500 | INTERNAL_ERROR | 未預期伺服器錯誤 |

錯誤訊息不得洩漏 service role key、SQL、資料庫內部細節或管理員判斷邏輯。

## 4. 必須先確認的規則（未確認前不可實作定案）

1. 七個維護範圍的正式代碼及是否存在「全站」範圍。
2. 維護事件的正式狀態欄位與允許狀態轉換。
3. 同一範圍、不同範圍，以及全站與局部維護之間的排程重疊判定。
4. 已開始、已結束或已取消事件是否允許修改，以及允許修改哪些欄位。
5. 前台狀態 API 是否需要同時回傳即將開始的事件。
6. 現有資料表欄位、唯一限制、索引及稽核紀錄結構。
7. 管理員身分在現有專案中的權威來源，以及五支 Edge Function 的既有呼叫方式。

## 5. 驗收條件

- 非管理員不能列出、建立、修改或操作維護事件。
- 前台狀態 API 不洩漏管理端欄位。
- 不合法時間區間、未知 scope、未知 action 一律拒絕。
- 併發建立或更新時，不能繞過排程衝突與版本檢查。
- 事件資料與稽核紀錄具備交易一致性。
- 重複提交不會造成重複或互相矛盾的狀態轉換。
- 測試涵蓋匿名、一般登入者、管理員、過期 JWT、無效輸入、衝突及併發情境。

---
本文件只建立待核對的 API 契約；尚未建立 Edge Functions、尚未執行 Migration，也尚未進行正式環境測試。


## 6. Supabase 現況核對紀錄（2026-11-08，只讀檢查）

核對對象：Supabase 專案 `fsoowongtavlsrwvzbze` 的目前連線資料庫與已部署 Edge Functions。以下只記錄本次可直接查證的現況，不代表功能已實作。

### 已查證結果

1. **目前 public schema 未見維護專用資料表。** 本次查詢到的 public base tables 共 43 張，沒有名稱包含 `maintenance`、`audit` 或 `event` 的資料表，也沒有任何維護相關欄位可供五支 API 直接使用。
2. **目前已部署 Edge Functions 清單未見維護 API。** 已列出的函式為 `manage-visitors`、`create-visitor`（清單中另有一個 slug/name 不一致項）、`set-visitor-password`、`ai-generate-announcement`、`send-announcement-push`；未見本規格列出的五支 maintenance functions。
3. **現有管理員角色來源可查證。** `public.profiles` 有 `id`、`role` 等欄位；`role` 預設為 `visitor`，資料庫檢查限制為 `admin` 或 `visitor`。
4. **現有管理員判斷函式可查證。** `public.is_admin()` 以 `auth.uid()` 對應 `profiles.id` 且 `role='admin'` 判斷，函式為 `SECURITY DEFINER`，並設定空的 `search_path`。實作時仍須確認呼叫權限及函式擁有者，不可僅因函式存在就視為整體授權已安全。
5. **profiles RLS policy 可查證。** 有管理員全權政策（使用 `is_admin()`）、本人讀取政策，以及本人更新政策（更新後限制 `role='visitor'`）。這可作為管理員驗證設計的現況參考。
6. **七個維護範圍尚無資料庫證據。** 本次未查到維護範圍 enum、check constraint、scope table 或維護事件資料，故不能把「七個範圍」寫成已核實的正式代碼。
7. **Migration 清單工具回傳空陣列。** 這只表示本次工具回傳沒有列出 migration 紀錄；不單憑此結果推論資料庫從未執行過任何 schema migration。

### 對 API 草案的修正要求

- 五支 API 目前都屬於**待建置**，不得描述為已存在或已可呼叫。
- `maintenance-status` 目前沒有維護事件資料來源；需先設計並建立維護資料模型後才能實作。
- `maintenance-admin-list`、`create`、`update`、`action` 都需要維護事件與稽核紀錄資料表／交易邏輯，目前資料庫尚未提供。
- 管理員權限應以伺服器端驗證登入使用者，再根據受信任的 `profiles.role` 或經核實的 `is_admin()` 機制授權；不得接受前端自報角色。
- scope 代碼、狀態機、排程重疊規則、編輯限制、稽核 schema 都仍是**未決設計**，需先定稿，再寫 migration 與函式。
- 在資料模型與規則核准前，不部署 Edge Functions、不執行 Migration、不改動正式資料庫。

### 本輪核對結論

**結果：API 草案與目前資料庫尚未對接。** 已確認可重用的只有管理員角色資料與 `is_admin()` 判斷基礎；維護資料表、七個 scope 的正式代碼、狀態轉換與五支 API 均未在目前連線的 Supabase 專案中查得。
