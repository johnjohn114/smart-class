// Deploy with: supabase functions deploy send-announcement-push
// Required secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, FIREBASE_SERVICE_ACCOUNT_JSON
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

function b64url(input: Uint8Array | string) {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  bytes.forEach((b) => binary += String.fromCharCode(b));
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}
function pemToBytes(pem: string) {
  const body = pem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "");
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}
async function firebaseAccessToken(sa: any) {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = header + "." + claim;
  const key = await crypto.subtle.importKey(
    "pkcs8", pemToBytes(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"],
  );
  const signature = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned)));
  const assertion = unsigned + "." + b64url(signature);
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const result = await response.json();
  if (!response.ok || !result.access_token) throw new Error("Firebase OAuth token request failed");
  return result.access_token as string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const saRaw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!supabaseUrl || !serviceKey || !saRaw) return json({ error: "Server push configuration is incomplete" }, 500);

  const authorization = req.headers.get("Authorization") || "";
  const userToken = authorization.replace(/^Bearer\s+/i, "");
  if (!userToken) return json({ error: "Authentication required" }, 401);

  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
  const { data: userData, error: userError } = await admin.auth.getUser(userToken);
  if (userError || !userData.user) return json({ error: "Invalid session" }, 401);
  const { data: profile } = await admin.from("profiles").select("role").eq("id", userData.user.id).maybeSingle();
  if (profile?.role !== "admin") return json({ error: "Administrator permission required" }, 403);

  let payload: any;
  try { payload = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400); }
  const announcementId = String(payload.announcement_id || "");
  if (!announcementId) return json({ error: "announcement_id is required" }, 400);

  const { data: announcement, error: announcementError } = await admin
    .from("announcements")
    .select("id,title,content,published,push_enabled,push_sent_at")
    .eq("id", announcementId).maybeSingle();
  if (announcementError || !announcement) return json({ error: "Announcement not found" }, 404);
  if (!announcement.published || !announcement.push_enabled) return json({ error: "Push is not enabled for this published announcement" }, 409);
  if (announcement.push_sent_at) return json({ ok: true, already_sent: true });

  // Claim the announcement before sending so concurrent admin requests cannot duplicate a broadcast.
  const claimedAt = new Date().toISOString();
  const { data: claimed, error: claimError } = await admin.from("announcements")
    .update({ push_sent_at: claimedAt })
    .eq("id", announcementId).is("push_sent_at", null).select("id").maybeSingle();
  if (claimError) return json({ error: "Unable to claim push delivery" }, 500);
  if (!claimed) return json({ ok: true, already_sent: true });

  const { data: devices, error: deviceError } = await admin.from("device_push_tokens").select("token");
  if (deviceError) {
    await admin.from("announcements").update({ push_sent_at: null }).eq("id", announcementId);
    return json({ error: "Unable to load registered devices" }, 500);
  }
  if (!devices?.length) return json({ ok: true, sent: 0, message: "No registered Android devices yet" });

  let sa: any;
  try { sa = JSON.parse(saRaw); } catch {
    await admin.from("announcements").update({ push_sent_at: null }).eq("id", announcementId);
    return json({ error: "Firebase service account JSON is invalid" }, 500);
  }

  try {
    const accessToken = await firebaseAccessToken(sa);
    const text = String(announcement.content || "").replace(/\s+/g, " ").trim();
    const body = text.length > 150 ? text.slice(0, 147) + "..." : text;
    let sent = 0;
    let failed = 0;
    for (const device of devices) {
      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
        {
          method: "POST",
          headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
          body: JSON.stringify({
            message: {
              token: device.token,
              notification: { title: announcement.title, body: body || "有一則新公告" },
              data: { announcement_id: String(announcement.id), title: announcement.title },
              android: { priority: "HIGH", notification: { channel_id: "announcement_updates" } },
            },
          }),
        },
      );
      if (response.ok) sent++; else failed++;
    }
    return json({ ok: true, sent, failed, total: devices.length });
  } catch (error) {
    await admin.from("announcements").update({ push_sent_at: null }).eq("id", announcementId);
    return json({ error: error instanceof Error ? error.message : "FCM delivery failed" }, 502);
  }
});
