import { createMaintenanceHandler, parseAdminListRequest } from "../_shared/maintenance.ts";

Deno.serve(createMaintenanceHandler({
  method: "GET",
  auth: "required",
  rpc: "maintenance_admin_list",
  parse: parseAdminListRequest,
}));
