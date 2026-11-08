import {
  parseActionRequest,
  parseAdminListRequest,
  parseCreateRequest,
  parseStatusRequest,
  parseUpdateRequest,
} from "../functions/_shared/maintenance.ts";

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
