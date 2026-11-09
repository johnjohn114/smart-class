export type AuthMode = "required" | "optional";
export type JsonObject = Record<string, unknown>;

export class HttpError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
  }
}

const SCOPE_CODES = [
  "site_core",
  "announcements_info",
  "events_competitions",
  "video_content",
  "membership_growth",
  "store_support",
  "downloads_app",
] as const;

const MUTABLE_EVENT_FIELDS = [
  "title",
  "message",
  "internal_note",
  "is_global",
  "scope_codes",
  "starts_at",
  "ends_at",
] as const;

function getConfig() {
  const url = Deno.env.get("SUPABASE_URL");
  const key =
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
    Deno.env.get("SUPABASE_ANON_KEY") ??
    (() => {
      const raw = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
      if (!raw) return undefined;
      try {
        return JSON.parse(raw).default as string | undefined;
      } catch {
        return undefined;
      }
    })();

  if (!url || !key) {
    throw new HttpError(500, "INTERNAL_ERROR", "服務設定尚未完成");
  }
  return { url: url.replace(/\/$/, ""), key };
}

function allowedOrigins(): string[] {
  const configured = Deno.env.get("MAINTENANCE_ALLOWED_ORIGINS");
  if (configured) {
    return configured.split(",").map((v) => v.trim()).filter(Boolean);
  }
  // Default matches the currently documented GitHub Pages site origin.
  return ["https://johnjohn114.github.io"];
}

function corsHeaders(origin: string | null): Headers {
  const headers = new Headers({
    "Vary": "Origin",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Max-Age": "86400",
    "Cache-Control": "no-store",
  });
  if (origin && allowedOrigins().includes(origin)) {
    headers.set("Access-Control-Allow-Origin", origin);
  }
  return headers;
}

function jsonResponse(
  body: unknown,
  status: number,
  origin: string | null,
): Response {
  const headers = corsHeaders(origin);
  headers.set("Content-Type", "application/json; charset=utf-8");
  return new Response(JSON.stringify(body), { status, headers });
}

function fail(error: HttpError, origin: string | null): Response {
  return jsonResponse({
    ok: false,
    error: { code: error.code, message: error.message },
  }, error.status, origin);
}

function getBearerToken(req: Request): string | null {
  const value = req.headers.get("authorization");
  if (!value) return null;
  const match = /^Bearer\s+([^\s]+)$/i.exec(value.trim());
  return match?.[1] ?? null;
}

async function isValidUserToken(token: string): Promise<boolean> {
  const { url, key } = getConfig();
  try {
    const response = await fetch(`${url}/auth/v1/user`, {
      method: "GET",
      headers: {
        apikey: key,
        Authorization: `Bearer ${token}`,
      },
    });
    return response.ok;
  } catch {
    return false;
  }
}

function requireObject(value: unknown): JsonObject {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpError(400, "INVALID_REQUEST", "請提供 JSON 物件");
  }
  return value as JsonObject;
}

function rejectUnknownKeys(
  value: JsonObject,
  allowed: readonly string[],
): void {
  const unknown = Object.keys(value).filter((key) => !allowed.includes(key));
  if (unknown.length) {
    throw new HttpError(400, "INVALID_REQUEST", "請求包含不支援的欄位");
  }
}

function requireString(
  value: unknown,
  name: string,
  maxLength: number,
  optional = false,
): string | null {
  if (optional && (value === undefined || value === null || value === "")) {
    return null;
  }
  if (typeof value !== "string" || !value.trim() || value.length > maxLength) {
    throw new HttpError(422, "VALIDATION_ERROR", `${name} 格式不正確`);
  }
  return value.trim();
}

function requireUuid(value: unknown, name: string): string {
  const result = requireString(value, name, 36);
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(result!)) {
    throw new HttpError(422, "VALIDATION_ERROR", `${name} 必須是 UUID`);
  }
  return result!;
}

function requireIsoDate(value: unknown, name: string): string {
  const result = requireString(value, name, 40);
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$/i.test(result!)) {
    throw new HttpError(422, "VALIDATION_ERROR", `${name} 必須是含時區的 ISO 8601 時間`);
  }
  if (!Number.isFinite(Date.parse(result!))) {
    throw new HttpError(422, "VALIDATION_ERROR", `${name} 時間無效`);
  }
  return result!;
}

