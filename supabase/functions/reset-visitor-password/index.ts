import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
    },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method Not Allowed" }, 405);
  }

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const anon = Deno.env.get("SUPABASE_ANON_KEY");
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!url || !anon || !service) {
      return json({ error: "Supabase Edge Function 環境變數未設定完整。" }, 500);
    }

    const auth = req.headers.get("Authorization") || "";
    if (!auth) return json({ error: "未登入" }, 401);

    const userClient = createClient(url, anon, {
      global: { headers: { Authorization: auth } },
    });

    const { data: { user: caller }, error: callerError } =
      await userClient.auth.getUser();

    if (callerError || !caller) {
      return json({ error: "登入狀態無效，請重新登入。" }, 401);
    }

    const admin = createClient(url, service);

    const { data: profile, error: profileError } = await admin
      .from("profiles")
      .select("role")
      .eq("id", caller.id)
      .maybeSingle();

    if (profileError) {
      return json({ error: "無法確認管理員權限：" + profileError.message }, 500);
    }

    if (profile?.role !== "admin") {
      return json({ error: "沒有管理員權限" }, 403);
    }

    const body = await req.json();
    const email = String(body.email || "").trim();
    const password = String(body.password || "");

    if (!email || password.length < 8) {
      return json({ error: "Email 與至少 8 碼密碼為必填" }, 400);
    }

    const { data: users, error: listError } =
      await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });

    if (listError) return json({ error: listError.message }, 400);

    const target = users.users.find(
      (u) => u.email?.toLowerCase() === email.toLowerCase(),
    );

    if (!target) return json({ error: "找不到訪客帳號" }, 404);

    const { data: visitor, error: visitorError } = await admin
      .from("visitor_accounts")
      .select("id")
      .eq("id", target.id)
      .maybeSingle();

    if (visitorError) {
      return json({ error: visitorError.message }, 500);
    }

    if (!visitor) return json({ error: "此帳號不是訪客帳號" }, 403);

    const { error } = await admin.auth.admin.updateUserById(
      target.id,
      { password },
    );

    if (error) return json({ error: error.message }, 400);

    return json({ ok: true });
  } catch (e) {
    console.error("reset-visitor-password error:", e);
    return json(
      { error: e instanceof Error ? e.message : String(e) },
      400,
    );
  }
});
