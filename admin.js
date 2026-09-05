const F=['site_name','hero_title','hero_text','hero_image','about_title','about_subtitle','about1_title','about1_text','about2_title','about2_text','features_title','features_subtitle','f1_title','f1_text','f2_title','f2_text','f3_title','f3_text','f4_title','f4_text','contact1','contact2','contact3'];
const $=id=>document.getElementById(id); const esc=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
function configured(){return typeof SUPABASE_URL!=='undefined'&&typeof SUPABASE_ANON_KEY!=='undefined'&&SUPABASE_URL&&SUPABASE_ANON_KEY&&!String(SUPABASE_URL).includes('你的')&&!String(SUPABASE_URL).includes('請填入')&&!String(SUPABASE_ANON_KEY).includes('你的')}
function auth(){const t=localStorage.getItem('access_token');return {'Content-Type':'application/json',apikey:SUPABASE_ANON_KEY,Authorization:'Bearer '+(t||SUPABASE_ANON_KEY)}}
function msg(id,t){if($(id))$(id).textContent=t}
async function login(){if(!configured()){msg('loginError','請把可用的 config.js 放回來。');return}const email=$('email').value.trim(),password=$('password').value;if(!email||!password){msg('loginError','請輸入 Email 與密碼。');return}msg('loginError','登入中…');try{const r=await fetch(SUPABASE_URL+'/auth/v1/token?grant_type=password',{method:'POST',headers:{'Content-Type':'application/json',apikey:SUPABASE_ANON_KEY},body:JSON.stringify({email,password})});const d=await r.json().catch(()=>({}));if(!r.ok||!d.access_token){msg('loginError',d.error_description||d.msg||'登入失敗。');return}localStorage.setItem('access_token',d.access_token);if(d.refresh_token)localStorage.setItem('refresh_token',d.refresh_token);const pr=await fetch(SUPABASE_URL+'/rest/v1/profiles?select=role&id=eq.'+encodeURIComponent(d.user?.id||'') ,{headers:{...auth(),'Authorization':'Bearer '+d.access_token}});const pa=pr.ok?await pr.json():[];if(pa[0]?.role!=='admin'){localStorage.removeItem('access_token');localStorage.removeItem('refresh_token');msg('loginError','此帳號不是管理員帳號。');return} $('login').classList.add('hidden');$('dashboard').classList.remove('hidden');await load() }catch(e){console.error(e);msg('loginError','無法連線到 Supabase。')}}

