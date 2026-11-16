import {
  parseActionRequest,
  parseAdminListRequest,
  parseCreateRequest,
  parseStatusRequest,
  parseUpdateRequest,
  createMaintenanceHandler,
} from "../../functions/_shared/maintenance.ts";

const uuid = "9f4c7a2e-1d63-4a80-9b21-7c6e5d4f3a20";

Deno.test("status: accepts no scope and known scope only", () => {
  const empty = parseStatusRequest(new Request("https://local.test/maintenance-status"));
  if (Object.keys(empty).length !== 0) throw new Error("expected empty status query");

  const scoped = parseStatusRequest(new Request("https://local.test/maintenance-status?scope=site_core"));
  if (scoped.scope !== "site_core") throw new Error("expected site_core");

  let rejected = false;
  try {
    parseStatusRequest(new Request("https://local.test/maintenance-status?scope=unknown"));
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error("unknown scope must be rejected");
});

Deno.test("admin list: validates limits and date windows", () => {
  const valid = parseAdminListRequest(new Request("https://local.test/list?limit=100&is_global=false"));
  if (valid.limit !== 100 || valid.is_global !== false) throw new Error("valid filters were not parsed");

  let rejected = false;
  try {
    parseAdminListRequest(new Request("https://local.test/list?limit=101"));
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error("limit above 100 must be rejected");
});

Deno.test("create: accepts a valid global draft", async () => {
  const req = new Request("https://local.test/create", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      title: "系統維護",
      message: "服務將進行維護",
      internal_note: null,
      is_global: true,
      scope_codes: [],
      starts_at: "2026-12-01T10:00:00+08:00",
      ends_at: "2026-12-01T11:00:00+08:00",
      status: "draft",
      reason: "排定例行維護",
      idempotency_key: uuid,
    }),
  });
  const result = await parseCreateRequest(req);
  if (result.is_global !== true || result.status !== "draft") throw new Error("create payload mismatch");
});

Deno.test("create: rejects local event without scopes", async () => {
  const req = new Request("https://local.test/create", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      title: "局部維護",
      message: "服務維護",
      is_global: false,
      scope_codes: [],
      starts_at: "2026-12-01T10:00:00+08:00",
      ends_at: "2026-12-01T11:00:00+08:00",
      status: "draft",
      reason: "排定維護",
      idempotency_key: uuid,
    }),
  });
  let rejected = false;
  try {
    await parseCreateRequest(req);
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error("local event without scopes must be rejected");
});

Deno.test("update: rejects protected or unknown fields", async () => {
  const req = new Request("https://local.test/update", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      event_id: uuid,
      expected_version: 1,
      status: "completed",
      reason: "測試",
      idempotency_key: uuid,
      title: "更新標題",
    }),
  });
  let rejected = false;
  try {
    await parseUpdateRequest(req);
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error("protected status field must be rejected");
});

Deno.test("action: only supports schedule, cancel, complete", async () => {
  const req = new Request("https://local.test/action", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      event_id: uuid,
      expected_version: 1,
      action: "extend",
      reason: "測試",
      idempotency_key: uuid,
    }),
  });
  let rejected = false;
  try {
    await parseActionRequest(req);
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error("unsupported action must be rejected");
});

Deno.test("status: rejects an explicitly blank scope", () => {
  let rejected = false;
  try {
    parseStatusRequest(new Request("https://local.test/maintenance-status?scope="));
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error("blank scope must be rejected");
});

Deno.test("admin list: rejects explicitly blank status, scope, from, and to", () => {
  for (const parameter of ["status", "scope", "from", "to"]) {
    let rejected = false;
    try {
      parseAdminListRequest(
        new Request(`https://local.test/list?${parameter}=`),
      );
    } catch {
      rejected = true;
    }
    if (!rejected) {
      throw new Error(`blank ${parameter} must be rejected`);
    }
  }
});

Deno.test("date validation: rejects impossible calendar dates", async () => {
  const req = new Request("https://local.test/create", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      title: "系統維護",
      message: "服務將進行維護",
      internal_note: null,
      is_global: true,
      scope_codes: [],
      starts_at: "2026-02-30T10:00:00+08:00",
      ends_at: "2026-03-03T11:00:00+08:00",
      status: "draft",
      reason: "排定例行維護",
      idempotency_key: uuid,
    }),
  });
  let rejected = false;
  try {
    await parseCreateRequest(req);
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error("impossible calendar date must be rejected");
});

Deno.test("date validation: accepts leap day in a leap year", async () => {
  const req = new Request("https://local.test/create", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      title: "系統維護",
      message: "服務將進行維護",
      internal_note: null,
      is_global: true,
      scope_codes: [],
      starts_at: "2028-02-29T10:00:00+08:00",
      ends_at: "2028-03-01T11:00:00+08:00",
      status: "draft",
      reason: "排定例行維護",
      idempotency_key: uuid,
    }),
  });
  const result = await parseCreateRequest(req);
  if (result.starts_at !== "2028-02-29T10:00:00+08:00") {
    throw new Error("valid leap day must be preserved");
  }
});

Deno.test("date validation: rejects invalid dates in admin filters", () => {
  for (const value of [
    "2026-02-30T10:00:00+08:00",
    "2026-13-01T10:00:00+08:00",
    "2026-11-16T25:00:00+08:00",
  ]) {
    let rejected = false;
    try {
      parseAdminListRequest(
        new Request("https://local.test/list?from=" + encodeURIComponent(value)),
      );
    } catch {
      rejected = true;
    }
    if (!rejected) throw new Error(`invalid date must be rejected: ${value}`);
  }
});

