import { createMaintenanceHandler, parseActionRequest } from "../_shared/maintenance.ts";

Deno.serve(createMaintenanceHandler({
  method: "POST",
  auth: "required",
  rpc: "maintenance_event_action",
  parse: parseActionRequest,
}));