function requireScopeCodes(value: unknown): string[] {
  if (!Array.isArray(value) || value.some((v) => typeof v !== "string")) {
    throw new HttpError(422, "VALIDATION_ERROR", "scope_codes 格式不正確");
  }
  const values = [...new Set(value as string[])];
  if (values.some((v) => !SCOPE_CODES.includes(v as typeof SCOPE_CODES[number]))) {
    throw new HttpError(422, "VALIDATION_ERROR", "scope_codes 包含未知範圍");
  }
  return values;
}

function requireReason(value: unknown): string {
  return requireString(value, "reason", 500)!;
}

async function readJsonBody(req: Request): Promise<JsonObject> {
  const contentType = req.headers.get("content-type") ?? "";
  if (!contentType.toLowerCase().includes("application/json")) {
    throw new HttpError(400, "INVALID_REQUEST", "Content-Type 必須是 application/json");
  }
  const raw = await req.text();
  if (raw.length > 64 * 1024) {
    throw new HttpError(413, "INVALID_REQUEST", "請求內容超過大小限制");
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new HttpError(400, "INVALID_REQUEST", "JSON 格式錯誤");
  }
  return requireObject(parsed);
}

export function parseStatusRequest(req: Request): JsonObject {
  const url = new URL(req.url);
  for (const key of url.searchParams.keys()) {
    if (key !== "scope") {
      throw new HttpError(400, "INVALID_REQUEST", "查詢參數不支援");
    }
  }
  const scope = url.searchParams.get("scope");
  if (scope === null) return {};
  if (!scope.trim() || !SCOPE_CODES.includes(scope as typeof SCOPE_CODES[number])) {
    throw new HttpError(422, "VALIDATION_ERROR", "scope 不在允許範圍內");
  }
  return { scope };
}

export function parseAdminListRequest(req: Request): JsonObject {
  const url = new URL(req.url);
  const allowed = ["status", "scope", "is_global", "from", "to", "limit", "cursor"];
  for (const key of url.searchParams.keys()) {
    if (!allowed.includes(key)) {
      throw new HttpError(400, "INVALID_REQUEST", "查詢參數不支援");
    }
  }
  const result: JsonObject = {};
  const status = url.searchParams.get("status");
  if (status !== null) {
    if (!status.trim() || !["draft", "scheduled", "cancelled", "completed"].includes(status)) {
      throw new HttpError(422, "VALIDATION_ERROR", "status 不正確");
    }
    result.status = status;
  }
  const scope = url.searchParams.get("scope");
  if (scope !== null) {
    if (!scope.trim() || !SCOPE_CODES.includes(scope as typeof SCOPE_CODES[number])) {
      throw new HttpError(422, "VALIDATION_ERROR", "scope 不正確");
    }
    result.scope = scope;
  }
  const isGlobal = url.searchParams.get("is_global");
  if (isGlobal !== null) {
    if (isGlobal !== "true" && isGlobal !== "false") {
      throw new HttpError(422, "VALIDATION_ERROR", "is_global 必須是 true 或 false");
    }
    result.is_global = isGlobal === "true";
  }
  const from = url.searchParams.get("from");
  const to = url.searchParams.get("to");
  if (from !== null) result.from = requireIsoDate(from, "from");
  if (to !== null) result.to = requireIsoDate(to, "to");
  if (from !== null && to !== null && Date.parse(from) >= Date.parse(to)) {
    throw new HttpError(422, "VALIDATION_ERROR", "from 必須早於 to");
  }
  const limit = url.searchParams.get("limit");
  if (limit !== null) {
    if (!/^\d+$/.test(limit) || Number(limit) < 1 || Number(limit) > 100) {
      throw new HttpError(422, "VALIDATION_ERROR", "limit 必須介於 1 至 100");
    }
    result.limit = Number(limit);
  } else {
    result.limit = 20;
  }
  const cursor = url.searchParams.get("cursor");
  if (cursor !== null) result.cursor = requireString(cursor, "cursor", 2000);
  return result;
}

