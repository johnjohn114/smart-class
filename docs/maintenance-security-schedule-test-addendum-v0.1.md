# Maintenance System 權限與排程測試補充 v0.1

> 日期：2026-11-16  
> 分支：`feature/maintenance-system`  
> 最新測試提交：`051f7c8f42af8b0649ea817604ff00c7c8a4e242`  
> GitHub Actions：`43891994630`  
> 結果：Deno、isolated PostgreSQL、GoTrue/PostgREST 三項皆成功。

## 本輪新增測試

### 權限邊界

- 未帶 bearer token 的 anon caller，逐一呼叫 `maintenance_admin_list`、`maintenance_event_create`、`maintenance_event_update`、`maintenance_event_action`，皆被拒絕。
- 以 GoTrue 簽發的 authenticated 非管理員 JWT，逐一呼叫上述四個管理 RPC，皆被拒絕。
- 建立、更新、操作事件時嘗試加入 `actor_id` 欄位，皆由 RPC 輸入白名單拒絕。
- 前一輪已測試管理員 JWT 可執行管理 RPC、竄改 JWT 簽章被拒絕、private tables 不透過 PostgREST 暴露。

### 排程衝突與生命週期

- 同一個局部 scope 的重疊維護事件無法同時排程。
- 半開區間相鄰時段（前一事件結束時間等於下一事件開始時間）可以排程，不會被誤判為重疊。
- 全站維護與重疊的局部維護衝突。
- 先前已測試兩個全站維護事件併發建立時只有一個成功。
- 排程中的事件未到結束時間前不能執行 complete。
- 前一輪已測試 draft -> scheduled -> cancelled、版本衝突、update/action 冪等重播。

## CI 過程中的修正

第一次執行時，PostgREST 對 SQLSTATE `23505` 的衝突回應不是固定 HTTP 400；測試已調整為接受標準衝突回應狀態（400/409/422），並保留對應錯誤訊息斷言。這是測試對 HTTP 映射的相容性修正，沒有降低衝突規則本身的驗證。

## 結論與仍待處理事項

本輪測試全部通過，代表目前隔離測試環境中上述權限拒絕與排程規則符合預期。

這仍不代表正式環境已驗收。正式 Supabase Migration baseline、實際 Data API exposed schemas、正式 grants/RLS、Edge Function secrets/CORS、rate limiting、audit/idempotency retention，以及部署後 smoke test 仍待審查。不得把這份 CI 結果視為正式資料庫已部署或正式發布核准。
