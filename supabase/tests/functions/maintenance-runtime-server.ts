import {
  createMaintenanceHandler,
  parseActionRequest,
  parseAdminListRequest,
  parseCreateRequest,
  parseStatusRequest,
  parseUpdateRequest,
} from "../../functions/_shared/maintenance.ts";

const routes = new Map<string, (request: Request) => Promise<Response>>([
  ["/functions/v1/maintenance-status", createMaintenanceHandler({
    method: "GET", auth: "optional", rpc: "maintenance_status_public",
    parse: parseStatusRequest,
  })],
  ["/functions/v1/maintenance-admin-list", createMaintenanceHandler({
    method: "GET", auth: "required", rpc: "maintenance_admin_list",
    parse: parseAdminListRequest,
  })],
  ["/functions/v1/maintenance-event-create", createMaintenanceHandler({
    method: "POST", auth: "required", rpc: "maintenance_event_create",
    parse: parseCreateRequest,
  })],
  ["/functions/v1/maintenance-event-update", createMaintenanceHandler({
    method: "POST", auth: "required", rpc: "maintenance_event_update",
    parse: parseUpdateRequest,
  })],
  ["/functions/v1/maintenance-event-action", createMaintenanceHandler({
    method: "POST", auth: "required", rpc: "maintenance_event_action",
    parse: parseActionRequest,
  })],
]);

const port = Number(Deno.env.get("MAINTENANCE_RUNTIME_PORT") ?? "8002");
Deno.serve({ port, hostname: "127.0.0.1" }, async (request) => {
  const pathname = new URL(request.url).pathname;
  if (pathname === "/__health") return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { "Content-Type": "application/json" } });
  const route = routes.get(pathname);
  if (!route) {
    return new Response(JSON.stringify({
      ok: false,
      error: { code: "NOT_FOUND", message: "找不到測試路由" },
    }), { status: 404, headers: { "Content-Type": "application/json" } });
  }
  return await route(request);
});
