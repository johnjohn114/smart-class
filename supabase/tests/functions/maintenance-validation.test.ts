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

Deno.test("request body: rejects invalid UTF-8", async () => {
  const req = new Request("https://local.test/create", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: new Uint8Array([0xff, 0x7b, 0x7d]),
  });
  let rejected = false;
  try {
    await parseCreateRequest(req);
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error("invalid UTF-8 must be rejected");
});

Deno.test("handler: distinguishes invalid credentials from Auth service outage", async () => {
  const originalFetch = globalThis.fetch;
  const previousUrl = Deno.env.get("SUPABASE_URL");
  const previousKey = Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  Deno.env.set("SUPABASE_URL", "https://auth-test.invalid");
  Deno.env.set("SUPABASE_PUBLISHABLE_KEY", "test-publishable-key");

  const handler = createMaintenanceHandler({
    method: "POST",
    auth: "required",
    rpc: "maintenance_event_create",
    parse: () => ({}),
  });

  try {
    globalThis.fetch = async () => new Response("{}", { status: 401 });
    const invalid = await handler(new Request("https://local.test/create", {
      method: "POST",
      headers: { Authorization: "Bearer invalid-token" },
    }));
    if (invalid.status !== 401) {
      throw new Error("invalid credentials must return 401");
    }

    globalThis.fetch = async () => new Response("{}", { status: 503 });
    const unavailable = await handler(new Request("https://local.test/create", {
      method: "POST",
      headers: { Authorization: "Bearer valid-looking-token" },
    }));
    const body = await unavailable.json();
    if (unavailable.status !== 503 || body.error?.code !== "AUTH_UNAVAILABLE") {
      throw new Error("Auth service outage must return 503 AUTH_UNAVAILABLE");
    }
  } finally {
    globalThis.fetch = originalFetch;
    if (previousUrl === undefined) Deno.env.delete("SUPABASE_URL");
    else Deno.env.set("SUPABASE_URL", previousUrl);
    if (previousKey === undefined) Deno.env.delete("SUPABASE_PUBLISHABLE_KEY");
    else Deno.env.set("SUPABASE_PUBLISHABLE_KEY", previousKey);
  }
});

Deno.test("admin list: accepts an opaque pagination cursor", () => {
  const cursor = "MjAyNi0xMS0yMFQxMDowMDowMFp8OWY0YzdhMmUtMWQ2My00YTgwLTliMjEtN2M2ZTVkNGYzYTIw";
  const result = parseAdminListRequest(
    new Request("https://local.test/list?limit=100&cursor=" + encodeURIComponent(cursor)),
  );
  if (result.limit !== 100 || result.cursor !== cursor) {
    throw new Error("pagination cursor must be preserved");
  }
});

Deno.test("admin list: rejects duplicate cursor parameters", () => {
  let rejected = false;
  try {
    parseAdminListRequest(
      new Request("https://local.test/list?cursor=first&cursor=second"),
    );
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error("duplicate cursor must be rejected");
});

Deno.test("handler: keeps RPC success responses in a single envelope", async () => {
  const previousUrl = Deno.env.get("SUPABASE_URL");
  const previousKey = Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const originalFetch = globalThis.fetch;
  const statusData = {
    is_maintenance: true,
    admin_bypass: false,
    title: "測試維護",
    message: "測試公告",
  };
  const listData = {
    events: [{ id: uuid, title: "測試事件", scopes: [] }],
    next_cursor: "next-page-token",
  };

  Deno.env.set("SUPABASE_URL", "https://maintenance-contract.test");
  Deno.env.set("SUPABASE_PUBLISHABLE_KEY", "test-publishable-key");
  globalThis.fetch = (async (input: RequestInfo | URL) => {
    const url = String(input);
    if (url.endsWith("/auth/v1/user")) {
      return Response.json({ id: uuid });
    }
    if (url.endsWith("/rest/v1/rpc/maintenance_status_public")) {
      return Response.json({ ok: true, data: statusData });
    }
    if (url.endsWith("/rest/v1/rpc/maintenance_admin_list")) {
      return Response.json({ ok: true, data: listData });
    }
    return new Response("Unexpected mocked request", { status: 404 });
  }) as typeof fetch;

  try {
    const statusHandler = createMaintenanceHandler({
      method: "GET",
      auth: "optional",
      rpc: "maintenance_status_public",
      parse: parseStatusRequest,
    });
    const statusResponse = await statusHandler(
      new Request("https://local.test/status?scope=site_core"),
    );
    const statusBody = await statusResponse.json();
    if (
      statusResponse.status !== 200 ||
      JSON.stringify(statusBody) !== JSON.stringify({ ok: true, data: statusData })
    ) {
      throw new Error("public status must expose the RPC payload under one data envelope");
    }

    const listHandler = createMaintenanceHandler({
      method: "GET",
      auth: "required",
      rpc: "maintenance_admin_list",
      parse: parseAdminListRequest,
    });
    const listResponse = await listHandler(
      new Request("https://local.test/list?limit=20", {
        headers: { Authorization: "Bearer valid-test-token" },
      }),
    );
    const listBody = await listResponse.json();
    if (
      listResponse.status !== 200 ||
      JSON.stringify(listBody) !== JSON.stringify({ ok: true, data: listData })
    ) {
      throw new Error("admin list must expose events and next_cursor under one data envelope");
    }
  } finally {
    globalThis.fetch = originalFetch;
    if (previousUrl === undefined) Deno.env.delete("SUPABASE_URL");
    else Deno.env.set("SUPABASE_URL", previousUrl);
    if (previousKey === undefined) Deno.env.delete("SUPABASE_PUBLISHABLE_KEY");
    else Deno.env.set("SUPABASE_PUBLISHABLE_KEY", previousKey);
  }
});

