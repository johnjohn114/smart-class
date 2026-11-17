import { createMaintenanceHandler, parseCreateRequest } from "../_shared/maintenance.ts";

Deno.serve(createMaintenanceHandler({
  method: "POST",
  auth: "required",
  rpc: "maintenance_event_create",
  parse: parseCreateRequest,
}));