Deno.test("date validation: rejects non-leap-year February 29", async () => {
  const req = new Request("https://local.test/create", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      title: "系統維護",
      message: "服務將進行維護",
      internal_note: null,
      is_global: true,
      scope_codes: [],
      starts_at: "2027-02-29T10:00:00+08:00",
      ends_at: "2027-03-01T11:00:00+08:00",
      status: "draft",
      reason: "排定例行維護",
      idempotency_key: uuid,
    }),
  });
  let rejected = false;
  try {
    await parseCreateRequest(req);
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error("non-leap-year February 29 must be rejected");
});

Deno.test("status: rejects duplicate scope parameters", () => {
  let rejected = false;
  try {
    parseStatusRequest(
      new Request("https://local.test/status?scope=site_core&scope=video_content"),
    );
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error("duplicate scope parameters must be rejected");
});

Deno.test("admin list: rejects duplicate filters", () => {
  let rejected = false;
  try {
    parseAdminListRequest(
      new Request("https://local.test/list?limit=10&limit=20"),
    );
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error("duplicate filters must be rejected");
});

Deno.test("request body: rejects missing JSON content type", async () => {
  const req = new Request("https://local.test/create", {
    method: "POST",
    body: "{}",
  });
  let rejected = false;
  try {
    await parseCreateRequest(req);
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error("non-JSON content type must be rejected");
});

Deno.test("request body: rejects malformed JSON and non-object JSON", async () => {
  for (const body of ["{", "null", "[]", '"text"']) {
    const req = new Request("https://local.test/create", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body,
    });
    let rejected = false;
    try {
      await parseCreateRequest(req);
    } catch {
      rejected = true;
    }
    if (!rejected) throw new Error(`invalid JSON body must be rejected: ${body}`);
  }
});

Deno.test("request body: enforces 64 KiB UTF-8 byte limit", async () => {
  const req = new Request("https://local.test/create", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message: "字".repeat(23000) }),
  });
  let rejected = false;
  try {
    await parseCreateRequest(req);
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error("body over 64 KiB must be rejected");
});

Deno.test("date validation: rejects out-of-range time and timezone", async () => {
  for (const value of [
    "2026-11-16T24:00:00+08:00",
    "2026-11-16T10:99:00+08:00",
    "2026-11-16T10:00:00+14:01",
    "2026-11-16T10:00:00+08:99",
  ]) {
    const req = new Request("https://local.test/create", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        title: "系統維護",
        message: "服務將進行維護",
        is_global: true,
        scope_codes: [],
        starts_at: value,
        ends_at: "2026-11-17T10:00:00+08:00",
        status: "draft",
        reason: "排定維護",
        idempotency_key: uuid,
      }),
    });
    let rejected = false;
    try {
      await parseCreateRequest(req);
    } catch {
      rejected = true;
    }
    if (!rejected) throw new Error(`invalid time zone/date must be rejected: ${value}`);
  }
});

Deno.test("handler: rejects missing bearer token on protected endpoints", async () => {
  const handler = createMaintenanceHandler({
    method: "POST",
    auth: "required",
    rpc: "maintenance_event_create",
    parse: async () => ({ should_not_parse: true }),
  });
  const response = await handler(new Request("https://local.test/create", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: "{}",
  }));
  const body = await response.json();
  if (response.status !== 401 || body.error?.code !== "UNAUTHENTICATED") {
    throw new Error("protected endpoint must reject missing bearer token");
  }
});

Deno.test("handler: rejects incorrect HTTP method", async () => {
  const handler = createMaintenanceHandler({
    method: "POST",
    auth: "required",
    rpc: "maintenance_event_create",
    parse: async () => ({}),
  });
  const response = await handler(new Request("https://local.test/create", {
    method: "GET",
  }));
  const body = await response.json();
  if (response.status !== 405 || body.error?.code !== "INVALID_REQUEST") {
    throw new Error("incorrect method must return 405");
  }
});

Deno.test("handler: answers allowed CORS preflight without calling RPC", async () => {
  const handler = createMaintenanceHandler({
    method: "GET",
    auth: "optional",
    rpc: "maintenance_status_public",
    parse: () => ({}),
  });
  const response = await handler(new Request("https://local.test/status", {
    method: "OPTIONS",
    headers: { Origin: "https://johnjohn114.github.io" },
  }));
  if (
    response.status !== 204 ||
    response.headers.get("Access-Control-Allow-Origin") !== "https://johnjohn114.github.io"
  ) {
    throw new Error("allowed CORS preflight must return 204 and allow origin");
  }
});

Deno.test("handler: blocks unapproved origins", async () => {
  const handler = createMaintenanceHandler({
    method: "GET",
    auth: "optional",
    rpc: "maintenance_status_public",
    parse: () => ({}),
  });
  const response = await handler(new Request("https://local.test/status", {
    method: "GET",
    headers: { Origin: "https://untrusted.example" },
  }));
  const body = await response.json();
  if (response.status !== 403 || body.error?.code !== "FORBIDDEN") {
    throw new Error("unapproved origin must be blocked");
  }
  if (response.headers.has("Access-Control-Allow-Origin")) {
    throw new Error("unapproved origin must not receive CORS permission");
  }
});