async function countTable(table, filter=''){
  const r=await fetch(SUPABASE_URL+'/rest/v1/'+table+'?select=id'+(filter?'&'+filter:''),{method:'HEAD',headers:{...auth(),Prefer:'count=exact'}});
  const range=r.headers.get('content-range')||'';
  const m=range.match(/\/([0-9]+)$/);
  return r.ok&&m?Number(m[1]):0;
}
async function dashboard(){
  if(!$('dashboardCards')||!configured()||!localStorage.getItem('access_token'))return;
  $('dashboardCards').innerHTML='<div class="loading">正在讀取儀表板…</div>';
  try{
    const now=new Date();
    const today=now.toISOString().slice(0,10);
    const in30=new Date(now.getTime()-30*86400000).toISOString();
    const [members,activeMembers,competitions,publishedCompetitions,products,activeProducts,coupons,supportOpen,notificationsUnread,newsPublished]=await Promise.all([
      countTable('visitor_accounts'),countTable('visitor_accounts','active=eq.true'),countTable('competitions'),countTable('competitions','published=eq.true'),countTable('products'),countTable('products','active=eq.true'),countTable('coupons'),countTable('support_tickets','status=eq.open'),countTable('notifications','read_at=is.null'),countTable('announcements','published=eq.true')
    ]);
    const card=(icon,label,value,sub,cls='')=>'<div class="dashCard '+cls+'"><div class="dashIcon">'+icon+'</div><div><div class="dashLabel">'+label+'</div><div class="dashValue">'+Number(value).toLocaleString()+'</div><div class="dashSub">'+sub+'</div></div></div>';
    $('dashboardCards').innerHTML=[
      card('👥','會員',members,'啟用 '+activeMembers+' 人','members'),
      card('🎮','活動／比賽',competitions,'已公布 '+publishedCompetitions+' 場','events'),
      card('📦','商品',products,'上架 '+activeProducts+' 件','products'),
      card('🎟️','優惠券',coupons,'目前紀錄總數','coupons'),
      card('💬','待處理客服',supportOpen,'尚未回覆','support'),
      card('🔔','未讀通知',notificationsUnread,'所有會員未讀','notice'),
      card('📢','已發布公告',newsPublished,'目前公開內容','news')
    ].join('');

    const [tickets,upcoming,news,recentMembers]=await Promise.all([
      fetch(SUPABASE_URL+'/rest/v1/support_tickets?select=id,subject,status,created_at&status=eq.open&order=created_at.asc&limit=5',{headers:auth()}).then(r=>r.ok?r.json():[]),
      fetch(SUPABASE_URL+'/rest/v1/competitions?select=id,name,category,event_date,published&published=eq.true&event_date=gte.'+today+'&order=event_date.asc&limit=5',{headers:auth()}).then(r=>r.ok?r.json():[]),
      fetch(SUPABASE_URL+'/rest/v1/announcements?select=id,title,category,published_at,pinned&published=eq.true&order=published_at.desc&limit=5',{headers:auth()}).then(r=>r.ok?r.json():[]),
      fetch(SUPABASE_URL+'/rest/v1/visitor_accounts?select=created_at&created_at=gte.'+encodeURIComponent(in30)+'&order=created_at.asc&limit=1000',{headers:auth()}).then(r=>r.ok?r.json():[])
    ]);
    $('dashboardTodo').innerHTML=(tickets.length?'<div class="dashTodoCount">💬 有 '+tickets.length+(supportOpen>tickets.length?'+'+ (supportOpen-tickets.length):'')+' 筆客服待處理</div>'+tickets.map(t=>'<button class="dashboardLink" data-dash-tab="supportTab"><span>💬 '+esc(t.subject)+'</span><small>'+esc(String(t.created_at).slice(0,16).replace('T',' '))+'</small></button>').join(''):'<div class="empty">🎉 目前沒有待處理客服。</div>')+'<button class="dashboardAction" data-dash-tab="supportTab">查看客服中心 →</button>';
    $('dashboardUpcoming').innerHTML=upcoming.length?upcoming.map(c=>'<button class="dashboardLink" data-dash-tab="competitionTab"><span>🎮 '+esc(c.name)+'</span><small>'+esc(c.event_date||'日期未設定')+' · '+esc(c.category||'')+'</small></button>').join(''):'<div class="empty">目前沒有近期活動。</div>';
    $('dashboardNews').innerHTML=news.length?news.map(n=>'<button class="dashboardLink" data-dash-tab="newsTab"><span>'+((n.pinned?'📌 ':'')+'📢 '+esc(n.title))+'</span><small>'+esc(n.category||'最新消息')+' · '+esc(String(n.published_at).slice(0,10))+'</small></button>').join(''):'<div class="empty">目前沒有已發布公告。</div>';

    const days=[]; for(let i=29;i>=0;i--){const d=new Date(now.getTime()-i*86400000);days.push(d.toISOString().slice(0,10));}
    const counts=Object.fromEntries(days.map(d=>[d,0])); recentMembers.forEach(x=>{const d=String(x.created_at).slice(0,10);if(counts[d]!=null)counts[d]++;});
    const max=Math.max(1,...Object.values(counts));
    $('dashboardMemberTrend').innerHTML=days.map(d=>'<div class="miniBarRow"><span>'+d.slice(5)+'</span><div class="miniBarTrack"><i style="width:'+Math.round(counts[d]/max*100)+'%"></i></div><b>'+counts[d]+'</b></div>').join('');
    document.querySelectorAll('[data-dash-tab]').forEach(b=>b.onclick=()=>{document.querySelector('[data-tab="'+b.dataset.dashTab+'"]').click(); if(b.classList.contains('dashboardAction')){if(b.dataset.dashTab==='newsTab'&&typeof clearAnnouncement==='function')clearAnnouncement();if(b.dataset.dashTab==='productTab'&&typeof clearProduct==='function')clearProduct();if(b.dataset.dashTab==='competitionTab'&&typeof clearCompetition==='function')clearCompetition();}});
  }catch(e){console.error('dashboard:',e);$('dashboardCards').innerHTML='<div class="empty">❌ 儀表板讀取失敗：'+esc(e.message||String(e))+'</div>'}
}
async function load(){await dashboard();await content();await news();await products();await visitors();await coupons();await competitions();await quickLinks();await tickets()}
async function content(){if(!configured()||!localStorage.getItem('access_token'))return;const r=await fetch(SUPABASE_URL+'/rest/v1/site_settings?select=*&id=eq.1',{headers:auth()});if(r.status===401){logout();return}if(!r.ok)return;const a=await r.json();if(a[0])F.forEach(k=>{if($(k))$(k).value=a[0][k]??''})}
async function save(){const body={};F.forEach(k=>body[k]=$(k)?.value||'');const r=await fetch(SUPABASE_URL+'/rest/v1/site_settings?id=eq.1',{method:'PATCH',headers:{...auth(),Prefer:'return=minimal'},body:JSON.stringify(body)});msg('contentMsg',r.ok?'✅ 已儲存':'❌ 儲存失敗：請檢查 RLS 權限。')}
async function publish(){const id=$('announcementId')?.value||'';const body={title:$('title').value.trim(),category:$('category').value,published_at:new Date($('published_at').value||new Date()).toISOString(),pinned:$('pinned').checked,content:$('content').value,link_url:$('linkUrl').value.trim()||null,link_label:$('linkLabel').value.trim()||null,published:true};if(!body.title||!body.content){msg('publishMsg','請填寫標題與內容。');return}const url=SUPABASE_URL+'/rest/v1/announcements'+(id?'?id=eq.'+encodeURIComponent(id):'');const r=await fetch(url,{method:id?'PATCH':'POST',headers:{...auth(),Prefer:'return=representation'},body:JSON.stringify(body)});msg('publishMsg',r.ok?'✅ 已儲存公告':'❌ 儲存失敗：請檢查 announcements RLS。');if(r.ok){clearAnnouncement();await news()}}
function clearAnnouncement(){$('title').value='';$('content').value='';$('category').value='最新消息';$('published_at').value='';$('pinned').checked=false;if($('linkUrl'))$('linkUrl').value='';if($('linkLabel'))$('linkLabel').value='';if($('announcementId'))$('announcementId').value=''}
async function news(){
  if(!$('adminList')||!configured()||!localStorage.getItem('access_token'))return;
  const r=await fetch(SUPABASE_URL+'/rest/v1/announcements?select=*&order=pinned.desc,published_at.desc,created_at.desc',{headers:auth()});
  if(!r.ok)return;
  const a=await r.json();
  window.__adminNews=a;
  renderAdminNews();
}
function renderAdminNews(){
  const a=window.__adminNews||[];
  const q=($('newsSearch')?.value||'').trim().toLowerCase();
  const status=$('newsStatusFilter')?.value||'all';
  const rows=a.filter(x=>{
    const hit=!q || [x.title,x.content,x.category].some(v=>String(v||'').toLowerCase().includes(q));
    const st=x.published?'published':'draft';
    return hit&&(status==='all'||status===st);
  });
  $('adminList').innerHTML=rows.map(x=>'<article class="notice"><div class="date">'+(x.published?'🟢 已發布':'📝 草稿')+' · '+(x.pinned?'📌 ':'')+esc(x.category)+' · '+esc(String(x.published_at||x.date||'').slice(0,16).replace('T',' '))+'</div><h3>'+esc(x.title)+'</h3><p>'+esc(x.content).replace(/\n/g,'<br>')+(x.link_url?'<br><a href="'+esc(x.link_url)+'" target="_blank" rel="noopener noreferrer">🔗 '+esc(x.link_label||'查看連結')+'</a>':'')+'</p><button data-edit="'+esc(x.id)+'">✏️ 編輯</button> <button data-del="'+esc(x.id)+'">🗑️ 刪除</button></article>').join('')||'<div class="empty">目前沒有符合條件的公告。</div>';
  document.querySelectorAll('[data-del]').forEach(b=>b.onclick=()=>delAnnouncement(b.dataset.del));
  document.querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>editAnnouncement(b.dataset.edit));
}
async function editAnnouncement(id){const r=await fetch(SUPABASE_URL+'/rest/v1/announcements?id=eq.'+encodeURIComponent(id)+'&select=*',{headers:auth()});const a=r.ok?await r.json():[];const x=a[0];if(!x)return;$('announcementId')?.setAttribute('value',x.id);if(!$('announcementId')){const i=document.createElement('input');i.type='hidden';i.id='announcementId';document.querySelector('#newsTab .editor').prepend(i);i.value=x.id}else $('announcementId').value=x.id;$('title').value=x.title||'';$('content').value=x.content||'';$('category').value=x.category||'最新消息';$('pinned').checked=!!x.pinned;$('published_at').value=x.published_at?new Date(x.published_at).toISOString().slice(0,16):'';if($('linkUrl'))$('linkUrl').value=x.link_url||'';if($('linkLabel'))$('linkLabel').value=x.link_label||'';document.querySelector('[data-tab="newsTab"]').click();}
async function delAnnouncement(id){if(!confirm('確定刪除這則公告？'))return;const r=await fetch(SUPABASE_URL+'/rest/v1/announcements?id=eq.'+encodeURIComponent(id),{method:'DELETE',headers:auth()});if(!r.ok){let d=await r.json().catch(()=>({}));alert('刪除失敗：'+(d.message||d.hint||('HTTP '+r.status)));return}await news()}
async function products(){
  if(!$('adminProducts')||!configured()||!localStorage.getItem('access_token'))return;
  const r=await fetch(SUPABASE_URL+'/rest/v1/products?select=*&order=created_at.desc',{headers:auth()});
  const a=r.ok?await r.json():[];
  window.__adminProducts=a; renderAdminProducts();
}
function renderAdminProducts(){
  const a=window.__adminProducts||[];
  const q=($('productSearch')?.value||'').trim().toLowerCase(); const status=$('productStatusFilter')?.value||'all';
  const rows=a.filter(p=>{const hit=!q||[p.name,p.category,p.description].some(v=>String(v||'').toLowerCase().includes(q));const ok=status==='all'||(status==='active'?!!p.active:!p.active);return hit&&ok});
  $('adminProducts').innerHTML=rows.map(p=>'<article class="productCard">'+(p.image_url?'<img src="'+esc(p.image_url)+'" alt="'+esc(p.name)+'">':'<div class="productImage">📦</div>')+'<div class="productBody"><div class="date">'+(p.active?'🟢 上架':'⚪ 下架')+' · '+esc(p.category||'')+'</div><h3>'+esc(p.name)+'</h3><p>'+esc(p.description||'')+'</p><strong>NT$ '+Number(p.price||0).toLocaleString()+'</strong><div><button data-pedit="'+p.id+'">✏️ 編輯</button> <button data-pdel="'+p.id+'">🗑️ 刪除</button></div></div></article>').join('')||'<div class="empty">目前沒有符合條件的商品。</div>';
  document.querySelectorAll('[data-pdel]').forEach(b=>b.onclick=()=>deleteProduct(b.dataset.pdel)); document.querySelectorAll('[data-pedit]').forEach(b=>b.onclick=()=>editProduct(b.dataset.pedit));
}
async function saveProduct(){const id=$('productId').value;const body={name:$('productName').value.trim(),category:$('productCategory').value.trim(),price:Number($('productPrice').value||0),image_url:$('productImage').value.trim(),description:$('productDescription').value,active:$('productActive').checked};if(!body.name){msg('productMsg','請輸入商品名稱。');return}const r=await fetch(SUPABASE_URL+'/rest/v1/products'+(id?'?id=eq.'+encodeURIComponent(id):''),{method:id?'PATCH':'POST',headers:{...auth(),Prefer:'return=representation'},body:JSON.stringify(body)});msg('productMsg',r.ok?'✅ 商品已儲存':'❌ 商品儲存失敗');if(r.ok){clearProduct();await products()}}
function clearProduct(){$('productId').value='';$('productName').value='';$('productCategory').value='';$('productPrice').value='';$('productImage').value='';$('productDescription').value='';$('productActive').checked=true}
async function editProduct(id){const r=await fetch(SUPABASE_URL+'/rest/v1/products?id=eq.'+encodeURIComponent(id)+'&select=*',{headers:auth()});const a=r.ok?await r.json():[];const p=a[0];if(!p)return;$('productId').value=p.id;$('productName').value=p.name||'';$('productCategory').value=p.category||'';$('productPrice').value=p.price||0;$('productImage').value=p.image_url||'';$('productDescription').value=p.description||'';$('productActive').checked=!!p.active;document.querySelector('[data-tab="productTab"]').click()}
async function deleteProduct(id){if(!confirm('確定刪除商品？'))return;const r=await fetch(SUPABASE_URL+'/rest/v1/products?id=eq.'+encodeURIComponent(id),{method:'DELETE',headers:auth()});if(!r.ok){alert('刪除失敗：請檢查 products RLS。');return}await products()}
async function visitors(){
  if(!$('visitorList')||!configured()||!localStorage.getItem('access_token'))return;
  const r=await fetch(SUPABASE_URL+'/rest/v1/visitor_accounts?select=*&order=created_at.desc',{headers:auth()});
  const a=r.ok?await r.json():[];
  const pr=await fetch(SUPABASE_URL+'/rest/v1/profiles?select=id,nickname,member_no,role,created_at&role=eq.visitor',{headers:auth()}); const ps=pr.ok?await pr.json():[]; const pm=new Map(ps.map(x=>[x.id,x]));
  $('visitorList').innerHTML=a.map(v=>{const p=pm.get(v.id)||{};return '<article class="notice"><div class="date">'+(v.active?'🟢 啟用':'⚪ 停用')+' · 會員 '+esc(p.member_no!=null?String(p.member_no).padStart(3,'0'):'—')+'</div><h3>'+esc(p.nickname||v.email)+'</h3><p><b>Email：</b>'+esc(v.email)+'</p><label>暱稱<input data-vnick="'+esc(v.id)+'" value="'+esc(p.nickname||'')+'"></label><button data-vsave="'+esc(v.id)+'">💾 儲存暱稱</button> <button data-vdel="'+esc(v.id)+'">🗑️ 刪除訪客</button></article>'}).join('')||'<div class="empty">目前沒有訪客帳號。</div>';document.querySelectorAll('[data-vdel]').forEach(b=>b.onclick=()=>deleteVisitor(b.dataset.vdel));document.querySelectorAll('[data-vsave]').forEach(b=>b.onclick=()=>saveVisitorNickname(b.dataset.vsave));
  const sel=$('couponVisitor');
  if(sel) sel.innerHTML='<option value="all">全部訪客</option>'+a.filter(v=>v.active).map(v=>'<option value="'+esc(v.id)+'">'+esc(v.email)+'</option>').join('');
}
async function callEdge(path,body){
  const r=await fetch(SUPABASE_URL+'/functions/v1/'+path,{method:'POST',headers:auth(),body:JSON.stringify(body)});
  const d=await r.json().catch(()=>({}));
  if(!r.ok)throw new Error(d.error||d.message||('HTTP '+r.status));
  return d;
}
async function createVisitor(){
  const email=$('visitorAccountEmail').value.trim();
  const password=$('sharedVisitorPassword').value;
  if(!email){msg('visitorMsg','請輸入訪客 Email。');return}
  if(password.length<8){msg('visitorMsg','統一密碼至少 8 碼。');return}
  try{
    await callEdge('create-visitor',{email,password});
    msg('visitorMsg','✅ 訪客帳號已建立，請使用這組統一密碼登入。');
    $('visitorAccountEmail').value='';
    await visitors();
  }catch(e){msg('visitorMsg','❌ '+e.message)}
}

