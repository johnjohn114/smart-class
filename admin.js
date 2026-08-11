function login(){
 const email=document.getElementById("email").value.trim(),password=document.getElementById("password").value;
 if(SUPABASE_URL.includes("請填入")){document.getElementById("loginError").textContent="請先依 README.md 設定 Supabase。";return}
 supaAuth(email,password);
}
async function supaAuth(email,password){
 const r=await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`,{
  method:"POST",headers:{"Content-Type":"application/json",apikey:SUPABASE_ANON_KEY},
  body:JSON.stringify({email,password})
 });
 if(!r.ok){document.getElementById("loginError").textContent="帳號或密碼錯誤";return}
 const data=await r.json();
 localStorage.setItem("access_token",data.access_token);
 localStorage.setItem("refresh_token",data.refresh_token);
 showDashboard();loadAdminNews();
}
function showDashboard(){document.getElementById("login").classList.add("hidden");document.getElementById("dashboard").classList.remove("hidden")}
function logout(){localStorage.clear();location.reload()}
if(localStorage.getItem("access_token"))showDashboard();

async function publish(){
 const title=document.getElementById("title").value.trim();
 const date=document.getElementById("date").value;
 const content=document.getElementById("content").value.trim();
 const msg=document.getElementById("publishMsg");
 if(!title||!content){msg.textContent="請填寫標題與內容";return}
 const r=await fetch(`${SUPABASE_URL}/rest/v1/announcements`,{
  method:"POST",
  headers:{"Content-Type":"application/json",apikey:SUPABASE_ANON_KEY,Authorization:`Bearer ${localStorage.getItem("access_token")}`,Prefer:"return=minimal"},
  body:JSON.stringify({title,content,date:date||new Date().toISOString().slice(0,10),published:true})
 });
 if(!r.ok){msg.textContent="發布失敗，請檢查登入或資料庫設定";return}
 msg.textContent="✅ 已發布";
 document.getElementById("title").value="";
 document.getElementById("date").value="";
 document.getElementById("content").value="";
 loadAdminNews();
}
async function loadAdminNews(){
 const box=document.getElementById("adminList");if(!box)return;
 const r=await fetch(`${SUPABASE_URL}/rest/v1/announcements?select=*&order=created_at.desc`,
 {headers:{apikey:SUPABASE_ANON_KEY,Authorization:`Bearer ${localStorage.getItem("access_token")}`}});
 const rows=await r.json();
 box.innerHTML=rows.map(x=>`<article class="notice"><div class="date">${escapeHtml(x.date||"")}</div><h3>${escapeHtml(x.title)}</h3><p>${escapeHtml(x.content).replace(/\n/g,"<br>")}</p><button onclick="removeNews('${x.id}')">刪除</button></article>`).join("")||'<div class="empty">目前沒有公告。</div>';
}
async function removeNews(id){
 if(!confirm("確定刪除這則公告？"))return;
 await fetch(`${SUPABASE_URL}/rest/v1/announcements?id=eq.${encodeURIComponent(id)}`,{
  method:"DELETE",headers:{apikey:SUPABASE_ANON_KEY,Authorization:`Bearer ${localStorage.getItem("access_token")}`}});
 loadAdminNews();
}
function escapeHtml(s){return String(s).replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]))}