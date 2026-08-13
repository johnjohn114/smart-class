import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://johnjohn114.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
  "Vary": "Origin",
};

function json(body: unknown, status=200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {...corsHeaders, "Content-Type": "application/json; charset=utf-8"},
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, {status:200, headers:corsHeaders});
  if (req.method !== "POST") return json({error:"Method Not Allowed"},405);

  try {
    const url=Deno.env.get("SUPABASE_URL");
    const anon=Deno.env.get("SUPABASE_ANON_KEY");
    const service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if(!url||!anon||!service) return json({error:"Edge Function 缺少必要環境變數。"},500);

    const auth=req.headers.get("Authorization")||"";
    if(!auth) return json({error:"未登入"},401);
    const callerClient=createClient(url,anon,{global:{headers:{Authorization:auth}}});
    const {data:{user:caller},error:callerError}=await callerClient.auth.getUser();
    if(callerError||!caller) return json({error:"登入狀態無效，請重新登入。"},401);

    const admin=createClient(url,service);
    const {data:profile,error:profileError}=await admin.from("profiles").select("role").eq("id",caller.id).maybeSingle();
    if(profileError) return json({error:profileError.message},500);
    if(profile?.role!=="admin") return json({error:"沒有管理員權限"},403);

    const body=await req.json();
    const email=String(body.email||"").trim().toLowerCase();
    const password=String(body.password||"");
    if(!email) return json({error:"請輸入訪客 Email"},400);
    if(password.length<8) return json({error:"統一密碼至少 8 碼"},400);

    const {data,error}=await admin.auth.admin.createUser({
      email,password,email_confirm:true
    });
    if(error) return json({error:error.message},400);

    const {error:profileInsert}=await admin.from("profiles").upsert({id:data.user.id,role:"visitor"});
    if(profileInsert){await admin.auth.admin.deleteUser(data.user.id);return json({error:"建立訪客身份失敗："+profileInsert.message},400);}
    const {error:visitorInsert}=await admin.from("visitor_accounts").insert({id:data.user.id,email,active:true});
    if(visitorInsert){await admin.auth.admin.deleteUser(data.user.id);return json({error:"建立訪客資料失敗："+visitorInsert.message},400);}
    return json({ok:true,id:data.user.id});
  } catch(e) {
    console.error(e);
    return json({error:e instanceof Error?e.message:String(e)},400);
  }
});