async function saveVisitorNickname(id){const el=document.querySelector('[data-vnick="'+CSS.escape(id)+'"]');const nickname=el?.value.trim()||'';if(!nickname){alert('請輸入暱稱。');return}const r=await fetch(SUPABASE_URL+'/rest/v1/profiles?id=eq.'+encodeURIComponent(id),{method:'PATCH',headers:{...auth(),Prefer:'return=minimal'},body:JSON.stringify({nickname})});if(!r.ok){const d=await r.json().catch(()=>({}));alert('儲存暱稱失敗：'+(d.message||d.hint||('HTTP '+r.status)));return}await visitors()}

async function createNotifications(rows){
  if(!rows.length)return;
  const r=await fetch(SUPABASE_URL+'/rest/v1/notifications',{method:'POST',headers:{...auth(),Prefer:'return=minimal'},body:JSON.stringify(rows)});
  if(!r.ok){const d=await r.json().catch(()=>({}));throw new Error(d.message||d.hint||('通知建立失敗 HTTP '+r.status));}
}

async function notifications(){
  if(!$('adminNotifications')||!configured()||!localStorage.getItem('access_token'))return;
  const r=await fetch(SUPABASE_URL+'/rest/v1/notifications?select=*&order=created_at.desc',{headers:auth()});
  const a=r.ok?await r.json():[];
  const pr=await fetch(SUPABASE_URL+'/rest/v1/profiles?select=id,nickname,member_no&role=eq.visitor',{headers:auth()});
  const ps=pr.ok?await pr.json():[];const pm=new Map(ps.map(x=>[x.id,x]));
  $('adminNotifications').innerHTML=a.map(n=>{const p=pm.get(n.user_id)||{};return '<article class="notice"><div class="date">'+esc(n.type||'一般')+' · '+esc(p.nickname||'會員')+' · '+(p.member_no!=null?'會員 '+esc(String(p.member_no).padStart(3,'0')):'')+' · '+esc(String(n.created_at).slice(0,16).replace('T',' '))+'</div><h3>'+esc(n.title)+'</h3><p>'+esc(n.content).replace(/\n/g,'<br>')+'</p><button data-ndel="'+esc(n.id)+'">🗑️ 刪除</button></article>'}).join('')||'<div class="empty">目前沒有通知紀錄。</div>';
  document.querySelectorAll('[data-ndel]').forEach(b=>b.onclick=()=>deleteNotification(b.dataset.ndel));
  const vs=await fetch(SUPABASE_URL+'/rest/v1/visitor_accounts?select=id,email&active=eq.true',{headers:auth()});const va=vs.ok?await vs.json():[];
  if($('notificationUser'))$('notificationUser').innerHTML='<option value="all">全部會員</option>'+va.map(v=>{const p=pm.get(v.id)||{};return '<option value="'+esc(v.id)+'">會員 '+esc(p.member_no!=null?String(p.member_no).padStart(3,'0'):'—')+'｜'+esc(p.nickname||v.email)+'</option>'}).join('');
}
async function createNotification(){const title=$('notificationTitle').value.trim(),content=$('notificationContent').value.trim(),type=$('notificationType').value.trim()||'一般',target=$('notificationUser').value;if(!title||!content){msg('notificationMsg','請填寫標題與內容。');return}try{let rows=[];if(target==='all'){const r=await fetch(SUPABASE_URL+'/rest/v1/visitor_accounts?select=id&active=eq.true',{headers:auth()});const a=r.ok?await r.json():[];rows=a.map(v=>({user_id:v.id,title,content,type}));}else rows=[{user_id:target,title,content,type}];if(!rows.length){msg('notificationMsg','目前沒有可發送的會員。');return}const r=await fetch(SUPABASE_URL+'/rest/v1/notifications',{method:'POST',headers:{...auth(),Prefer:'return=minimal'},body:JSON.stringify(rows)});if(!r.ok)throw new Error('HTTP '+r.status);msg('notificationMsg','✅ 通知已發送。');$('notificationTitle').value='';$('notificationContent').value='';await notifications()}catch(e){msg('notificationMsg','❌ '+e.message)}}
async function deleteNotification(id){if(!confirm('確定刪除這則通知？'))return;const r=await fetch(SUPABASE_URL+'/rest/v1/notifications?id=eq.'+encodeURIComponent(id),{method:'DELETE',headers:auth()});if(!r.ok){alert('刪除失敗 HTTP '+r.status);return}await notifications()}