export async function parseCreateRequest(req: Request): Promise<JsonObject> {
  const value = await readJsonBody(req);
  rejectUnknownKeys(value, [
    "title", "message", "internal_note", "is_global", "scope_codes",
    "starts_at", "ends_at", "status", "reason", "idempotency_key",
  ]);
  const title = requireString(value.title, "title", 200)!;
  const message = requireString(value.message, "message", 4000)!;
  const internalNote = requireString(value.internal_note, "internal_note", 4000, true);
  if (typeof value.is_global !== "boolean") {
    throw new HttpError(422, "VALIDATION_ERROR", "is_global 必須是布林值");
  }
  const scopeCodes = requireScopeCodes(value.scope_codes);
  if (value.is_global && scopeCodes.length !== 0) {
    throw new HttpError(422, "VALIDATION_ERROR", "全站維護不得指定 scope_codes");
  }
  if (!value.is_global && scopeCodes.length === 0) {
    throw new HttpError(422, "VALIDATION_ERROR", "局部維護至少需要一個 scope");
  }
  const startsAt = requireIsoDate(value.starts_at, "starts_at");
  const endsAt = requireIsoDate(value.ends_at, "ends_at");
  if (Date.parse(startsAt) >= Date.parse(endsAt)) {
    throw new HttpError(422, "VALIDATION_ERROR", "starts_at 必須早於 ends_at");
  }
  if (value.status !== "draft" && value.status !== "scheduled") {
    throw new HttpError(422, "VALIDATION_ERROR", "初始 status 僅允許 draft 或 scheduled");
  }
  return {
    title, message, internal_note: internalNote, is_global: value.is_global,
    scope_codes: scopeCodes, starts_at: startsAt, ends_at: endsAt,
    status: value.status, reason: requireReason(value.reason),
    idempotency_key: requireUuid(value.idempotency_key, "idempotency_key"),
  };
}

export async function parseUpdateRequest(req: Request): Promise<JsonObject> {
  const value = await readJsonBody(req);
  const allowed = ["event_id", "expected_version", "reason", "idempotency_key", ...MUTABLE_EVENT_FIELDS];
  rejectUnknownKeys(value, allowed);
  const result: JsonObject = {
    event_id: requireUuid(value.event_id, "event_id"),
    expected_version: value.expected_version,
    reason: requireReason(value.reason),
    idempotency_key: requireUuid(value.idempotency_key, "idempotency_key"),
  };
  if (!Number.isSafeInteger(value.expected_version) || Number(value.expected_version) < 1) {
    throw new HttpError(422, "VALIDATION_ERROR", "expected_version 必須是正整數");
  }
  let changed = 0;
  if ("title" in value) { result.title = requireString(value.title, "title", 200)!; changed++; }
  if ("message" in value) { result.message = requireString(value.message, "message", 4000)!; changed++; }
  if ("internal_note" in value) { result.internal_note = requireString(value.internal_note, "internal_note", 4000, true); changed++; }
  if ("is_global" in value) {
    if (typeof value.is_global !== "boolean") throw new HttpError(422, "VALIDATION_ERROR", "is_global 必須是布林值");
    result.is_global = value.is_global; changed++;
  }
  if ("scope_codes" in value) { result.scope_codes = requireScopeCodes(value.scope_codes); changed++; }
  if ("starts_at" in value) { result.starts_at = requireIsoDate(value.starts_at, "starts_at"); changed++; }
  if ("ends_at" in value) { result.ends_at = requireIsoDate(value.ends_at, "ends_at"); changed++; }
  if (!changed) throw new HttpError(422, "VALIDATION_ERROR", "至少提供一個可修改欄位");
  if ("is_global" in result && "scope_codes" in result) {
    const scopes = result.scope_codes as string[];
    if (result.is_global === true && scopes.length !== 0) {
      throw new HttpError(422, "VALIDATION_ERROR", "全站維護不得指定 scope_codes");
    }
    if (result.is_global === false && scopes.length === 0) {
      throw new HttpError(422, "VALIDATION_ERROR", "局部維護至少需要一個 scope");
    }
  }
  if ("starts_at" in result && "ends_at" in result &&
      Date.parse(String(result.starts_at)) >= Date.parse(String(result.ends_at))) {
    throw new HttpError(422, "VALIDATION_ERROR", "starts_at 必須早於 ends_at");
  }
  return result;
}

export async function parseActionRequest(req: Request): Promise<JsonObject> {
  const value = await readJsonBody(req);
  rejectUnknownKeys(value, ["event_id", "expected_version", "action", "reason", "idempotency_key"]);
  if (!Number.isSafeInteger(value.expected_version) || Number(value.expected_version) < 1) {
    throw new HttpError(422, "VALIDATION_ERROR", "expected_version 必須是正整數");
  }
  if (!["schedule", "cancel", "complete"].includes(String(value.action))) {
    throw new HttpError(422, "VALIDATION_ERROR", "action 不在允許範圍內");
  }
  return {
    event_id: requireUuid(value.event_id, "event_id"),
    expected_version: value.expected_version,
    action: value.action,
    reason: requireReason(value.reason),
    idempotency_key: requireUuid(value.idempotency_key, "idempotency_key"),
  };
}

