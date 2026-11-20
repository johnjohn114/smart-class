import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { buildPublicLeaderboard } from "./shared.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

function json(body: unknown, status = 200) {
  const cacheControl = status >= 200 && status < 300
    ? "public, max-age=60"
    : "no-store";

  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": cacheControl,
      "X-Content-Type-Options": "nosniff",
    },
  });
}

export async function handleRequest(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "GET") {
    return json({ error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "Leaderboard service is not configured" }, 503);
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error } = await adminClient
    .from("activity_member_stats")
    .select("nickname,attended_count,late_count,no_show_count,activity_points")
    .order("activity_points", { ascending: false })
    .order("attended_count", { ascending: false })
    .order("nickname", { ascending: true })
    .limit(100);

  if (error) {
    // Do not expose database errors or internal schema details publicly.
    return json({ error: "Unable to load activity leaderboard" }, 500);
  }

  return json(buildPublicLeaderboard(data ?? []));
}

if (import.meta.main) {
  Deno.serve(handleRequest);
}