async function setSharedVisitorPassword(){
  const password=$('sharedVisitorPassword').value;
  if(password.length<8){msg('sharedPasswordMsg','統一密碼至少 8 碼。');return}
  try{
    msg('sharedPasswordMsg','正在更新所有訪客密碼…');
    const vr=await fetch(SUPABASE_URL+'/rest/v1/visitor_accounts?select=email&active=eq.true',{headers:auth()});
    const visitors=vr.ok?await vr.json():[];
    if(!vr.ok)throw new Error('無法取得訪客清單 HTTP '+vr.status);
    if(!visitors.length){msg('sharedPasswordMsg','目前沒有啟用中的訪客。');return}
    let count=0;
    for(const v of visitors){
      await callEdge('reset-visitor-password',{email:v.email,password});
      count++;
    }
    msg('sharedPasswordMsg','✅ 已將統一密碼套用到 '+count+' 位訪客。');
  }catch(e){msg('sharedPasswordMsg','❌ '+e.message)}
}
async function deleteVisitor(id){
  if(!id)return;
  if(!confirm('確定要刪除這個訪客帳號？這會同時刪除其優惠券、客服紀錄與登入帳號，無法復原。'))return;
  try{await callEdge('delete-visitor',{user_id:id});msg('visitorMsg','✅ 訪客帳號已刪除。');await visitors()}
  catch(e){msg('visitorMsg','❌ '+e.message)}
}
async function coupons(){
  if(!$('adminCoupons')||!configured()||!localStorage.getItem('access_token'))return;
  await visitors();
  const r=await fetch(SUPABASE_URL+'/rest/v1/coupons?select=*,visitor_accounts(email)&order=created_at.desc',{headers:auth()});
  const a=r.ok?await r.json():[]; window.__adminCoupons=a; renderAdminCoupons();
}
function renderAdminCoupons(){
  const q=($('couponSearch')?.value||'').trim().toLowerCase(); const a=window.__adminCoupons||[];
  const rows=a.filter(c=>!q||[c.title,c.code,c.visitor_accounts?.email].some(v=>String(v||'').toLowerCase().includes(q)));
  $('adminCoupons').innerHTML=rows.map(c=>'<article class="notice"><div class="date">'+esc(c.visitor_accounts?.email||'')+' · '+esc(c.used?'⚫ 已使用':(c.expires_at&&new Date(c.expires_at)<new Date()?'⚪ 已過期':'🟢 可使用'))+' · '+esc(c.expires_at?String(c.expires_at).slice(0,10):'無期限')+'</div><h3>🎟️ '+esc(c.title)+'</h3><p>'+esc(c.description||'')+'</p><p><b>優惠碼：</b>'+esc(c.code)+(c.discount?'　<b>'+esc(c.discount)+'</b>':'')+'</p><button data-cdel="'+esc(c.id)+'">🗑️ 刪除優惠券</button></article>').join('')||'<div class="empty">目前沒有符合條件的優惠券。</div>';
  document.querySelectorAll('[data-cdel]').forEach(b=>b.onclick=()=>deleteCoupon(b.dataset.cdel));
}
async function createCoupon(){
  const title=$('couponTitle').value.trim(), description=$('couponDescription').value.trim(), code=$('couponCode').value.trim(), discount=$('couponDiscount').value.trim(), expires=$('couponExpires').value, target=$('couponVisitor').value;
  if(!title||!code){msg('couponMsg','請至少填寫優惠券名稱與優惠碼。');return}
  const body={title,description,code,discount:discount||null,expires_at:expires?expires+'T23:59:59Z':null};
  try{
    let targets=[];
    if(target==='all'){
      const vr=await fetch(SUPABASE_URL+'/rest/v1/visitor_accounts?select=id&active=eq.true',{headers:auth()});
      targets=vr.ok?await vr.json():[];
      if(!targets.length){msg('couponMsg','目前沒有啟用中的訪客。');return}
      const rows=targets.map(v=>({...body,user_id:v.id}));
      const r=await fetch(SUPABASE_URL+'/rest/v1/coupons',{method:'POST',headers:{...auth(),Prefer:'return=minimal'},body:JSON.stringify(rows)});
      if(!r.ok)throw new Error('發送失敗 HTTP '+r.status);
    }else{
      targets=[{id:target}]; body.user_id=target;
      const r=await fetch(SUPABASE_URL+'/rest/v1/coupons',{method:'POST',headers:{...auth(),Prefer:'return=minimal'},body:JSON.stringify(body)});
      if(!r.ok)throw new Error('發送失敗 HTTP '+r.status);
    }
    try{await createNotifications(targets.map(v=>({user_id:v.id,type:'優惠券',title:'🎟️ 新優惠券已送達',content:title+(discount?'｜'+discount:'')+(expires?'｜有效至 '+expires:'')})))}catch(e){console.error('優惠券通知建立失敗:',e)}
    msg('couponMsg','✅ 優惠券已發送。');
    ['couponTitle','couponDescription','couponCode','couponDiscount','couponExpires'].forEach(id=>$(id).value='');
    await coupons();
  }catch(e){msg('couponMsg','❌ '+e.message)}
}
async function deleteCoupon(id){
  if(!confirm('確定刪除這張優惠券？'))return;
  const r=await fetch(SUPABASE_URL+'/rest/v1/coupons?id=eq.'+encodeURIComponent(id),{method:'DELETE',headers:auth()});
  if(!r.ok){alert('刪除失敗：請檢查 coupons RLS。');return}
  await coupons();
}
async function quickLinks(){
  if(!$('adminQuickLinks')||!configured()||!localStorage.getItem('access_token'))return;
  const r=await fetch(SUPABASE_URL+'/rest/v1/quick_links?select=*&order=sort_order.asc,created_at.asc',{headers:auth()});
  const a=r.ok?await r.json():[];
  $('adminQuickLinks').innerHTML=a.map(q=>'<article class="notice quickLinkAdminItem"><div class="date">'+(q.visible?'🟢 顯示':'⚪ 隱藏')+' · 排序 '+Number(q.sort_order||0)+'</div><h3>'+esc(q.icon||'🔗')+' '+esc(q.name)+'</h3><p>'+esc(q.url)+'</p><button data-ql-edit="'+esc(q.id)+'">✏️ 編輯</button> <button data-ql-toggle="'+esc(q.id)+'" data-visible="'+(!q.visible)+'">'+(q.visible?'🙈 隱藏':'👁️ 顯示')+'</button> <button data-ql-del="'+esc(q.id)+'">🗑️ 刪除</button></article>').join('')||'<div class="empty">目前沒有快速連結。</div>';
  document.querySelectorAll('[data-ql-edit]').forEach(b=>b.onclick=()=>editQuickLink(b.dataset.qlEdit));
  document.querySelectorAll('[data-ql-toggle]').forEach(b=>b.onclick=()=>toggleQuickLink(b.dataset.qlToggle,b.dataset.visible==='true'));
  document.querySelectorAll('[data-ql-del]').forEach(b=>b.onclick=()=>deleteQuickLink(b.dataset.qlDel));
}
function clearQuickLink(){
  $('quickLinkId').value='';$('quickLinkName').value='';$('quickLinkUrl').value='';$('quickLinkIcon').value='';$('quickLinkSort').value='1';$('quickLinkVisible').checked=true;msg('quickLinkMsg','');
}
async function saveQuickLink(){
  const id=$('quickLinkId').value,name=$('quickLinkName').value.trim(),url=$('quickLinkUrl').value.trim(),icon=$('quickLinkIcon').value.trim()||null,sort_order=Number($('quickLinkSort').value||1),visible=$('quickLinkVisible').checked;
  if(!name||!url){msg('quickLinkMsg','請填寫名稱與連結網址。');return}
  if(!Number.isInteger(sort_order)||sort_order<1){msg('quickLinkMsg','排序必須是正整數。');return}
  const r=await fetch(SUPABASE_URL+'/rest/v1/quick_links'+(id?'?id=eq.'+encodeURIComponent(id):''),{method:id?'PATCH':'POST',headers:{...auth(),Prefer:'return=representation'},body:JSON.stringify({name,url,icon,sort_order,visible})});
  const d=await r.json().catch(()=>[]);
  if(!r.ok){msg('quickLinkMsg','❌ 儲存失敗：'+(d.message||d.hint||('HTTP '+r.status)));return}
  msg('quickLinkMsg','✅ 快速連結已儲存。');clearQuickLink();await quickLinks();
}
async function editQuickLink(id){
  const r=await fetch(SUPABASE_URL+'/rest/v1/quick_links?id=eq.'+encodeURIComponent(id)+'&select=*',{headers:auth()});
  const a=r.ok?await r.json():[];const q=a[0];if(!q)return;
  $('quickLinkId').value=q.id;$('quickLinkName').value=q.name||'';$('quickLinkUrl').value=q.url||'';$('quickLinkIcon').value=q.icon||'';$('quickLinkSort').value=q.sort_order||1;$('quickLinkVisible').checked=!!q.visible;
}
async function toggleQuickLink(id,visible){
  const r=await fetch(SUPABASE_URL+'/rest/v1/quick_links?id=eq.'+encodeURIComponent(id),{method:'PATCH',headers:{...auth(),Prefer:'return=minimal'},body:JSON.stringify({visible})});
  if(!r.ok){alert('更新顯示狀態失敗：HTTP '+r.status);return}await quickLinks();
}
async function deleteQuickLink(id){
  if(!confirm('確定刪除這個快速連結？'))return;
  const r=await fetch(SUPABASE_URL+'/rest/v1/quick_links?id=eq.'+encodeURIComponent(id),{method:'DELETE',headers:auth()});
  if(!r.ok){const d=await r.json().catch(()=>({}));alert('刪除失敗：'+(d.message||d.hint||('HTTP '+r.status)));return}
  await quickLinks();
}