function mapRpcError(status: number, raw: unknown): HttpError {
  const value = raw && typeof raw === "object" ? raw as Record<string, unknown> : {};
  const code = String(value.code ?? "");
  const message = String(value.message ?? "");
  const detail = `${code} ${message}`;

  if (code === "42501" || status === 403) {
    return new HttpError(403, "FORBIDDEN", "無權執行此操作");
  }
  if (status === 401) {
    return new HttpError(401, "UNAUTHENTICATED", "登入狀態已失效，請重新登入");
  }
  if (code === "P0002" || status === 404) {
    return new HttpError(404, "NOT_FOUND", "找不到指定事件");
  }
  if (/VERSION_CONFLICT/.test(detail)) {
    return new HttpError(409, "VERSION_CONFLICT", "資料已更新，請重新載入後再試");
  }
  if (/IDEMPOTENCY_KEY_REUSED/.test(detail)) {
    return new HttpError(409, "IDEMPOTENCY_KEY_REUSED", "請求識別碼已用於不同內容");
  }
  if (/CONFLICT/.test(detail) || code === "23505" || status === 409) {
    return new HttpError(409, "CONFLICT", "操作與現有排程或狀態衝突");
  }
  if (/VALIDATION_ERROR/.test(detail) || code === "22023") {
    return new HttpError(422, "VALIDATION_ERROR", "資料不符合維護規則");
  }
  return new HttpError(500, "INTERNAL_ERROR", "伺服器暫時無法完成請求");
}

async function callRpc(
  rpc: string,
  payload: JsonObject,
  token: string | null,
): Promise<unknown> {
  const { url, key } = getConfig();
  let response: Response;
  try {
    const headers: Record<string, string> = {
      apikey: key,
      "Content-Type": "application/json",
      Accept: "application/json",
    };
    if (token) headers.Authorization = `Bearer ${token}`;
    response = await fetch(`${url}/rest/v1/rpc/${rpc}`, {
      method: "POST",
      headers,
      body: JSON.stringify({ p_request: payload }),
    });
  } catch {
    throw new HttpError(503, "SERVICE_UNAVAILABLE", "目前無法連線至維護服務");
  }

  const raw = await response.json().catch(() => null);
  if (!response.ok) throw mapRpcError(response.status, raw);
  return raw;
}

export interface HandlerOptions {
  method: "GET" | "POST";
  auth: AuthMode;
  rpc: string;
  parse: (req: Request) => JsonObject | Promise<JsonObject>;
}

export function createMaintenanceHandler(options: HandlerOptions) {
  return async (req: Request): Promise<Response> => {
    const origin = req.headers.get("origin");
    const allowed = allowedOrigins();
    if (origin && !allowed.includes(origin)) {
      return jsonResponse({
        ok: false,
        error: { code: "FORBIDDEN", message: "來源網站不在允許清單內" },
      }, 403, null);
    }

    if (req.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders(origin) });
    }
    if (req.method !== options.method) {
      return fail(new HttpError(405, "INVALID_REQUEST", "HTTP method 不正確"), origin);
    }

    try {
      const suppliedToken = getBearerToken(req);
      let token: string | null = null;

      if (options.auth === "required") {
        if (!suppliedToken) {
          throw new HttpError(401, "UNAUTHENTICATED", "請先登入");
        }
        if (!(await isValidUserToken(suppliedToken))) {
          throw new HttpError(401, "UNAUTHENTICATED", "登入狀態已失效，請重新登入");
        }
        token = suppliedToken;
      } else if (suppliedToken && await isValidUserToken(suppliedToken)) {
        // Invalid optional tokens degrade to anonymous public access; they never grant bypass.
        token = suppliedToken;
      }

      const payload = await options.parse(req);
      const data = await callRpc(options.rpc, payload, token);
      if (data && typeof data === "object" && "ok" in (data as Record<string, unknown>)) {
        return jsonResponse(data, 200, origin);
      }
      return jsonResponse({ ok: true, data }, 200, origin);
    } catch (error) {
      if (error instanceof HttpError) return fail(error, origin);
      return fail(new HttpError(500, "INTERNAL_ERROR", "伺服器暫時無法完成請求"), origin);
    }
  };
}
