import { createMaintenanceHandler, parseStatusRequest } from "../_shared/maintenance.ts";

Deno.serve(createMaintenanceHandler({
  method: "GET",
  auth: "optional",
  rpc: "maintenance_status_public",
  parse: parseStatusRequest,
}));