async function tickets(){
  if(!$('ticketList')||!configured()||!localStorage.getItem('access_token'))return;
  const r=await fetch(SUPABASE_URL+'/rest/v1/support_tickets?select=*&order=created_at.desc',{headers:auth()});
  const a=r.ok?await r.json():[]; window.__adminTickets=a; renderTickets();
}
function renderTickets(){
  const a=window.__adminTickets||[]; const q=($('supportSearch')?.value||'').trim().toLowerCase(); const status=$('supportStatusFilter')?.value||'all';
  const rows=a.filter(t=>{const hit=!q||[t.subject,t.message,t.admin_reply].some(v=>String(v||'').toLowerCase().includes(q));return hit&&(status==='all'||String(t.status||'')===status)});
  $('ticketList').innerHTML=rows.map(t=>'<article class="notice"><div class="date">'+(t.status==='open'?'🟠 待處理':'🟢 已回覆')+' · '+esc(String(t.created_at).slice(0,16).replace('T',' '))+'</div><h3>'+esc(t.subject)+'</h3><p>'+esc(t.message).replace(/\n/g,'<br>')+'</p><label>管理員回覆<textarea data-reply="'+t.id+'" rows="4">'+esc(t.admin_reply||'')+'</textarea></label><button data-replybtn="'+t.id+'">💬 儲存回覆</button></article>').join('')||'<div class="empty">目前沒有符合條件的客服訊息。</div>';
  document.querySelectorAll('[data-replybtn]').forEach(b=>b.onclick=()=>replyTicket(b.dataset.replybtn));
}
async function replyTicket(id){const ta=document.querySelector('[data-reply="'+CSS.escape(id)+'"]');const reply=ta?ta.value.trim():'';const old=await fetch(SUPABASE_URL+'/rest/v1/support_tickets?id=eq.'+encodeURIComponent(id)+'&select=id,user_id,admin_reply',{headers:auth()});const ticket=(old.ok?(await old.json()):[])[0];const r=await fetch(SUPABASE_URL+'/rest/v1/support_tickets?id=eq.'+encodeURIComponent(id),{method:'PATCH',headers:{...auth(),Prefer:'return=minimal'},body:JSON.stringify({admin_reply:reply,status:reply?'answered':'open'})});if(r.ok&&reply&&ticket?.user_id&&reply!==String(ticket.admin_reply||'')){try{await createNotifications([{user_id:ticket.user_id,type:'客服',title:'💬 客服已有新回覆',content:'你的客服問題已有管理員回覆，請到「我的 → 我的客服」查看。'}])}catch(e){console.error(e)}}alert(r.ok?'已儲存回覆。':'儲存失敗。');if(r.ok)await tickets()}


async function loadCompetitionRegistrations(competitionId){
  const panel=$('competitionRegistrationPanel'),box=$('competitionRegistrations'); if(!panel||!box||!competitionId)return;
  panel.classList.remove('hidden'); panel.dataset.competitionId=competitionId;
  const r=await fetch(SUPABASE_URL+'/rest/v1/competition_registrations?select=*&competition_id=eq.'+encodeURIComponent(competitionId)+'&order=created_at.asc',{headers:auth()});
  const rows=r.ok?await r.json():[]; window.__competitionRegistrations=rows; renderCompetitionRegistrations();
}
function registrationAdminStatus(x){return {active:'🟢 已報名',pending:'🟡 待審核',approved:'🟢 已通過',rejected:'🔴 未通過',cancelled:'⚪ 已取消'}[x]||x}
function renderCompetitionRegistrations(){
  const box=$('competitionRegistrations');if(!box)return;const a=window.__competitionRegistrations||[];const q=($('registrationSearch')?.value||'').trim().toLowerCase();const st=$('registrationStatusFilter')?.value||'all';
  const rows=a.filter(x=>{const hit=!q||[x.member_no,x.nickname,x.email,x.note].some(v=>String(v||'').toLowerCase().includes(q));return hit&&(st==='all'||x.status===st)});
  box.innerHTML=rows.map(x=>{const actions=(x.status==='pending')?'<button type="button" class="btn secondary" data-reg-approve="'+esc(x.id)+'">✅ 通過</button> <button type="button" class="btn secondary" data-reg-reject="'+esc(x.id)+'">❌ 拒絕</button> ':'';return '<article class="notice"><div class="date">'+registrationAdminStatus(x.status)+' · '+esc(String(x.created_at).slice(0,16).replace('T',''))+'</div><h3>會員 '+esc(x.member_no!=null?String(x.member_no).padStart(3,'0'):'—')+'｜'+esc(x.nickname||'')+'</h3><p>Email：'+esc(x.email||'—')+(x.note?'<br>備註：'+esc(x.note):'')+'</p>'+(x.custom_fields&&Object.keys(x.custom_fields).length?'<p>自訂欄位：'+esc(JSON.stringify(x.custom_fields))+'</p>':'')+'<div class="competitionActions">'+actions+'</div><small>報名 ID：'+esc(x.id)+'</small></article>'}).join('')||'<div class="empty">目前沒有符合條件的報名資料。</div>';
  box.querySelectorAll('[data-reg-approve]').forEach(b=>b.onclick=()=>reviewCompetitionRegistration(b.dataset.regApprove,'approved'));
  box.querySelectorAll('[data-reg-reject]').forEach(b=>b.onclick=()=>reviewCompetitionRegistration(b.dataset.regReject,'rejected'));
}
async function reviewCompetitionRegistration(id,status){
  const row=(window.__competitionRegistrations||[]).find(x=>x.id===id); if(!row)return;
  const action=status==='approved'?'通過':'拒絕'; if(!confirm('確定要'+action+'這筆報名嗎？'))return;
  const r=await fetch(SUPABASE_URL+'/rest/v1/competition_registrations?id=eq.'+encodeURIComponent(id),{method:'PATCH',headers:{...auth(),Prefer:'return=minimal'},body:JSON.stringify({status})});
  if(!r.ok){const d=await r.json().catch(()=>({}));alert('操作失敗：'+(d.message||d.hint||('HTTP '+r.status)));return}
  if(row.user_id){try{await fetch(SUPABASE_URL+'/rest/v1/notifications',{method:'POST',headers:{...auth(),Prefer:'return=minimal'},body:JSON.stringify([{user_id:row.user_id,type:'比賽',title:'📝 報名審核結果',content:'「'+(window.__currentCompetitionName||'活動／比賽')+'」的報名已'+(status==='approved'?'通過':'拒絕')+'。'}])})}catch(e){console.error(e)}}
  await loadCompetitionRegistrations($('competitionRegistrationPanel').dataset.competitionId);
}
function exportCompetitionRegistrations(){
  const rows=window.__competitionRegistrations||[]; if(!rows.length){alert('目前沒有報名資料可匯出。');return}
  const headers=['會員編號','暱稱','Email','狀態','備註','建立時間','取消時間','自訂欄位'];
  const escCsv=v=>'"'+String(v??'').replace(/"/g,'""')+'"';
  const lines=[headers.map(escCsv).join(',')]; rows.forEach(x=>lines.push([x.member_no!=null?String(x.member_no).padStart(3,'0'):'',x.nickname,x.email,registrationAdminStatus(x.status).replace(/^\S+ /,''),x.note,x.created_at,x.cancelled_at,JSON.stringify(x.custom_fields||{})].map(escCsv).join(',')));
  const blob=new Blob(['\ufeff'+lines.join('\r\n')],{type:'text/csv;charset=utf-8'}); const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='報名名單_'+($('competitionName')?.value.trim()||'活動')+'.csv';a.click();setTimeout(()=>URL.revokeObjectURL(a.href),1000);
}

function clearCompetition(){
  if($('competitionId'))$('competitionId').value='';
  $('competitionName').value='';
  $('competitionCategory').value='Minecraft';
  $('competitionDate').value='';
  $('competitionRegistrationDeadline').value='';
  $('competitionRegistrationCapacity').value='';
  $('competitionRegistrationApproval').checked=false;
  $('competitionRegistrationFields').value='';
  $('competitionDescription').value='';
  $('competitionResults').innerHTML='';
  $('competitionRegistrationPanel')?.classList.add('hidden');
  msg('competitionMsg','');
  addCompetitionResult();
}
function addCompetitionResult(data={}){
  const box=$('competitionResults');
  if(!box)return;
  const row=document.createElement('div');
  row.className='resultRow';
  row.innerHTML='<label>名次<input type="number" min="1" class="resultPlace" value="'+esc(data.place??(box.children.length+1))+'"></label><label>玩家名稱<input class="resultPlayer" value="'+esc(data.player_name||'')+'" placeholder="玩家名稱"></label><label>綁定會員<select class="resultMember"><option value="">不綁定</option></select></label><label>分數<input type="number" step="0.01" class="resultScore" value="'+esc(data.score??'')+'" placeholder="可留空"></label><label>獎項<input class="resultPrize" value="'+esc(data.prize||'')+'" placeholder="例如：冠軍"></label><button type="button" class="removeResult">🗑️</button>';
  row.querySelector('.removeResult').onclick=()=>row.remove();
  box.appendChild(row); loadResultMemberOptions(row,data.user_id||'');
}
async function loadResultMemberOptions(row,selected){const sel=row.querySelector('.resultMember');if(!sel)return;let a=window.__competitionMembers;if(!a){const r=await fetch(SUPABASE_URL+'/rest/v1/profiles?select=id,nickname,member_no&role=eq.visitor&order=member_no.asc',{headers:auth()});a=r.ok?await r.json():[];window.__competitionMembers=a}sel.innerHTML='<option value="">不綁定</option>'+a.map(x=>'<option value="'+esc(x.id)+'">會員 '+esc(x.member_no!=null?String(x.member_no).padStart(3,'0'):'—')+'｜'+esc(x.nickname||'會員')+'</option>').join('');sel.value=selected||'';sel.onchange=()=>{const p=a.find(x=>x.id===sel.value);if(p)row.querySelector('.resultPlayer').value=p.nickname||row.querySelector('.resultPlayer').value;};}

function getCompetitionResults(){
  return [...document.querySelectorAll('#competitionResults .resultRow')].map(row=>({
    place:Number(row.querySelector('.resultPlace').value||0),
    player_name:row.querySelector('.resultPlayer').value.trim(),
    score:row.querySelector('.resultScore').value===''?null:Number(row.querySelector('.resultScore').value),
    prize:row.querySelector('.resultPrize').value.trim()||null,
    user_id:row.querySelector('.resultMember')?.value||null
  })).filter(x=>x.player_name).sort((a,b)=>a.place-b.place);
}

async function competitionCategories(){
  if(!$('competitionCategory')||!configured()||!localStorage.getItem('access_token'))return;
  try{
    const r=await fetch(SUPABASE_URL+'/rest/v1/competition_categories?select=id,name,parent_category&order=name.asc',{headers:auth()});
    if(!r.ok)throw new Error('無法讀取分類 HTTP '+r.status);
    const rows=await r.json();
    const sel=$('competitionCategory');
    const current=sel.value;
    sel.innerHTML=rows.map(c=>'<option value="'+esc(c.name)+'">'+esc(c.name)+'</option>').join('');
    if(current && rows.some(c=>c.name===current))sel.value=current;
    else if(rows[0])sel.value=rows[0].name;

    const box=$('competitionCategoryList');
    if(box){
      box.innerHTML=rows.map(c=>{
        const safeId=esc(c.id);
        const parentLabel=c.parent_category==='蛋仔'?'↳ 蛋仔派對子分類':'最外層分類'; const buttons=(c.name==='Minecraft'||c.name==='蛋仔') ? '<span class="sub">預設分類</span>' : '<span class="sub">'+parentLabel+'</span> <button type="button" class="btn secondary categoryEdit" data-cat-edit="'+safeId+'" data-cat-name="'+esc(c.name)+'">✏️ 修改</button> <button type="button" class="btn secondary categoryDelete" data-cat-del="'+safeId+'" data-cat-name="'+esc(c.name)+'">🗑️ 刪除</button>';
        return '<article class="notice"><div class="date">'+(false?'⭐ ':'')+esc(c.name)+'</div>'+buttons+'</article>';
      }).join('') || '<div class="empty">目前沒有分類。</div>';
      box.querySelectorAll('[data-cat-edit]').forEach(b=>b.onclick=()=>editCompetitionCategory(b.dataset.catEdit,b.dataset.catName));
      box.querySelectorAll('[data-cat-del]').forEach(b=>b.onclick=()=>deleteCompetitionCategory(b.dataset.catDel,b.dataset.catName));
    }
  }catch(e){
    console.error('competitionCategories:',e);
    msg('competitionMsg','❌ '+(e instanceof Error?e.message:String(e)));
  }
}
async function addCompetitionCategory(){
  const input=$('competitionCategoryNew');
  const name=input?.value.trim()||'';
  if(!name){alert('請輸入分類名稱。');return}
  try{
    const r=await fetch(SUPABASE_URL+'/rest/v1/competition_categories',{
      method:'POST',
      headers:{...auth(),Prefer:'return=representation'},
      body:JSON.stringify({name,parent_category:null})
    });
    const d=await r.json().catch(()=>[]);
    if(!r.ok)throw new Error(d.message||d.hint||('HTTP '+r.status));
    input.value='';
    await competitionCategories();
    $('competitionCategory').value=name;
    msg('competitionMsg','✅ 已新增分類：'+name);
  }catch(e){
    alert('新增分類失敗：'+(e instanceof Error?e.message:String(e)));
  }
}
async function editCompetitionCategory(id,currentName){
  if(!id)return;
  const next=prompt('請輸入新的分類名稱：',currentName||'');
  if(next===null)return;
  const name=next.trim();
  if(!name){alert('分類名稱不能為空白。');return}
  const parentInput=prompt('要放在哪個分類底下？\n留白 = 最外層\n輸入「蛋仔」 = 放到蛋仔派對子選單', currentName==='蛋仔' ? '' : '');
  if(parentInput===null)return;
  const parent_category=parentInput.trim()==='蛋仔'?'蛋仔':null;
  try{
    const used=await fetch(SUPABASE_URL+'/rest/v1/competitions?select=id&category=eq.'+encodeURIComponent(currentName)+'&limit=1',{headers:auth()});
    const usedRows=used.ok?await used.json():[];
    const r=await fetch(SUPABASE_URL+'/rest/v1/competition_categories?id=eq.'+encodeURIComponent(id),{
      method:'PATCH',
      headers:{...auth(),Prefer:'return=representation'},
      body:JSON.stringify({name,parent_category})
    });
    const d=await r.json().catch(()=>[]);
    if(!r.ok)throw new Error(d.message||d.hint||('HTTP '+r.status));
    if(usedRows.length){
      const u=await fetch(SUPABASE_URL+'/rest/v1/competitions?category=eq.'+encodeURIComponent(currentName),{
        method:'PATCH',
        headers:{...auth(),Prefer:'return=minimal'},
        body:JSON.stringify({category:name})
      });
      if(!u.ok)throw new Error('分類名稱已更新，但舊比賽的分類同步失敗 HTTP '+u.status);
    }
    await competitionCategories();
    $('competitionCategory').value=name;
    msg('competitionMsg','✅ 分類已修改。');
  }catch(e){alert('修改分類失敗：'+(e instanceof Error?e.message:String(e)));}
}
async function deleteCompetitionCategory(id,name){
  if(!id)return;
  if(!confirm('確定刪除分類「'+name+'」？'))return;
  try{
    const used=await fetch(SUPABASE_URL+'/rest/v1/competitions?select=id&category=eq.'+encodeURIComponent(name)+'&limit=1',{headers:auth()});
    if(!used.ok)throw new Error('無法檢查分類是否正在使用 HTTP '+used.status);
    const rows=await used.json();
    if(rows.length){
      alert('這個分類已有比賽使用，為避免歷屆資料失去分類，請先修改相關比賽的分類後再刪除。');
      return;
    }
    const r=await fetch(SUPABASE_URL+'/rest/v1/competition_categories?id=eq.'+encodeURIComponent(id),{
      method:'DELETE',
      headers:auth()
    });
    const d=await r.json().catch(()=>[]);
    if(!r.ok)throw new Error(d.message||d.hint||('HTTP '+r.status));
    await competitionCategories();
    msg('competitionMsg','✅ 已刪除分類：'+name);
  }catch(e){alert('刪除分類失敗：'+(e instanceof Error?e.message:String(e)));}
}
async function saveCompetition(){
  const id=$('competitionId').value;
  const name=$('competitionName').value.trim();
  const category=$('competitionCategory').value;
  const event_date=$('competitionDate').value||null;
  const description=$('competitionDescription').value.trim()||null;
  const registration_deadline=$('competitionRegistrationDeadline').value?new Date($('competitionRegistrationDeadline').value).toISOString():null;
  const cap=$('competitionRegistrationCapacity').value.trim(); const registration_capacity=cap?Number(cap):null;
  const registration_approval=$('competitionRegistrationApproval').checked;
  const registration_fields=$('competitionRegistrationFields').value.split('\n').map(x=>x.trim()).filter(Boolean).slice(0,20);
  const results=getCompetitionResults();
  if(!name){msg('competitionMsg','請輸入比賽名稱。');return false}
  if(registration_capacity!==null && (!Number.isInteger(registration_capacity)||registration_capacity<1)){msg('competitionMsg','報名人數上限必須是正整數。');return false}
  if(registration_deadline && Number.isNaN(new Date(registration_deadline).getTime())){msg('competitionMsg','報名截止時間格式不正確。');return false}
  if(results.some(x=>!Number.isInteger(x.place)||x.place<1)){msg('competitionMsg','名次必須是正整數。');return false}
  if(results.some(x=>x.score!==null && !Number.isFinite(x.score))){msg('competitionMsg','分數必須是有效數字。');return false}
  const places=results.map(x=>x.place); if(new Set(places).size!==places.length){msg('competitionMsg','名次不可重複，請檢查參賽成績。');return false}
  try{
    const payload={name,category,event_date,description,registration_deadline,registration_capacity,registration_approval,registration_fields};
    const url=SUPABASE_URL+'/rest/v1/competitions'+(id?'?id=eq.'+encodeURIComponent(id):'');
    const r=await fetch(url,{method:id?'PATCH':'POST',headers:{...auth(),Prefer:'return=representation'},body:JSON.stringify(payload)});
    const d=await r.json().catch(()=>[]);
    if(!r.ok)throw new Error(d.message||d.hint||('HTTP '+r.status));
    const competitionId=id||d[0]?.id;
    if(!competitionId)throw new Error('無法取得比賽 ID');
    await replaceCompetitionResults(competitionId,results);
    $('competitionId').value=competitionId; window.__currentCompetitionName=name;
    msg('competitionMsg','✅ 已儲存草稿（目前不會顯示在網站）。');
    await competitions();
    return true;
  }catch(e){msg('competitionMsg','❌ '+e.message);return false}
}
async function replaceCompetitionResults(competitionId,results){
  const del=await fetch(SUPABASE_URL+'/rest/v1/competition_results?competition_id=eq.'+encodeURIComponent(competitionId),{method:'DELETE',headers:auth()});
  if(!del.ok){const d=await del.json().catch(()=>({}));throw new Error(d.message||d.hint||('刪除舊成績失敗 HTTP '+del.status))}
  if(!results.length)return;
  const ins=await fetch(SUPABASE_URL+'/rest/v1/competition_results',{method:'POST',headers:{...auth(),Prefer:'return=minimal'},body:JSON.stringify(results.map(x=>({...x,competition_id:competitionId})))});
  if(!ins.ok){const d=await ins.json().catch(()=>({}));throw new Error(d.message||d.hint||('儲存成績失敗 HTTP '+ins.status))}
}
async function loadCompetition(id){
  const r=await fetch(SUPABASE_URL+'/rest/v1/competitions?id=eq.'+encodeURIComponent(id)+'&select=*',{headers:auth()});
  const a=r.ok?await r.json():[];const c=a[0];if(!c)return;
  $('competitionId').value=c.id;$('competitionName').value=c.name||'';$('competitionCategory').value=c.category||'Minecraft';$('competitionDate').value=c.event_date||'';$('competitionRegistrationDeadline').value=c.registration_deadline?new Date(c.registration_deadline).toISOString().slice(0,16):'';$('competitionRegistrationCapacity').value=c.registration_capacity??'';$('competitionRegistrationApproval').checked=!!c.registration_approval;$('competitionRegistrationFields').value=Array.isArray(c.registration_fields)?c.registration_fields.join('\n'):'';$('competitionDescription').value=c.description||'';
  const rr=await fetch(SUPABASE_URL+'/rest/v1/competition_results?competition_id=eq.'+encodeURIComponent(id)+'&select=*&order=place.asc',{headers:auth()});
  const results=rr.ok?await rr.json():[];$('competitionResults').innerHTML='';results.forEach(addCompetitionResult);if(!results.length)addCompetitionResult();
  msg('competitionMsg',c.published?'📢 目前已公布':'📝 目前為草稿');
  document.querySelector('[data-tab="competitionTab"]').click();
  window.__currentCompetitionName=c.name||''; loadCompetitionRegistrations(id);
}
async function setCompetitionPublished(id,published){
  if(!id){alert('找不到比賽 ID，無法更新公布狀態。');return}
  if(published && !confirm('確定要公布這場比賽？公布後會員即可看到活動與成績。'))return;
  if(!published && !confirm('確定取消公布這場比賽？會員將暫時看不到它。'))return;
  const beforeR=await fetch(SUPABASE_URL+'/rest/v1/competitions?id=eq.'+encodeURIComponent(id)+'&select=id,name,published',{headers:auth()});
  const before=(beforeR.ok?(await beforeR.json()):[])[0];
  const body=published?{published:true}:{published:false};
  try{
    const r=await fetch(SUPABASE_URL+'/rest/v1/competitions?id=eq.'+encodeURIComponent(id),{method:'PATCH',headers:{...auth(),Prefer:'return=representation'},body:JSON.stringify(body)});
    const d=await r.json().catch(()=>[]);
    if(!r.ok)throw new Error(d.message||d.hint||('HTTP '+r.status));
    const vr=await fetch(SUPABASE_URL+'/rest/v1/competitions?id=eq.'+encodeURIComponent(id)+'&select=id,published,published_at',{headers:auth()});
    const va=vr.ok?await vr.json():[];const row=va[0];
    if(published){
      if(!row||row.published!==true||!row.published_at)throw new Error('公布狀態沒有成功寫入。請先執行新版 schema_upgrade_rerunnable.sql。');
      const pt=new Date(row.published_at).getTime();
      if(!Number.isFinite(pt)||pt>Date.now()+5000)throw new Error('資料庫的 published_at 仍是未來時間：'+row.published_at);
      msg('competitionMsg','📢 已立即公布！公布時間由資料庫自動設定。');
      if(before?.published!==true){
        try{
          const vr=await fetch(SUPABASE_URL+'/rest/v1/visitor_accounts?select=id&active=eq.true',{headers:auth()});
          const targets=vr.ok?await vr.json():[];
          if(targets.length)await createNotifications(targets.map(v=>({user_id:v.id,type:'比賽',title:'🏆 新比賽／活動已公布',content:(before.name||'比賽')+' 已公布，歡迎到「🏆 歷屆成績」查看。'})));
        }catch(e){console.error('比賽通知建立失敗:',e)}
      }
    }else{
      if(row&&(row.published!==false||row.published_at!==null))throw new Error('取消公布沒有成功寫入。');
      msg('competitionMsg','🔒 已取消公布。');
    }
    await competitions();
  }catch(e){alert('更新公布狀態失敗：'+(e instanceof Error?e.message:String(e)))}
}
async function competitions(){
  await competitionCategories();
  if(!$('adminCompetitions')||!configured()||!localStorage.getItem('access_token'))return;
  const r=await fetch(SUPABASE_URL+'/rest/v1/competitions?select=*&order=event_date.desc,created_at.desc',{headers:auth()});
  const a=r.ok?await r.json():[]; window.__adminCompetitions=a; renderAdminCompetitions();
}
function competitionStatus(c){
  if(!c.event_date)return 'nodate';
  const d=new Date(c.event_date+'T00:00:00'); const today=new Date(); const t=new Date(today.getFullYear(),today.getMonth(),today.getDate());
  if(d.getTime()===t.getTime())return 'today'; if(d>t)return 'upcoming'; return 'ended';
}
function competitionStatusText(c){const s=competitionStatus(c);return {nodate:'📅 日期未設定',today:'🟡 今天',upcoming:'🟢 即將開始',ended:'⚪ 已結束'}[s]}
function renderCompetitionFilters(){
  const sel=$('competitionCategoryFilter'); if(!sel)return;
  const names=[...new Set((window.__adminCompetitions||[]).map(c=>c.category).filter(Boolean))].sort(); const cur=sel.value; sel.innerHTML='<option value="all">全部分類</option>'+names.map(n=>'<option value="'+esc(n)+'">'+esc(n)+'</option>').join(''); if(names.includes(cur))sel.value=cur;
}
function renderAdminCompetitions(){
  renderCompetitionFilters();
  const a=window.__adminCompetitions||[]; const q=($('competitionSearch')?.value||'').trim().toLowerCase(); const status=$('competitionStatusFilter')?.value||'all'; const cat=$('competitionCategoryFilter')?.value||'all';
  const rows=a.filter(c=>{const hit=!q||[c.name,c.category,c.description].some(v=>String(v||'').toLowerCase().includes(q)); const st=competitionStatus(c); return hit&&(status==='all'||st===status)&&(cat==='all'||c.category===cat)});
  const published=a.filter(c=>c.published).length; const upcoming=a.filter(c=>competitionStatus(c)==='upcoming'||competitionStatus(c)==='today').length; const drafts=a.filter(c=>!c.published).length;
  if($('competitionSummary'))$('competitionSummary').innerHTML='<div class="competitionSummaryItem"><b>'+a.length+'</b><span>全部</span></div><div class="competitionSummaryItem"><b>'+published+'</b><span>已公布</span></div><div class="competitionSummaryItem"><b>'+drafts+'</b><span>草稿</span></div><div class="competitionSummaryItem"><b>'+upcoming+'</b><span>近期</span></div>';
  $('adminCompetitions').innerHTML=rows.map(c=>'<article class="notice"><div class="date">'+(c.published?'🟢 已公布':'📝 草稿')+' · '+competitionStatusText(c)+' · '+esc(c.category||'未分類')+' · '+esc(c.event_date||'未設定日期')+'</div><h3>'+esc(c.name)+'</h3><p>'+esc(c.description||'')+'</p><button data-cedit="'+esc(c.id)+'">✏️ 編輯</button> <button data-cpub="'+esc(c.id)+'" data-value="'+(!c.published)+'">'+(c.published?'🔒 取消公布':'📢 公布')+'</button> <button data-cdelcomp="'+esc(c.id)+'">🗑️ 刪除</button></article>').join('')||'<div class="empty">目前沒有符合條件的比賽。</div>';
  document.querySelectorAll('[data-cedit]').forEach(b=>b.onclick=()=>loadCompetition(b.dataset.cedit)); document.querySelectorAll('[data-cpub]').forEach(b=>b.onclick=()=>setCompetitionPublished(b.dataset.cpub,b.dataset.value==='true')); document.querySelectorAll('[data-cdelcomp]').forEach(b=>b.onclick=()=>deleteCompetition(b.dataset.cdelcomp));
}
async function deleteCompetition(id){
  if(!confirm('確定刪除這場比賽及其所有成績？'))return;
  const r=await fetch(SUPABASE_URL+'/rest/v1/competitions?id=eq.'+encodeURIComponent(id),{method:'DELETE',headers:auth()});
  if(!r.ok){const d=await r.json().catch(()=>({}));alert('刪除失敗：'+(d.message||d.hint||('HTTP '+r.status)));return}
  if($('competitionId').value===id)clearCompetition();
  await competitions();
}

function logout(){localStorage.removeItem('access_token');localStorage.removeItem('refresh_token');location.reload()}
function bindMobileAdminNav(){
  document.querySelectorAll('.mobileNavToggle').forEach(btn=>btn.addEventListener('click',()=>{const nav=btn.nextElementSibling;if(!nav)return;const open=nav.classList.toggle('mobileOpen');btn.setAttribute('aria-expanded',open?'true':'false');btn.textContent=open?'✕ 關閉選單':'☰ 選單'}));
}
function bind(){
  if($('newsSearch'))$('newsSearch').addEventListener('input',renderAdminNews); if($('newsStatusFilter'))$('newsStatusFilter').addEventListener('change',renderAdminNews);
  if($('productSearch'))$('productSearch').addEventListener('input',renderAdminProducts); if($('productStatusFilter'))$('productStatusFilter').addEventListener('change',renderAdminProducts);
  if($('couponSearch'))$('couponSearch').addEventListener('input',renderAdminCoupons);
  if($('supportSearch'))$('supportSearch').addEventListener('input',renderTickets); if($('supportStatusFilter'))$('supportStatusFilter').addEventListener('change',renderTickets);
  if($('competitionSearch'))$('competitionSearch').addEventListener('input',renderAdminCompetitions); if($('competitionStatusFilter'))$('competitionStatusFilter').addEventListener('change',renderAdminCompetitions); if($('competitionCategoryFilter'))$('competitionCategoryFilter').addEventListener('change',renderAdminCompetitions); if($('registrationSearch'))$('registrationSearch').addEventListener('input',renderCompetitionRegistrations); if($('exportCompetitionRegistrations'))$('exportCompetitionRegistrations').onclick=exportCompetitionRegistrations; if($('registrationStatusFilter'))$('registrationStatusFilter').addEventListener('change',renderCompetitionRegistrations);
  if($('loginButton'))$('loginButton').onclick=login;if($('refreshDashboard'))$('refreshDashboard').onclick=dashboard;if($('logoutButton'))$('logoutButton').onclick=logout;if($('saveContent'))$('saveContent').onclick=save;if($('publishButton'))$('publishButton').onclick=publish;if($('saveProduct'))$('saveProduct').onclick=saveProduct;if($('clearProduct'))$('clearProduct').onclick=clearProduct;if($('createVisitor'))$('createVisitor').onclick=createVisitor;if($('setSharedVisitorPassword'))$('setSharedVisitorPassword').onclick=setSharedVisitorPassword;if($('createCoupon'))$('createCoupon').onclick=createCoupon;if($('createNotification'))$('createNotification').onclick=createNotification;if($('addCompetitionResult'))$('addCompetitionResult').onclick=()=>addCompetitionResult();if($('saveCompetition'))$('saveCompetition').onclick=saveCompetition;if($('publishCompetition'))$('publishCompetition').onclick=async()=>{const ok=await saveCompetition();const id=$('competitionId').value;if(ok&&id)await setCompetitionPublished(id,true)};if($('unpublishCompetition'))$('unpublishCompetition').onclick=async()=>{const id=$('competitionId').value;if(id)await setCompetitionPublished(id,false)};if($('clearCompetition'))$('clearCompetition').onclick=clearCompetition;if($('addCompetitionCategory'))$('addCompetitionCategory').onclick=addCompetitionCategory;if($('saveQuickLink'))$('saveQuickLink').onclick=saveQuickLink;if($('clearQuickLink'))$('clearQuickLink').onclick=clearQuickLink;document.querySelectorAll('.tab').forEach(b=>b.onclick=()=>{document.querySelectorAll('.tabPanel').forEach(x=>x.classList.add('hidden'));document.querySelectorAll('.tab').forEach(x=>x.classList.remove('active'));$(b.dataset.tab).classList.remove('hidden');b.classList.add('active');if(b.dataset.tab==='dashboardTab')dashboard();if(b.dataset.tab==='newsTab')news();if(b.dataset.tab==='productTab')products();if(b.dataset.tab==='visitorTab')visitors();if(b.dataset.tab==='couponTab')coupons();if(b.dataset.tab==='competitionTab'){competitionCategories();competitions();if(!$('competitionResults').children.length)addCompetitionResult()}if(b.dataset.tab==='quickLinkTab')quickLinks();if(b.dataset.tab==='supportTab')tickets();if(b.dataset.tab==='notificationTab')notifications()})}
document.addEventListener('DOMContentLoaded',()=>{bindMobileAdminNav();bind();if(localStorage.getItem('access_token')){$('login').classList.add('hidden');$('dashboard').classList.remove('hidden');load()}else if(!configured())msg('loginError','請把你原本可用的 config.js 放回來。')});
