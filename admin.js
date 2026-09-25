const F=['site_name','hero_title','hero_text','hero_image','about_title','about_subtitle','about1_title','about1_text','about2_title','about2_text','features_title','features_subtitle','f1_title','f1_text','f2_title','f2_text','f3_title','f3_text','f4_title','f4_text','contact1','contact2','contact3'];
const $=id=>document.getElementById(id); const esc=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
function configured(){return typeof SUPABASE_URL!=='undefined'&&typeof SUPABASE_ANON_KEY!=='undefined'&&SUPABASE_URL&&SUPABASE_ANON_KEY&&!String(SUPABASE_URL).includes('你的')&&!String(SUPABASE_URL).includes('請填入')&&!String(SUPABASE_ANON_KEY).includes('你的')}
function auth(){const t=recoverStoredSession().access||localStorage.getItem('access_token')||sessionStorage.getItem('access_token');return {'Content-Type':'application/json',apikey:SUPABASE_ANON_KEY,Authorization:'Bearer '+(t||SUPABASE_ANON_KEY)}}
function msg(id,t){if($(id))$(id).textContent=t}

// 活動中心時間一律以台灣時間（Asia/Taipei，UTC+8）顯示與儲存，避免 datetime-local 被瀏覽器轉成 UTC 後少 8 小時。
function taipeiDateTimeLocal(value){
  if(!value) return '';
  const d=new Date(value);
  if(Number.isNaN(d.getTime())) return '';
  const parts=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Taipei',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hour12:false,hourCycle:'h23'}).formatToParts(d);
  const get=k=>parts.find(x=>x.type===k)?.value||'';
  return `${get('year')}-${get('month')}-${get('day')}T${get('hour')}:${get('minute')}`;
}
function taipeiDateTimeToISO(value){
  if(!value) return null;
  const m=String(value).match(/^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2})/);
  if(!m) return null;
  return new Date(m[1]+':00+08:00').toISOString();
}
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
async function publish(){const id=$('announcementId')?.value||'';const body={title:$('title').value.trim(),category:$('category').value,published_at:new Date($('published_at').value||new Date()).toISOString(),pinned:$('pinned').checked,content:$('content').value,link_url:$('linkUrl').value.trim()||null,link_label:$('linkLabel').value.trim()||null,published:true,popup_enabled:$('popupEnabled')?.checked||false,popup_mode:$('popupMode')?.value||'once',popup_start_at:$('popupStartAt')?.value?new Date($('popupStartAt').value).toISOString():new Date($('published_at').value||new Date()).toISOString(),popup_end_at:$('popupEndAt')?.value?new Date($('popupEndAt').value).toISOString():null};if(!body.title||!body.content){msg('publishMsg','請填寫標題與內容。');return}const url=SUPABASE_URL+'/rest/v1/announcements'+(id?'?id=eq.'+encodeURIComponent(id):'');const r=await fetch(url,{method:id?'PATCH':'POST',headers:{...auth(),Prefer:'return=representation'},body:JSON.stringify(body)});msg('publishMsg',r.ok?'✅ 已儲存公告':'❌ 儲存失敗：請檢查 announcements RLS。');if(r.ok){clearAnnouncement();await news()}}
function clearAnnouncement(){$('title').value='';$('content').value='';$('category').value='最新消息';$('published_at').value='';$('pinned').checked=false;if($('linkUrl'))$('linkUrl').value='';if($('linkLabel'))$('linkLabel').value='';if($('popupEnabled'))$('popupEnabled').checked=false;if($('popupMode'))$('popupMode').value='once';if($('popupStartAt'))$('popupStartAt').value='';if($('popupEndAt'))$('popupEndAt').value='';if($('announcementId'))$('announcementId').value=''}
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
  $('adminList').innerHTML=rows.map(x=>'<article class="notice"><div class="date">'+(x.published?'🟢 已發布':'📝 草稿')+' · '+(x.popup_enabled?'📢 彈窗':'')+(x.pinned?' · 📌 ':' · ')+esc(x.category)+' · '+esc(String(x.published_at||x.date||'').slice(0,16).replace('T',' '))+'</div><h3>'+esc(x.title)+'</h3><p>'+esc(x.content).replace(/\n/g,'<br>')+(x.link_url?'<br><a href="'+esc(x.link_url)+'" target="_blank" rel="noopener noreferrer">🔗 '+esc(x.link_label||'查看連結')+'</a>':'')+'</p><button data-edit="'+esc(x.id)+'">✏️ 編輯</button> <button data-del="'+esc(x.id)+'">🗑️ 刪除</button></article>').join('')||'<div class="empty">目前沒有符合條件的公告。</div>';
  document.querySelectorAll('[data-del]').forEach(b=>b.onclick=()=>delAnnouncement(b.dataset.del));
  document.querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>editAnnouncement(b.dataset.edit));
}
async function editAnnouncement(id){const r=await fetch(SUPABASE_URL+'/rest/v1/announcements?id=eq.'+encodeURIComponent(id)+'&select=*',{headers:auth()});const a=r.ok?await r.json():[];const x=a[0];if(!x)return;$('announcementId')?.setAttribute('value',x.id);if(!$('announcementId')){const i=document.createElement('input');i.type='hidden';i.id='announcementId';document.querySelector('#newsTab .editor').prepend(i);i.value=x.id}else $('announcementId').value=x.id;$('title').value=x.title||'';$('content').value=x.content||'';$('category').value=x.category||'最新消息';$('pinned').checked=!!x.pinned;$('published_at').value=x.published_at?new Date(x.published_at).toISOString().slice(0,16):'';if($('linkUrl'))$('linkUrl').value=x.link_url||'';if($('linkLabel'))$('linkLabel').value=x.link_label||'';if($('popupEnabled'))$('popupEnabled').checked=!!x.popup_enabled;if($('popupMode'))$('popupMode').value=x.popup_mode||'once';if($('popupStartAt'))$('popupStartAt').value=x.popup_start_at?new Date(x.popup_start_at).toISOString().slice(0,16):'';if($('popupEndAt'))$('popupEndAt').value=x.popup_end_at?new Date(x.popup_end_at).toISOString().slice(0,16):'';document.querySelector('[data-tab="newsTab"]').click();}
async function delAnnouncement(id){if(!confirm('確定刪除這則公告？'))return;const r=await fetch(SUPABASE_URL+'/rest/v1/announcements?id=eq.'+encodeURIComponent(id),{method:'DELETE',headers:auth()});if(!r.ok){let d=await r.json().catch(()=>({}));alert('刪除失敗：'+(d.message||d.hint||('HTTP '+r.status)));return}await news()}

let __adminOrders=[];
async function ordersAdmin(){
  if(!$('adminOrders')||!configured()||!localStorage.getItem('access_token'))return;
  $('adminOrders').innerHTML='<div class="loading">正在載入訂單…</div>';
  const r=await fetch(SUPABASE_URL+'/rest/v1/orders?select=id,order_no,user_id,status,payment_method,total_amount,note,created_at,paid_at,completed_at,cancelled_at,order_items(id,product_name,unit_price,quantity,subtotal)&order=created_at.desc&limit=1000',{headers:auth()});
  __adminOrders=r.ok?await r.json():[];
  renderAdminOrders();
}
function renderAdminOrders(){
  const q=($('orderSearch')?.value||'').trim().toLowerCase(); const st=$('orderStatusFilter')?.value||'all';
  const rows=__adminOrders.filter(o=>st==='all'||o.status===st).filter(o=>{const items=(o.order_items||[]).map(x=>x.product_name).join(' ');return !q||[o.order_no,o.user_id,o.note,items].some(v=>String(v||'').toLowerCase().includes(q));});
  $('adminOrders').innerHTML=rows.length?rows.map(o=>'<article class="notice orderCard"><div class="date">'+esc(o.order_no)+' · '+orderStatusLabelAdmin(o.status)+'</div><h3>🧾 '+(o.order_items||[]).map(i=>esc(i.product_name)+' × '+esc(i.quantity)).join('、')+'</h3><p><b>會員：</b>'+esc(o.user_id)+'<br><b>金額：</b>NT$ '+Number(o.total_amount||0).toLocaleString()+'　·　<b>付款：</b>線下現金</p>'+(o.note?'<p><b>備註：</b>'+esc(o.note)+'</p>':'')+'<small>建立：'+esc(new Date(o.created_at).toLocaleString('zh-TW'))+(o.paid_at?'　· 收款：'+esc(new Date(o.paid_at).toLocaleString('zh-TW')):'')+'</small><div class="competitionActions" style="margin-top:12px">'+(o.status==='pending_payment'?'<button class="btn" data-order-paid="'+esc(o.id)+'">💵 確認收款</button><button class="btn secondary" data-order-cancel="'+esc(o.id)+'">取消訂單</button>':'')+(o.status==='paid'?'<button class="btn" data-order-complete="'+esc(o.id)+'">📦 標記完成</button><button class="btn secondary" data-order-cancel="'+esc(o.id)+'">取消訂單</button>':'')+'</div></article>').join(''):'<div class="empty">目前沒有符合條件的訂單。</div>';
  document.querySelectorAll('[data-order-paid]').forEach(b=>b.onclick=()=>adminOrderAction('admin_mark_order_paid',b.dataset.orderPaid,'確認收到這筆現金付款嗎？'));
  document.querySelectorAll('[data-order-complete]').forEach(b=>b.onclick=()=>adminOrderAction('admin_complete_order',b.dataset.orderComplete,'確認將此訂單標記為已完成嗎？'));
  document.querySelectorAll('[data-order-cancel]').forEach(b=>b.onclick=()=>adminOrderAction('admin_cancel_order',b.dataset.orderCancel,'確定取消這筆訂單嗎？'));
}
function orderStatusLabelAdmin(s){return {pending_payment:'🟡 待付款',paid:'🟢 已付款',completed:'✅ 已完成',cancelled:'⚪ 已取消'}[s]||s||'—'}
async function adminOrderAction(fn,id,question){if(!confirm(question))return;const r=await fetch(SUPABASE_URL+'/rest/v1/rpc/'+fn,{method:'POST',headers:{...auth(),Prefer:'return=representation'},body:JSON.stringify({p_order_id:id})});const d=await r.json().catch(()=>({}));if(!r.ok){alert(d.message||d.hint||'操作失敗');return}await ordersAdmin()}

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
  $('ticketList').innerHTML=rows.map(t=>{
    const reply=t.admin_reply?'<hr><p><b>目前回覆：</b>'+esc(t.admin_reply).replace(/\n/g,'<br>')+'</p>':'';
    const action=t.status!=='closed'?'<button class="btn secondary" type="button" data-close-admin="'+esc(t.id)+'">✓ 結案</button>':'<button class="btn secondary" type="button" data-reopen-admin="'+esc(t.id)+'">↩ 重新開啟</button>';
    return '<article class="notice supportTicketCard"><div class="date">'+(t.status==='closed'?'⚪ 已結案':t.status==='answered'?'🟢 已回覆':'🟠 處理中')+' · '+esc(String(t.updated_at||t.created_at).slice(0,16).replace('T',' '))+'</div><h3>'+esc(t.subject)+'</h3><p>'+esc(t.message).replace(/\n/g,'<br>')+'</p>'+reply+'<label>管理員回覆<textarea data-reply="'+esc(t.id)+'" rows="4">'+esc(t.admin_reply||'')+'</textarea></label><div class="supportActions"><button data-replybtn="'+esc(t.id)+'">💬 儲存回覆</button>'+action+'</div></article>';
  }).join('')||'<div class="empty">目前沒有符合條件的客服訊息。</div>';
  document.querySelectorAll('[data-close-admin]').forEach(b=>b.addEventListener('click',()=>setTicketStatus(b.dataset.closeAdmin,'closed')));
  document.querySelectorAll('[data-reopen-admin]').forEach(b=>b.addEventListener('click',()=>setTicketStatus(b.dataset.reopenAdmin,'open')));
  document.querySelectorAll('[data-replybtn]').forEach(b=>b.onclick=()=>replyTicket(b.dataset.replybtn));
}
async function setTicketStatus(id,status){const old=await fetch(SUPABASE_URL+'/rest/v1/support_tickets?id=eq.'+encodeURIComponent(id)+'&select=id,user_id,subject,status',{headers:auth()});const ticket=(old.ok?(await old.json()):[])[0];const r=await fetch(SUPABASE_URL+'/rest/v1/support_tickets?id=eq.'+encodeURIComponent(id),{method:'PATCH',headers:{...auth(),Prefer:'return=minimal'},body:JSON.stringify({status,updated_at:new Date().toISOString()})});if(r.ok&&ticket?.user_id){try{await createNotifications([{user_id:ticket.user_id,type:'客服',ticket_id:ticket.id,title:status==='closed'?'💬 客服案件已結案':'💬 客服案件已重新開啟',content:status==='closed'?'你的客服案件已由管理員結案。':'你的客服案件已重新開啟，請到「我的 → 我的客服」查看。'}])}catch(e){console.error(e)}}alert(r.ok?(status==='closed'?'已結案。':'已重新開啟。'):'操作失敗。');if(r.ok)await tickets()}
async function replyTicket(id){const ta=document.querySelector('[data-reply="'+CSS.escape(id)+'"]');const reply=ta?ta.value.trim():'';const old=await fetch(SUPABASE_URL+'/rest/v1/support_tickets?id=eq.'+encodeURIComponent(id)+'&select=id,user_id,admin_reply',{headers:auth()});const ticket=(old.ok?(await old.json()):[])[0];const r=await fetch(SUPABASE_URL+'/rest/v1/support_tickets?id=eq.'+encodeURIComponent(id),{method:'PATCH',headers:{...auth(),Prefer:'return=minimal'},body:JSON.stringify({admin_reply:reply,status:reply?'answered':'open',updated_at:new Date().toISOString()})});if(r.ok&&reply&&ticket?.user_id&&reply!==String(ticket.admin_reply||'')){try{await createNotifications([{user_id:ticket.user_id,type:'客服',title:'💬 客服已有新回覆',content:'你的客服問題已有管理員回覆，請到「我的 → 我的客服」查看。'}])}catch(e){console.error(e)}}alert(r.ok?'已儲存回覆。':'儲存失敗。');if(r.ok)await tickets()}


async function loadCompetitionRegistrations(competitionId){
  const panel=$('competitionRegistrationPanel'),box=$('competitionRegistrations'); if(!panel||!box||!competitionId)return;
  panel.classList.remove('hidden'); panel.dataset.competitionId=competitionId;
  await loadCompetitionAttendance(competitionId);
  const r=await fetch(SUPABASE_URL+'/rest/v1/competition_registrations?select=*&competition_id=eq.'+encodeURIComponent(competitionId)+'&order=created_at.asc',{headers:auth()});
  const rows=r.ok?await r.json():[]; window.__competitionRegistrations=rows; renderCompetitionRegistrations(); await loadCompetitionWaitlist(competitionId);
}

async function loadCompetitionWaitlist(competitionId){
  const box=$('competitionWaitlist'); if(!box||!competitionId)return;
  const r=await fetch(SUPABASE_URL+'/rest/v1/competition_waitlist?select=*&competition_id=eq.'+encodeURIComponent(competitionId)+'&order=position.asc',{headers:auth()});
  const rows=r.ok?await r.json():[]; window.__competitionWaitlist=rows; renderCompetitionWaitlist();
}
function renderCompetitionWaitlist(){
  const box=$('competitionWaitlist');if(!box)return;const rows=window.__competitionWaitlist||[];
  box.innerHTML=rows.length?rows.map(x=>'<article class="notice"><div class="date">'+(x.status==='waiting'?'🕐 等待中':x.status==='promoted'?'🟢 已遞補':'⚪ 已取消')+' · 候補第 '+esc(x.position)+'</div><h3>會員 '+esc(x.member_no!=null?String(x.member_no).padStart(3,'0'):'—')+'｜'+esc(x.nickname||'')+'</h3><p>Email：'+esc(x.email||'—')+' · '+esc(String(x.created_at||'').slice(0,16).replace('T',' '))+'</p>'+(x.status==='waiting'?'<button class="btn secondary" data-promote-wait="'+esc(x.id)+'">⬆️ 遞補</button>':'')+'</article>').join(''):'<div class="empty">目前沒有候補資料。</div>';
  box.querySelectorAll('[data-promote-wait]').forEach(b=>b.onclick=async()=>{
    if(!confirm('確定要遞補這位候補會員？'))return;
    const r=await fetch(SUPABASE_URL+'/rest/v1/rpc/admin_promote_competition_waitlist',{method:'POST',headers:{...auth(),Prefer:'return=representation'},body:JSON.stringify({p_waitlist_id:b.dataset.promoteWait})});
    const d=await r.json().catch(()=>({}));if(!r.ok){msg('competitionMsg','❌ 遞補失敗：'+(d.message||d.hint||('HTTP '+r.status)));return}
    if(d.user_id){try{await createNotifications([{user_id:d.user_id,type:'比賽',title:'🎉 活動候補已遞補',content:'你已從活動候補名單遞補成功。'+(d.status==='pending'?'目前等待管理員審核。':'請到活動頁查看報名狀態。')}])}catch(e){console.error('候補通知失敗',e)}}
    msg('competitionMsg','✅ 已完成候補遞補。');await loadCompetitionRegistrations($('competitionRegistrationPanel').dataset.competitionId);
  });
}

async function showCompetitionQr(){
  const id=$('competitionId')?.value;if(!id){msg('competitionMsg','請先儲存活動。');return}
  const code=$('competitionCheckinCode')?.value.trim();if(!code){msg('competitionMsg','請先設定簽到碼。');return}
  const url=new URL('competitions.html',location.href);url.searchParams.set('id',id);url.searchParams.set('checkin','1');url.searchParams.set('code',code);
  const panel=$('competitionQrPanel'),img=$('competitionQrImage'),txt=$('competitionQrUrl');panel?.classList.remove('hidden');
  if(img)img.innerHTML='<img style="width:280px;max-width:100%;border-radius:12px;border:1px solid #ddd;background:#fff;padding:10px" alt="活動簽到 QR Code" src="https://api.qrserver.com/v1/create-qr-code/?size=320x320&data='+encodeURIComponent(url.href)+'">';
  if(txt)txt.textContent=url.href;
}
async function copyCompetitionQr(){
  const id=$('competitionId')?.value;if(!id){msg('competitionMsg','請先儲存活動。');return} const code=$('competitionCheckinCode')?.value.trim();if(!code){msg('competitionMsg','請先設定簽到碼。');return}
  const url=new URL('competitions.html',location.href);url.searchParams.set('id',id);url.searchParams.set('checkin','1');url.searchParams.set('code',code);
  try{await navigator.clipboard.writeText(url.href);msg('competitionMsg','✅ 簽到連結已複製。')}catch(e){prompt('請複製這個簽到連結：',url.href)}
}
async function settleCompetition(){
  const id=$('competitionId')?.value;if(!id){msg('competitionMsg','請先選擇活動。');return}
  if(!confirm('活動結算後會自動把尚未簽到的已報名會員標記為「未到」，並發放活動完成積分。確定結算？'))return;
  const r=await fetch(SUPABASE_URL+'/rest/v1/rpc/admin_settle_competition',{method:'POST',headers:{...auth(),Prefer:'return=representation'},body:JSON.stringify({p_competition_id:id})});
  const d=await r.json().catch(()=>({}));if(!r.ok){msg('competitionMsg','❌ 結算失敗：'+(d.message||d.hint||('HTTP '+r.status)));return}
  msg('competitionMsg',d.already?'ℹ️ 此活動已結算。':'🏁 活動結算完成：完成 '+(d.completed||0)+' 人、未到 '+(d.no_show||0)+' 人、完成積分 '+(d.completion_points||0)+'。');await loadCompetitionAttendance(id); await loadActivityRewards(id);await competitions();
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
  $('competitionRegistrationApproval').checked=false;if($('competitionWaitlistEnabled'))$('competitionWaitlistEnabled').checked=true;
  $('competitionRegistrationFields').value='';
  $('competitionDescription').value=''; if($('competitionCheckinEnabled'))$('competitionCheckinEnabled').checked=false; if($('competitionCheckinCode'))$('competitionCheckinCode').value=''; if($('competitionCheckinStart'))$('competitionCheckinStart').value=''; if($('competitionCheckinEnd'))$('competitionCheckinEnd').value=''; if($('competitionCheckinPoints'))$('competitionCheckinPoints').value=10;if($('competitionCompletionPoints'))$('competitionCompletionPoints').value=20;
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
  const registration_deadline=taipeiDateTimeToISO($('competitionRegistrationDeadline').value);
  const cap=$('competitionRegistrationCapacity').value.trim(); const registration_capacity=cap?Number(cap):null;
  const registration_approval=$('competitionRegistrationApproval').checked; const waitlist_enabled=$('competitionWaitlistEnabled')?.checked!==false;
  const registration_fields=$('competitionRegistrationFields').value.split('\n').map(x=>x.trim()).filter(Boolean).slice(0,20); const completion_points=Number($('competitionCompletionPoints')?.value||0); const checkin_enabled=$('competitionCheckinEnabled')?.checked||false; const checkin_code=$('competitionCheckinCode')?.value.trim()||null; const checkin_start_at=taipeiDateTimeToISO($('competitionCheckinStart')?.value); const checkin_end_at=taipeiDateTimeToISO($('competitionCheckinEnd')?.value); const checkin_points=Number($('competitionCheckinPoints')?.value||0);
  const results=getCompetitionResults();
  if(!name){msg('competitionMsg','請輸入比賽名稱。');return false}
  if(registration_capacity!==null && (!Number.isInteger(registration_capacity)||registration_capacity<1)){msg('competitionMsg','報名人數上限必須是正整數。');return false}
  if(registration_deadline && Number.isNaN(new Date(registration_deadline).getTime())){msg('competitionMsg','報名截止時間格式不正確。');return false} if(checkin_points<0||!Number.isInteger(checkin_points)){msg('competitionMsg','簽到積分必須是 0 以上整數。');return false} if(completion_points<0||!Number.isInteger(completion_points)){msg('competitionMsg','活動完成積分必須是 0 以上整數。');return false} if(checkin_start_at&&checkin_end_at&&new Date(checkin_start_at)>=new Date(checkin_end_at)){msg('competitionMsg','簽到開始時間必須早於結束時間。');return false}
  if(results.some(x=>!Number.isInteger(x.place)||x.place<1)){msg('competitionMsg','名次必須是正整數。');return false}
  if(results.some(x=>x.score!==null && !Number.isFinite(x.score))){msg('competitionMsg','分數必須是有效數字。');return false}
  const places=results.map(x=>x.place); if(new Set(places).size!==places.length){msg('competitionMsg','名次不可重複，請檢查參賽成績。');return false}
  try{
    const payload={name,category,event_date,description,registration_deadline,registration_capacity,registration_approval,registration_fields,waitlist_enabled,checkin_enabled,checkin_code,checkin_start_at,checkin_end_at,checkin_points,completion_points};
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
  $('competitionId').value=c.id;$('competitionName').value=c.name||'';$('competitionCategory').value=c.category||'Minecraft';$('competitionDate').value=c.event_date||'';$('competitionRegistrationDeadline').value=taipeiDateTimeLocal(c.registration_deadline);$('competitionRegistrationCapacity').value=c.registration_capacity??'';$('competitionRegistrationApproval').checked=!!c.registration_approval;if($('competitionWaitlistEnabled'))$('competitionWaitlistEnabled').checked=c.waitlist_enabled!==false;$('competitionRegistrationFields').value=Array.isArray(c.registration_fields)?c.registration_fields.join('\n'):'';$('competitionDescription').value=c.description||''; if($('competitionCheckinEnabled'))$('competitionCheckinEnabled').checked=!!c.checkin_enabled; if($('competitionCheckinCode'))$('competitionCheckinCode').value=c.checkin_code||''; if($('competitionCheckinStart'))$('competitionCheckinStart').value=taipeiDateTimeLocal(c.checkin_start_at); if($('competitionCheckinEnd'))$('competitionCheckinEnd').value=taipeiDateTimeLocal(c.checkin_end_at); if($('competitionCheckinPoints'))$('competitionCheckinPoints').value=c.checkin_points??10;if($('competitionCompletionPoints'))$('competitionCompletionPoints').value=c.completion_points??20; await loadCompetitionAttendance(c.id); await loadActivityRewards(c.id); await loadActivityBadgesAdmin();
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
async function loadActivityAnalytics(){
  const box=$('activityAnalytics'); if(!box)return;
  box.innerHTML='<div class="loading">正在整理活動分析…</div>';
  const r=await fetch(SUPABASE_URL+'/rest/v1/rpc/admin_activity_analytics',{method:'POST',headers:{...auth(),Prefer:'return=representation'},body:'{}'});
  const d=await r.json().catch(()=>({}));
  if(!r.ok){box.innerHTML='<div class="empty">❌ '+esc(d.message||d.hint||('HTTP '+r.status))+'</div>';return;}
  box.innerHTML='<div class="competitionSummaryItem"><b>'+Number(d.competitions||0)+'</b><span>活動總數</span></div><div class="competitionSummaryItem"><b>'+Number(d.published||0)+'</b><span>已公布</span></div><div class="competitionSummaryItem"><b>'+Number(d.registrations||0)+'</b><span>有效報名</span></div><div class="competitionSummaryItem"><b>'+Number(d.attended||0)+'</b><span>已出席</span></div><div class="competitionSummaryItem"><b>'+Number(d.late||0)+'</b><span>遲到</span></div><div class="competitionSummaryItem"><b>'+Number(d.no_show||0)+'</b><span>未到</span></div><div class="competitionSummaryItem"><b>'+Number(d.attendance_points||0)+'</b><span>簽到積分</span></div><div class="competitionSummaryItem"><b>'+Number(d.completion_points||0)+'</b><span>完成積分</span></div><div class="competitionSummaryItem"><b>'+Number(d.badges||0)+'</b><span>徽章解鎖</span></div>';
}
async function loadActivityBadgesAdmin(){
  const sel=$('activityRewardBadge'),box=$('activityBadgeAdmin'); if(!sel&&!box)return;
  const r=await fetch(SUPABASE_URL+'/rest/v1/activity_badges?select=id,code,title,description,icon,requirement_type,requirement_value,active&order=requirement_value.asc',{headers:auth()});
  const rows=r.ok?await r.json():[];
  if(sel)sel.innerHTML=rows.map(x=>'<option value="'+esc(x.id)+'">'+esc(x.icon||'🏅')+' '+esc(x.title)+'</option>').join('')||'<option value="">尚無徽章</option>';
  if(box)box.innerHTML=rows.map(x=>'<article class="notice"><div class="date">'+esc(x.icon||'🏅')+' '+esc(x.code)+'</div><h3>'+esc(x.title)+'</h3><p>'+esc(x.description||'')+' · 條件 '+esc(x.requirement_value)+'</p></article>').join('');
}
async function loadActivityRewards(competitionId){
  const box=$('activityRewardList'); if(!box||!competitionId)return;
  const r=await fetch(SUPABASE_URL+'/rest/v1/competition_reward_rules?select=id,reward_type,reward_value,title,description,enabled,badge_id,activity_badges(title,icon)&competition_id=eq.'+encodeURIComponent(competitionId)+'&order=created_at.asc',{headers:auth()});
  const rows=r.ok?await r.json():[];
  box.innerHTML=rows.length?rows.map(x=>'<article class="notice"><div class="date">'+(x.reward_type==='points'?'💎 '+Number(x.reward_value||0)+' 點':'🏅 '+esc(x.activity_badges?.icon||'')+' '+esc(x.activity_badges?.title||'徽章'))+'</div><h3>'+esc(x.title)+'</h3><p>'+esc(x.description||'')+'</p></article>').join(''):'<div class="empty">尚未設定活動獎勵規則。</div>';
}
async function addActivityReward(){
  const id=$('competitionId')?.value; if(!id){show('activityRewardMsg','請先選擇已儲存的活動。');return}
  const type=$('activityRewardType')?.value||'points', title=$('activityRewardTitle')?.value.trim(), desc=$('activityRewardDescription')?.value.trim()||null;
  if(!title){show('activityRewardMsg','請輸入獎勵名稱。');return}
  const body={p_competition_id:id,p_reward_type:type,p_title:title,p_description:desc,p_points:type==='points'?Number($('activityRewardPoints')?.value||0):null,p_badge_id:type==='badge'?($('activityRewardBadge')?.value||null):null};
  const r=await fetch(SUPABASE_URL+'/rest/v1/rpc/admin_grant_competition_reward',{method:'POST',headers:{...auth(),Prefer:'return=representation'},body:JSON.stringify(body)}); const d=await r.json().catch(()=>({}));
  if(!r.ok){show('activityRewardMsg','❌ '+(d.message||d.hint||('HTTP '+r.status)));return}
  show('activityRewardMsg','✅ 獎勵規則已加入。'); $('activityRewardTitle').value='';$('activityRewardDescription').value=''; await loadActivityRewards(id);
}
async function loadCompetitionAttendance(competitionId){
  const panel=$('competitionAttendancePanel'),box=$('competitionAttendance'); if(!panel||!box||!competitionId)return;
  panel.classList.remove('hidden'); panel.dataset.competitionId=competitionId;
  try{
    const [rr,ar,pr]=await Promise.all([
      fetch(SUPABASE_URL+'/rest/v1/competition_registrations?select=id,user_id,member_no,nickname,email,status,created_at&competition_id=eq.'+encodeURIComponent(competitionId)+'&status=in.(active,approved)&order=created_at.asc',{headers:auth()}),
      fetch(SUPABASE_URL+'/rest/v1/competition_attendance?select=*&competition_id=eq.'+encodeURIComponent(competitionId)+'&order=created_at.asc',{headers:auth()}),
      fetch(SUPABASE_URL+'/rest/v1/profiles?select=id,member_no,nickname&role=eq.visitor',{headers:auth()})
    ]);
    const regs=rr.ok?await rr.json():[]; const atts=ar.ok?await ar.json():[]; const profiles=pr.ok?await pr.json():[];
    const pm=new Map(profiles.map(x=>[x.id,x])); const am=new Map(atts.map(x=>[x.user_id,x]));
    window.__competitionAttendance=regs.map(r=>({...r,profile:pm.get(r.user_id)||{},attendance:am.get(r.user_id)||null}));
    if(!rr.ok||!ar.ok)msg('competitionMsg','⚠️ 簽到資料讀取失敗，請確認已執行 V2 SQL。');
    renderCompetitionAttendance();
  }catch(e){console.error(e);msg('competitionMsg','❌ 簽到資料載入失敗：'+e.message)}
}
function renderCompetitionAttendance(){
  const box=$('competitionAttendance'); if(!box)return;
  const a=window.__competitionAttendance||[]; const st=$('attendanceStatusFilter')?.value||'all';
  const normalized=a.map(x=>({...x,attStatus:x.attendance?.status||'not_checked_in',att:x.attendance||{}}));
  const rows=normalized.filter(x=>st==='all'||(st==='checked_in'&&x.attStatus==='checked_in')||(st==='late'&&x.attStatus==='late')||(st==='no_show'&&x.attStatus==='no_show')||(st==='cancelled'&&x.attStatus==='cancelled')||(st==='not_checked_in'&&x.attStatus==='not_checked_in'));
  const counts={checked_in:0,late:0,no_show:0,cancelled:0,not_checked_in:0}; normalized.forEach(x=>counts[x.attStatus]=(counts[x.attStatus]||0)+1);
  if($('competitionAttendanceSummary'))$('competitionAttendanceSummary').innerHTML='<div class="competitionSummaryItem"><b>'+a.length+'</b><span>已報名</span></div><div class="competitionSummaryItem"><b>'+counts.checked_in+'</b><span>已簽到</span></div><div class="competitionSummaryItem"><b>'+counts.late+'</b><span>遲到</span></div><div class="competitionSummaryItem"><b>'+counts.not_checked_in+'</b><span>未簽到</span></div><div class="competitionSummaryItem"><b>'+counts.no_show+'</b><span>未到</span></div>';
  const statusText=x=>({checked_in:'🟢 已簽到',late:'🟡 遲到',no_show:'🔴 未到',cancelled:'⚪ 取消',not_checked_in:'⚪ 尚未簽到'}[x]||x);
  box.innerHTML=rows.map(x=>{const p=x.profile||{};const member=x.member_no!=null?String(x.member_no).padStart(3,'0'):String(p.member_no??'—').padStart(3,'0');const name=x.nickname||p.nickname||x.email||'會員';const att=x.attendance;const checked=att&&['checked_in','late'].includes(att.status);return '<article class="notice"><div class="date">'+statusText(x.attStatus)+(att?.checked_in_at?' · '+esc(new Date(att.checked_in_at).toLocaleString('zh-TW')):'')+'</div><h3>會員 '+esc(member)+'｜'+esc(name)+'</h3><p>Email：'+esc(x.email||'—')+' · 簽到積分：'+esc(att?.points_awarded||0)+'</p><div class="competitionActions">'+(!checked?'<button class="btn secondary" data-att-member="'+esc(x.user_id)+'" data-att-status="checked_in">✅ 補簽到</button>':'' )+'<button class="btn secondary" data-att-member="'+esc(x.user_id)+'" data-att-status="late">🟡 遲到</button><button class="btn secondary" data-att-member="'+esc(x.user_id)+'" data-att-status="no_show">🔴 未到</button></div></article>'}).join('')||'<div class="empty">目前沒有符合條件的報名會員。</div>';
  box.querySelectorAll('[data-att-member]').forEach(b=>b.onclick=async()=>{
    const r=await fetch(SUPABASE_URL+'/rest/v1/rpc/admin_mark_competition_member_attendance',{method:'POST',headers:{...auth(),Prefer:'return=representation'},body:JSON.stringify({p_competition_id:$('competitionAttendancePanel').dataset.competitionId,p_user_id:b.dataset.attMember,p_status:b.dataset.attStatus,p_note:null})});
    const d=await r.json().catch(()=>({})); if(!r.ok){msg('competitionMsg','❌ 更新簽到失敗：'+(d.message||d.hint||('HTTP '+r.status)));return} msg('competitionMsg','✅ 簽到狀態已更新。'); await loadCompetitionAttendance($('competitionAttendancePanel').dataset.competitionId);
  });
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


let growthMembers=[],growthLogs=[],growthTasks=[],growthAchievements=[];
const growthTaskTypeNames={profile_complete:'完成會員資料',first_registration:'第一次報名',first_result:'第一次參賽成績',registration_count:'報名次數',result_count:'成績次數'}; const growthTaskCycleNames={one_time:'一次性',daily:'每日',weekly:'每週'}; const growthAchievementRarityNames={common:'普通',rare:'稀有',epic:'史詩',legendary:'傳說'};
const growthAchievementTypeNames={registration_count:'報名次數',result_place:'名次成績',points:'累積積分'}; const rewardCategoryNames={cash:'現金折抵',discount:'折扣優惠',gift:'贈品',other:'其他'};
async function loadGrowthManagers(){
  const [tr,ar]=await Promise.all([
    fetch(SUPABASE_URL+'/rest/v1/growth_tasks?select=*&order=created_at.asc',{headers:auth()}),
    fetch(SUPABASE_URL+'/rest/v1/growth_achievements?select=*&order=created_at.asc',{headers:auth()})
  ]);
  growthTasks=tr.ok?await tr.json():[]; growthAchievements=ar.ok?await ar.json():[];
  renderGrowthManagers();
}
function renderGrowthManagers(){
  const tl=$('growthTaskList'),al=$('growthAchievementList');
  if(tl) tl.innerHTML=growthTasks.map(x=>'<article class="notice"><div class="date">'+(x.active?'🟢 啟用':'⚪ 停用')+' · '+esc(x.code)+'</div><h3>'+esc(x.title)+'</h3><p>'+esc(x.description||'')+'</p><p>條件：'+esc(growthTaskTypeNames[x.task_type]||x.task_type)+' × '+esc(x.requirement_count)+'　獎勵：<b>+'+esc(x.reward_points)+' 💎</b></p><button class="btn secondary growthEditTask" type="button" data-id="'+esc(x.id)+'">✏️ 編輯</button><button class="btn secondary growthToggleTask" type="button" data-id="'+esc(x.id)+'" data-active="'+(!x.active)+'">'+(x.active?'⏸️ 停用':'▶️ 啟用')+'</button></article>').join('')||'<div class="empty">目前沒有任務。</div>';
  if(al) al.innerHTML=growthAchievements.map(x=>'<article class="notice"><div class="date">'+(x.active?'🟢 啟用':'⚪ 停用')+' · '+esc(x.code)+'</div><h3>'+esc(x.title)+'</h3><p>'+esc(x.description||'')+'</p><p>條件：'+esc(growthAchievementTypeNames[x.achievement_type]||x.achievement_type)+' × '+esc(x.requirement_count)+'　獎勵：<b>+'+esc(x.reward_points)+' 💎</b></p><button class="btn secondary growthEditAchievement" type="button" data-id="'+esc(x.id)+'">✏️ 編輯</button><button class="btn secondary growthToggleAchievement" type="button" data-id="'+esc(x.id)+'" data-active="'+(!x.active)+'">'+(x.active?'⏸️ 停用':'▶️ 啟用')+'</button></article>').join('')||'<div class="empty">目前沒有成就。</div>';
  document.querySelectorAll('.growthEditTask').forEach(b=>b.onclick=()=>editGrowthTask(b.dataset.id));
  document.querySelectorAll('.growthToggleTask').forEach(b=>b.onclick=()=>toggleGrowthTask(b.dataset.id,b.dataset.active==='true'));
  document.querySelectorAll('.growthEditAchievement').forEach(b=>b.onclick=()=>editGrowthAchievement(b.dataset.id));
  document.querySelectorAll('.growthToggleAchievement').forEach(b=>b.onclick=()=>toggleGrowthAchievement(b.dataset.id,b.dataset.active==='true'));
}
function clearGrowthTask(){['growthTaskId','growthTaskCode','growthTaskTitle','growthTaskDescription'].forEach(id=>{if($(id))$(id).value=''});if($('growthTaskType'))$('growthTaskType').value='profile_complete';if($('growthTaskCycle'))$('growthTaskCycle').value='one_time';if($('growthTaskStartAt'))$('growthTaskStartAt').value='';if($('growthTaskEndAt'))$('growthTaskEndAt').value='';if($('growthTaskRequirement'))$('growthTaskRequirement').value=1;if($('growthTaskReward'))$('growthTaskReward').value=10;if($('growthTaskActive'))$('growthTaskActive').checked=true;if($('growthTaskMsg'))$('growthTaskMsg').textContent=''}

let growthRewards=[];
let rewardAchievements=[];
async function loadRewardManagers(){
  try{
    const [rr,ar,red]=await Promise.all([
      fetch(SUPABASE_URL+'/rest/v1/growth_rewards?select=*&order=sort_order.asc,created_at.asc',{headers:auth()}),
      fetch(SUPABASE_URL+'/rest/v1/growth_achievements?select=id,title&order=created_at.asc',{headers:auth()}),
      fetch(SUPABASE_URL+'/rest/v1/growth_reward_redemptions?select=*,growth_rewards(title)&order=created_at.desc&limit=200',{headers:auth()})
    ]);
    growthRewards=rr.ok?await rr.json():[]; rewardAchievements=ar.ok?await ar.json():[];
    const reds=red.ok?await red.json():[];
    const sel=$('rewardAchievement'); if(sel){const old=sel.value;sel.innerHTML='<option value="">無</option>'+rewardAchievements.map(a=>'<option value="'+esc(a.id)+'">'+esc(a.title)+'</option>').join('');sel.value=old;}
    $('adminRewards').innerHTML=growthRewards.length?growthRewards.map(r=>{const ach=rewardAchievements.find(a=>a.id===r.required_achievement_id);return '<article class="notice"><div class="date">'+(r.enabled?'🟢 啟用':'⚪ 停用')+' · '+esc(r.code)+'</div><h3>'+esc(r.icon||'🎁')+' '+esc(r.title)+'</h3><p>'+esc(r.description||'')+'</p><p><b>💎 '+Number(r.point_cost).toLocaleString()+' 點</b> · 最低等級：'+esc(r.min_level)+(ach?' · 成就：'+esc(ach.title):'')+'</p><p class="sub">每人上限：'+(r.user_limit??'不限')+' · 總上限：'+(r.total_limit??'不限')+'</p><div class="competitionActions"><button class="btn secondary" type="button" onclick="editGrowthReward(\''+esc(r.id)+'\')">✏️ 編輯</button><button class="btn secondary" type="button" onclick="deleteGrowthReward(\''+esc(r.id)+'\')">🗑️ 刪除</button></div></article>'}).join(''):'<div class="empty">目前沒有獎勵。</div>';
    $('adminRewardRedemptions').innerHTML=reds.length?reds.map(x=>'<article class="notice"><div class="date">'+esc(new Date(x.created_at).toLocaleString('zh-TW'))+'</div><h3>🎁 '+esc(x.growth_rewards?.title||'會員獎勵')+'</h3><p>會員：'+esc(x.user_id)+' · '+esc(x.status==='redeemed'?'已兌換':'已取消')+'</p><p>扣除 💎 '+esc(x.point_cost)+' 點'+(x.coupon_id?' · 已產生優惠券':'')+'</p></article>').join(''):'<div class="empty">尚無兌換紀錄。</div>';
  }catch(e){console.error('獎勵管理載入失敗:',e);msg('rewardMsg','❌ '+e.message)}
}
async function deleteGrowthReward(id){if(!confirm('確定要刪除這個獎勵嗎？相關兌換紀錄也會一併刪除，且無法復原。'))return;try{const rd=await fetch(SUPABASE_URL+'/rest/v1/growth_reward_redemptions?reward_id=eq.'+encodeURIComponent(id),{method:'DELETE',headers:auth()});if(!rd.ok){const d0=await rd.json().catch(()=>({}));throw new Error(d0?.message||('HTTP '+rd.status))}const r=await fetch(SUPABASE_URL+'/rest/v1/growth_rewards?id=eq.'+encodeURIComponent(id),{method:'DELETE',headers:auth()});if(!r.ok){const d=await r.json().catch(()=>({}));throw new Error(d?.message||('HTTP '+r.status))}msg('rewardMsg','✅ 獎勵已刪除');await loadRewardManagers()}catch(e){msg('rewardMsg','❌ '+e.message)}}
let downloadFiles=[];
async function loadDownloadFilesAdmin(){try{const r=await fetch(SUPABASE_URL+'/rest/v1/download_files?select=*&order=created_at.desc',{headers:auth()});downloadFiles=r.ok?await r.json():[];const el=$('adminDownloadFiles');if(el)el.innerHTML=downloadFiles.length?downloadFiles.map(x=>'<article class="notice"><div class="date">'+(x.published?'🟢 已發布':'⚪ 未發布')+' · '+esc(x.file_name||'')+'</div><h3>📎 '+esc(x.title)+'</h3><p>'+esc(x.description||'')+'</p><div class="competitionActions"><a class="btn secondary" href="'+esc(x.file_url)+'" target="_blank">🔗 開啟</a><button class="btn secondary" type="button" onclick="toggleDownloadPublish(\''+esc(x.id)+'\','+(!x.published)+')">'+(x.published?'⬇️ 取消發布':'📢 發布')+'</button><button class="btn secondary" type="button" onclick="deleteDownloadFile(\''+esc(x.id)+'\')">🗑️ 刪除</button></div></article>').join(''):'<div class="empty">目前沒有檔案。</div>'}catch(e){msg('downloadMsg','❌ '+e.message)}}
async function uploadDownloadFile(){const title=$('downloadTitle').value.trim(),desc=$('downloadDescription').value.trim(),f=$('downloadFileInput').files[0];if(!title||!f){msg('downloadMsg','請輸入檔案名稱並選擇檔案。');return}try{msg('downloadMsg','⏳ 上傳中…');const path='files/'+Date.now()+'_'+f.name;const up=await fetch(SUPABASE_URL+'/storage/v1/object/downloads/'+path.split('/').map(encodeURIComponent).join('/'),{method:'POST',headers:{...auth(),'Content-Type':f.type||'application/octet-stream'},body:f});if(!up.ok){const e2=await up.json().catch(()=>({}));throw new Error(e2.message||e2.error||('HTTP '+up.status))}const file_url=SUPABASE_URL+'/storage/v1/object/public/downloads/'+path;const published=$('downloadPublished').checked;const ins=await fetch(SUPABASE_URL+'/rest/v1/download_files',{method:'POST',headers:{...auth(),Prefer:'return=representation'},body:JSON.stringify({title,description:desc,file_name:f.name,file_url,published})});if(!ins.ok){const e3=await ins.json().catch(()=>({}));throw new Error(e3.message||('HTTP '+ins.status))}msg('downloadMsg','✅ 檔案已上傳'+(published?'並發布到前台':''));$('downloadTitle').value='';$('downloadDescription').value='';$('downloadFileInput').value='';await loadDownloadFilesAdmin()}catch(e){msg('downloadMsg','❌ '+e.message)}}
async function toggleDownloadPublish(id,pub){try{const r=await fetch(SUPABASE_URL+'/rest/v1/download_files?id=eq.'+encodeURIComponent(id),{method:'PATCH',headers:auth(),body:JSON.stringify({published:pub})});if(!r.ok)throw new Error('HTTP '+r.status);await loadDownloadFilesAdmin()}catch(e){msg('downloadMsg','❌ '+e.message)}}
async function deleteDownloadFile(id){if(!confirm('確定要刪除這個檔案嗎？前台也會無法下載。'))return;try{const x=downloadFiles.find(v=>v.id===id);if(x&&x.file_url){const m=x.file_url.split('/storage/v1/object/public/downloads/')[1];if(m)await fetch(SUPABASE_URL+'/storage/v1/object/downloads/'+m,{method:'DELETE',headers:auth()})}const r=await fetch(SUPABASE_URL+'/rest/v1/download_files?id=eq.'+encodeURIComponent(id),{method:'DELETE',headers:auth()});if(!r.ok)throw new Error('HTTP '+r.status);msg('downloadMsg','✅ 檔案已刪除');await loadDownloadFilesAdmin()}catch(e){msg('downloadMsg','❌ '+e.message)}}
function editGrowthReward(id){const x=growthRewards.find(v=>v.id===id);if(!x)return;$('rewardId').value=x.id;$('rewardCode').value=x.code;$('rewardTitle').value=x.title;$('rewardDescription').value=x.description||'';$('rewardIcon').value=x.icon||'🎁';$('rewardCategory').value=x.category||'other';$('rewardPointCost').value=x.point_cost;$('rewardMinLevel').value=x.min_level||'newbie';$('rewardAchievement').value=x.required_achievement_id||'';$('rewardUserLimit').value=x.user_limit??'';$('rewardTotalLimit').value=x.total_limit??'';$('rewardCouponTitle').value=x.coupon_title||'';$('rewardCouponDescription').value=x.coupon_description||'';$('rewardCouponDiscount').value=x.coupon_discount||'';$('rewardCouponExpiresDays').value=x.coupon_expires_days??'';$('rewardAvailableFrom').value=x.available_from?new Date(x.available_from).toISOString().slice(0,16):'';$('rewardAvailableUntil').value=x.available_until?new Date(x.available_until).toISOString().slice(0,16):'';$('rewardSortOrder').value=x.sort_order??0;$('rewardEnabled').checked=!!x.enabled;window.scrollTo({top:$('rewardTab').offsetTop-20,behavior:'smooth'})}
function clearReward(){$('rewardId').value='';['rewardCode','rewardTitle','rewardDescription','rewardCouponTitle','rewardCouponDescription','rewardCouponDiscount','rewardUserLimit','rewardTotalLimit','rewardCouponExpiresDays','rewardAvailableFrom','rewardAvailableUntil'].forEach(id=>$(id).value='');$('rewardIcon').value='🎁';$('rewardCategory').value='cash';$('rewardPointCost').value=50;$('rewardMinLevel').value='newbie';$('rewardAchievement').value='';$('rewardSortOrder').value=0;$('rewardEnabled').checked=true}
async function saveGrowthReward(){
  const id=$('rewardId').value.trim(),code=$('rewardCode').value.trim(),title=$('rewardTitle').value.trim(),description=$('rewardDescription').value.trim(),icon=$('rewardIcon').value.trim()||'🎁',category=$('rewardCategory').value,point_cost=Number($('rewardPointCost').value),min_level=$('rewardMinLevel').value,required_achievement_id=$('rewardAchievement').value||null,user_limit=$('rewardUserLimit').value===''?null:Number($('rewardUserLimit').value),total_limit=$('rewardTotalLimit').value===''?null:Number($('rewardTotalLimit').value),coupon_title=$('rewardCouponTitle').value.trim()||null,coupon_description=$('rewardCouponDescription').value.trim()||null,coupon_discount=$('rewardCouponDiscount').value.trim()||null,coupon_expires_days=$('rewardCouponExpiresDays').value===''?null:Number($('rewardCouponExpiresDays').value),available_from=$('rewardAvailableFrom').value?new Date($('rewardAvailableFrom').value).toISOString():null,available_until=$('rewardAvailableUntil').value?new Date($('rewardAvailableUntil').value).toISOString():null,sort_order=Number($('rewardSortOrder').value||0),enabled=$('rewardEnabled').checked;
  if(!code||!title||!Number.isInteger(point_cost)||point_cost<1){msg('rewardMsg','請完整填寫獎勵資料。');return}
  if(user_limit!==null&&(!Number.isInteger(user_limit)||user_limit<1)){msg('rewardMsg','每人上限必須是正整數。');return}
  if(total_limit!==null&&(!Number.isInteger(total_limit)||total_limit<1)){msg('rewardMsg','總兌換上限必須是正整數。');return}
  if(coupon_expires_days!==null&&(!Number.isInteger(coupon_expires_days)||coupon_expires_days<1)){msg('rewardMsg','優惠券有效天數必須是正整數。');return}
  if(available_from&&available_until&&new Date(available_from)>=new Date(available_until)){msg('rewardMsg','開始時間必須早於結束時間。');return} const body={code,title,description,icon,category,reward_type:'coupon',point_cost,min_level,required_achievement_id,user_limit,total_limit,coupon_title,coupon_description,coupon_discount,coupon_expires_days,available_from,available_until,sort_order,enabled};
  try{const r=await fetch(SUPABASE_URL+'/rest/v1/growth_rewards'+(id?'?id=eq.'+encodeURIComponent(id):''),{method:id?'PATCH':'POST',headers:{...auth(),Prefer:'return=representation'},body:JSON.stringify(body)});const d=await r.json().catch(()=>null);if(!r.ok)throw new Error(d?.message||d?.hint||('HTTP '+r.status));msg('rewardMsg',id?'✅ 獎勵已更新':'✅ 獎勵已新增');clearReward();await loadRewardManagers()}catch(e){msg('rewardMsg','❌ '+e.message)}
}

function editGrowthTask(id){const x=growthTasks.find(v=>v.id===id);if(!x)return;$('growthTaskId').value=x.id;$('growthTaskCode').value=x.code;$('growthTaskTitle').value=x.title;$('growthTaskDescription').value=x.description||'';$('growthTaskType').value=x.task_type;$('growthTaskCycle').value=x.cycle_type||'one_time';$('growthTaskStartAt').value=x.start_at?new Date(x.start_at).toISOString().slice(0,16):'';$('growthTaskEndAt').value=x.end_at?new Date(x.end_at).toISOString().slice(0,16):'';$('growthTaskRequirement').value=x.requirement_count;$('growthTaskReward').value=x.reward_points;$('growthTaskActive').checked=!!x.active;window.scrollTo({top:$('growthTab').offsetTop-20,behavior:'smooth'})}
async function saveGrowthTask(){const id=$('growthTaskId').value.trim(),code=$('growthTaskCode').value.trim(),title=$('growthTaskTitle').value.trim(),description=$('growthTaskDescription').value.trim(),task_type=$('growthTaskType').value,cycle_type=$('growthTaskCycle').value,start_at=$('growthTaskStartAt').value?new Date($('growthTaskStartAt').value).toISOString():null,end_at=$('growthTaskEndAt').value?new Date($('growthTaskEndAt').value).toISOString():null,requirement_count=Number($('growthTaskRequirement').value),reward_points=Number($('growthTaskReward').value),active=$('growthTaskActive').checked;if(!code||!title||!Number.isInteger(requirement_count)||requirement_count<1||!Number.isInteger(reward_points)||reward_points<0){msg('growthTaskMsg','請完整填寫任務資料。');return}try{const body={code,title,description,task_type,cycle_type,start_at,end_at,requirement_count,reward_points,active};const r=await fetch(SUPABASE_URL+'/rest/v1/growth_tasks'+(id?'?id=eq.'+encodeURIComponent(id):''),{method:id?'PATCH':'POST',headers:{...auth(),Prefer:'return=representation'},body:JSON.stringify(body)});const d=await r.json().catch(()=>null);if(!r.ok)throw new Error(d?.message||d?.hint||('HTTP '+r.status));msg('growthTaskMsg',id?'✅ 任務已更新':'✅ 任務已新增');clearGrowthTask();await loadGrowthManagers()}catch(e){msg('growthTaskMsg','❌ '+e.message)}}
async function toggleGrowthTask(id,active){const r=await fetch(SUPABASE_URL+'/rest/v1/growth_tasks?id=eq.'+encodeURIComponent(id),{method:'PATCH',headers:{...auth(),Prefer:'return=minimal'},body:JSON.stringify({active})});if(!r.ok){const d=await r.json().catch(()=>({}));alert('更新任務狀態失敗：'+(d.message||d.hint||('HTTP '+r.status)));return}await loadGrowthManagers()}
function clearGrowthAchievement(){['growthAchievementId','growthAchievementCode','growthAchievementTitle','growthAchievementDescription'].forEach(id=>{if($(id))$(id).value=''});if($('growthAchievementIcon'))$('growthAchievementIcon').value='🏆';if($('growthAchievementRarity'))$('growthAchievementRarity').value='common';if($('growthAchievementHidden'))$('growthAchievementHidden').checked=false;if($('growthAchievementType'))$('growthAchievementType').value='registration_count';if($('growthAchievementRequirement'))$('growthAchievementRequirement').value=1;if($('growthAchievementReward'))$('growthAchievementReward').value=10;if($('growthAchievementActive'))$('growthAchievementActive').checked=true;if($('growthAchievementMsg'))$('growthAchievementMsg').textContent=''}
function editGrowthAchievement(id){const x=growthAchievements.find(v=>v.id===id);if(!x)return;$('growthAchievementId').value=x.id;$('growthAchievementCode').value=x.code;$('growthAchievementTitle').value=x.title;$('growthAchievementDescription').value=x.description||'';$('growthAchievementIcon').value=x.icon||'🏆';$('growthAchievementRarity').value=x.rarity||'common';$('growthAchievementHidden').checked=!!x.hidden;$('growthAchievementType').value=x.achievement_type;$('growthAchievementRequirement').value=x.requirement_count;$('growthAchievementReward').value=x.reward_points;$('growthAchievementActive').checked=!!x.active;window.scrollTo({top:$('growthTab').offsetTop-20,behavior:'smooth'})}
async function saveGrowthAchievement(){const id=$('growthAchievementId').value.trim(),code=$('growthAchievementCode').value.trim(),title=$('growthAchievementTitle').value.trim(),description=$('growthAchievementDescription').value.trim(),icon=$('growthAchievementIcon').value.trim()||'🏆',rarity=$('growthAchievementRarity').value,hidden=$('growthAchievementHidden').checked,achievement_type=$('growthAchievementType').value,requirement_count=Number($('growthAchievementRequirement').value),reward_points=Number($('growthAchievementReward').value),active=$('growthAchievementActive').checked;if(!code||!title||!Number.isInteger(requirement_count)||requirement_count<1||!Number.isInteger(reward_points)||reward_points<0){msg('growthAchievementMsg','請完整填寫成就資料。');return}try{const body={code,title,description,icon,rarity,hidden,achievement_type,requirement_count,reward_points,active};const r=await fetch(SUPABASE_URL+'/rest/v1/growth_achievements'+(id?'?id=eq.'+encodeURIComponent(id):''),{method:id?'PATCH':'POST',headers:{...auth(),Prefer:'return=representation'},body:JSON.stringify(body)});const d=await r.json().catch(()=>null);if(!r.ok)throw new Error(d?.message||d?.hint||('HTTP '+r.status));msg('growthAchievementMsg',id?'✅ 成就已更新':'✅ 成就已新增');clearGrowthAchievement();await loadGrowthManagers()}catch(e){msg('growthAchievementMsg','❌ '+e.message)}}
async function toggleGrowthAchievement(id,active){const r=await fetch(SUPABASE_URL+'/rest/v1/growth_achievements?id=eq.'+encodeURIComponent(id),{method:'PATCH',headers:{...auth(),Prefer:'return=minimal'},body:JSON.stringify({active})});if(!r.ok){const d=await r.json().catch(()=>({}));alert('更新成就狀態失敗：'+(d.message||d.hint||('HTTP '+r.status)));return}await loadGrowthManagers()}

async function loadGrowthResetHistory(uid){
  const box=$('growthResetHistory'); if(!box) return;
  if(!uid){box.innerHTML='<div class="empty">請先選擇會員。</div>';return;}
  const r=await fetch(SUPABASE_URL+'/rest/v1/growth_reset_history?user_id=eq.'+encodeURIComponent(uid)+'&select=*&order=created_at.desc&limit=50',{headers:auth()});
  const rows=r.ok?await r.json():[];
  box.innerHTML=rows.length?rows.map(x=>'<article class="notice"><div class="date">第 '+esc(x.reset_no)+' 次 · '+esc(new Date(x.created_at).toLocaleString('zh-TW'))+'</div><h3>🔄 '+esc(x.before_level)+' → '+esc(x.after_level)+'　💎 '+esc(x.before_points)+' → '+esc(x.after_points)+'</h3><p>活躍：'+esc(x.before_active_days)+' 天 · 連續：'+esc(x.before_login_streak)+' 天 · 任務：'+esc(x.before_completed_tasks)+' · 成就：'+esc(x.before_achievements)+'</p><p class="sub">原因：'+esc(x.reason||'管理員手動重置')+'</p></article>').join(''):'<div class="empty">這位會員還沒有重置紀錄。</div>';
}
async function resetGrowthMember(){
  const uid=$('growthResetMemberSelect')?.value;
  const reason=($('growthResetReason')?.value||'').trim()||'管理員手動重置';
  if(!uid){msg('growthResetMsg','請先選擇會員。');return;}
  const m=growthMembers.find(x=>x.id===uid); const name=m?.nickname||m?.email||'這位會員';
  const typed=prompt('這是完整重置，將把「'+name+'」的積分、等級、活躍／連續紀錄、任務與目前成就狀態清零。\n\n請輸入 RESET 確認：');
  if(typed!=='RESET'){msg('growthResetMsg','已取消重置。');return;}
  try{
    const r=await fetch(SUPABASE_URL+'/rest/v1/rpc/admin_reset_growth_member',{method:'POST',headers:{...auth(),'Content-Type':'application/json','Prefer':'return=representation'},body:JSON.stringify({p_user_id:uid,p_reason:reason})});
    const d=await r.json().catch(()=>null);
    if(!r.ok) throw new Error(d?.message||d?.hint||('HTTP '+r.status));
    msg('growthResetMsg','✅ 已完成第 '+esc(d.reset_no)+' 次重置：'+esc(d.before_points)+' → 0 點，'+esc(d.before_level)+' → 新手。');
    if($('growthResetReason'))$('growthResetReason').value='';
    await growthAdmin();
    const sel=$('growthResetMemberSelect'); if(sel)sel.value=uid;
    await loadGrowthResetHistory(uid);
  }catch(e){msg('growthResetMsg','❌ '+e.message)}
}
async function growthAdmin(){
  try{
    const vr=await fetch(SUPABASE_URL+'/rest/v1/visitor_accounts?select=id,email,active&order=created_at.asc',{headers:auth()}); const va=vr.ok?await vr.json():[];
    const pr=await fetch(SUPABASE_URL+'/rest/v1/profiles?select=id,member_no,nickname,growth_points,growth_level&order=member_no.asc',{headers:auth()}); const ps=pr.ok?await pr.json():[]; const pm=new Map(ps.map(x=>[x.id,x]));
    growthMembers=va.map(v=>({...v,...(pm.get(v.id)||{})}));
    const sel=$('growthMemberSelect'); if(sel){const q=($('growthMemberSearch')?.value||'').toLowerCase();const rows=growthMembers.filter(v=>!q||[v.email,v.nickname,v.member_no].some(x=>String(x||'').toLowerCase().includes(q)));sel.innerHTML=rows.map(v=>'<option value="'+esc(v.id)+'">會員 '+esc(v.member_no!=null?String(v.member_no).padStart(3,'0'):'—')+'｜'+esc(v.nickname||v.email||'—')+'｜💎 '+esc(v.growth_points||0)+'</option>').join('')||'<option value="">沒有符合的會員</option>'}
    const rsel=$('growthResetMemberSelect'); if(rsel){rsel.innerHTML=growthMembers.map(v=>'<option value="'+esc(v.id)+'">會員 '+esc(v.member_no!=null?String(v.member_no).padStart(3,'0'):'—')+'｜'+esc(v.nickname||v.email||'—')+'｜💎 '+esc(v.growth_points||0)+'</option>').join('')||'<option value="">沒有會員</option>'; if(growthMembers[0]){rsel.value=growthMembers[0].id; await loadGrowthResetHistory(rsel.value)}}
    const counts={newbie:0,bronze:0,silver:0,gold:0,diamond:0}; growthMembers.forEach(v=>counts[v.growth_level||'newbie']=(counts[v.growth_level||'newbie']||0)+1);
    $('growthAdminSummary').innerHTML='<div class="competitionSummaryItem"><b>'+growthMembers.length+'</b><span>會員</span></div>'+Object.entries(counts).map(([k,n])=>'<div class="competitionSummaryItem"><b>'+n+'</b><span>'+({newbie:'🌱 新手',bronze:'⭐ 青銅',silver:'🥈 白銀',gold:'🥇 黃金',diamond:'💎 鑽石'}[k])+'</span></div>').join('');
    const lr=await fetch(SUPABASE_URL+'/rest/v1/growth_point_transactions?select=*&order=created_at.desc&limit=200',{headers:auth()}); growthLogs=lr.ok?await lr.json():[]; renderGrowthLogs(); await loadGrowthManagers();
  }catch(e){console.error(e);msg('growthAdminMsg','❌ 載入失敗：'+e.message)}
}
function renderGrowthLogs(){const q=($('growthLogSearch')?.value||'').toLowerCase();const f=$('growthLogFilter')?.value||'all';const mm=new Map(growthMembers.map(x=>[x.id,x]));const rows=growthLogs.filter(x=>{const m=mm.get(x.user_id)||{};const hit=!q||[m.email,m.nickname,m.member_no,x.reason].some(v=>String(v||'').toLowerCase().includes(q));return hit&&(f==='all'||(f==='positive'&&x.amount>0)||(f==='negative'&&x.amount<0))});$('growthAdminLogs').innerHTML=rows.map(x=>{const m=mm.get(x.user_id)||{};return '<article class="notice"><div class="date">'+esc(new Date(x.created_at).toLocaleString('zh-TW'))+' · 會員 '+esc(m.member_no!=null?String(m.member_no).padStart(3,'0'):'—')+'</div><h3>'+esc(m.nickname||m.email||x.user_id)+'</h3><p><b class="'+(x.amount>0?'growthPlus':'growthMinus')+'">'+(x.amount>0?'+':'')+esc(x.amount)+' 💎</b>　'+esc(x.reason)+'</p></article>'}).join('')||'<div class="empty">目前沒有符合的積分紀錄。</div>'}
async function adjustGrowthPoints(){const uid=$('growthMemberSelect')?.value,amount=Number($('growthAmount')?.value),reason=$('growthReason')?.value.trim();if(!uid||!Number.isInteger(amount)||amount===0||!reason){msg('growthAdminMsg','請選擇會員、輸入非 0 整數積分與調整原因。');return}try{const r=await fetch(SUPABASE_URL+'/rest/v1/rpc/admin_adjust_growth_points',{method:'POST',headers:{...auth(),Prefer:'return=representation'},body:JSON.stringify({p_user_id:uid,p_amount:amount,p_reason:reason})});const d=await r.json().catch(()=>null);if(!r.ok)throw new Error(d?.message||d?.hint||('HTTP '+r.status));msg('growthAdminMsg','✅ 積分調整完成，目前積分：'+d);$('growthAmount').value='';$('growthReason').value='';await growthAdmin()}catch(e){msg('growthAdminMsg','❌ '+e.message)}}


let adminVideos=[];
function parseYouTubeId(url){try{const u=new URL(url);if(u.hostname.includes('youtu.be'))return u.pathname.slice(1).split('/')[0];const v=u.searchParams.get('v');if(v)return v;const m=u.pathname.match(/\/(?:embed|shorts)\/([^/?]+)/);return m?m[1]:''}catch{return ''}}
function clearVideo(){['videoId','videoTitle','videoUrl','videoDescription'].forEach(id=>{if($(id))$(id).value=''});if($('videoCategoryInput'))$('videoCategoryInput').value='其他';if($('videoSortOrder'))$('videoSortOrder').value=0;if($('videoFeatured'))$('videoFeatured').checked=false;if($('videoPublished'))$('videoPublished').checked=true;if($('videoPreview'))$('videoPreview').innerHTML='貼上網址後會自動顯示縮圖預覽。';if($('videoMsg'))$('videoMsg').textContent=''}
function previewVideo(){const id=parseYouTubeId($('videoUrl')?.value.trim()||'');$('videoPreview').innerHTML=id?'<div style="max-width:420px"><img src="https://img.youtube.com/vi/'+encodeURIComponent(id)+'/hqdefault.jpg" style="width:100%;border-radius:12px"><p class="sub">YouTube ID：'+esc(id)+'</p></div>':'貼上有效的 YouTube 網址後會自動顯示縮圖預覽。'}
async function loadVideosAdmin(){try{const r=await fetch(SUPABASE_URL+'/rest/v1/videos?select=*&order=sort_order.asc,published_at.desc',{headers:auth()});if(!r.ok)throw new Error('HTTP '+r.status);adminVideos=await r.json();renderAdminVideos()}catch(e){msg('videoMsg','❌ 載入影片失敗：'+e.message)}}
function renderAdminVideos(){const q=($('videoAdminSearch')?.value||'').toLowerCase();const rows=adminVideos.filter(v=>!q||[v.title,v.category,v.description].some(x=>String(x||'').toLowerCase().includes(q)));$('adminVideos').innerHTML=rows.map(v=>'<article class="notice"><div class="date">'+(v.published?'🟢 上架':'⚪ 下架')+' · '+esc(v.category)+' · '+(v.featured?'⭐ 精選':'一般')+'</div><h3>'+esc(v.title)+'</h3><div style="display:flex;gap:14px;align-items:flex-start;flex-wrap:wrap"><img src="'+esc(v.thumbnail_url)+'" style="width:220px;max-width:100%;aspect-ratio:16/9;object-fit:cover;border-radius:10px"><div style="flex:1;min-width:240px"><p>'+esc(v.description||'')+'</p><p class="sub">'+esc(v.youtube_url)+'</p><button class="btn" onclick="editVideo(\''+esc(v.id)+'\')">✏️ 編輯</button> <button class="btn secondary" onclick="deleteVideo(\''+esc(v.id)+'\')">🗑️ 刪除</button></div></div></article>').join('')||'<div class="empty">目前沒有影片。</div>'}
function editVideo(id){const v=adminVideos.find(x=>x.id===id);if(!v)return;$('videoId').value=v.id;$('videoTitle').value=v.title||'';$('videoUrl').value=v.youtube_url||'';$('videoDescription').value=v.description||'';$('videoCategoryInput').value=v.category||'其他';$('videoSortOrder').value=v.sort_order||0;$('videoFeatured').checked=!!v.featured;$('videoPublished').checked=!!v.published;previewVideo();document.querySelector('[data-tab="videoTab"]').click();window.scrollTo({top:$('videoTab').offsetTop-20,behavior:'smooth'})}
async function saveVideo(){const id=$('videoId').value.trim(),title=$('videoTitle').value.trim(),youtube_url=$('videoUrl').value.trim(),youtube_id=parseYouTubeId(youtube_url),description=$('videoDescription').value.trim(),category=$('videoCategoryInput').value,sort_order=Number($('videoSortOrder').value||0),featured=$('videoFeatured').checked,published=$('videoPublished').checked;if(!title||!youtube_url||!youtube_id){msg('videoMsg','請填寫標題與有效的 YouTube 網址。');return}try{const payload={...(id?{id}:{}),title,description,youtube_url,youtube_id,thumbnail_url:'https://img.youtube.com/vi/'+youtube_id+'/hqdefault.jpg',category,sort_order,featured,published,published_at:new Date().toISOString()};const r=await fetch(SUPABASE_URL+'/rest/v1/rpc/admin_upsert_video',{method:'POST',headers:{...auth(),'Content-Type':'application/json','Prefer':'return=representation'},body:JSON.stringify({p_video:payload})});const d=await r.json().catch(()=>null);if(!r.ok)throw new Error(d?.message||d?.hint||('HTTP '+r.status));msg('videoMsg',id?'✅ 影片已更新':'✅ 影片已新增');clearVideo();await loadVideosAdmin()}catch(e){msg('videoMsg','❌ '+e.message)}}
async function deleteVideo(id){if(!confirm('確定刪除這部影片？'))return;try{const r=await fetch(SUPABASE_URL+'/rest/v1/rpc/admin_delete_video',{method:'POST',headers:{...auth(),'Content-Type':'application/json'},body:JSON.stringify({p_video_id:id})});const d=await r.json().catch(()=>null);if(!r.ok)throw new Error(d?.message||d?.hint||('HTTP '+r.status));await loadVideosAdmin()}catch(e){alert('❌ 刪除失敗：'+e.message)}}

function recoverStoredSession(){
  let access=localStorage.getItem('access_token')||sessionStorage.getItem('access_token');
  let refresh=localStorage.getItem('refresh_token')||sessionStorage.getItem('refresh_token');
  if(access)return {access,refresh};
  for(const store of [localStorage,sessionStorage]){
    for(const key of Object.keys(store)){
      if(!key.includes('auth-token'))continue;
      try{
        const raw=JSON.parse(store.getItem(key)||'null');
        const session=raw?.currentSession||raw?.session||raw;
        if(session?.access_token){
          access=session.access_token; refresh=session.refresh_token||refresh;
          localStorage.setItem('access_token',access);
          if(refresh)localStorage.setItem('refresh_token',refresh);
          return {access,refresh};
        }
      }catch(e){}
    }
  }
  return {access:null,refresh};
}
async function refreshAccessToken(){
  const stored=recoverStoredSession(), refreshToken=stored.refresh;
  if(!refreshToken)return false;
  try{
    const r=await fetch(SUPABASE_URL+'/auth/v1/token?grant_type=refresh_token',{method:'POST',headers:{'Content-Type':'application/json',apikey:SUPABASE_ANON_KEY},body:JSON.stringify({refresh_token:refreshToken})});
    const d=await r.json().catch(()=>({}));
    if(!r.ok||!d.access_token)return false;
    localStorage.setItem('access_token',d.access_token); if(d.refresh_token)localStorage.setItem('refresh_token',d.refresh_token); return true;
  }catch(e){console.error('refresh token:',e);return false}
}
async function ensureAdminSession(){
  const token=recoverStoredSession().access; if(token)return token;
  if(await refreshAccessToken())return localStorage.getItem('access_token'); return null;
}
async function callAiAnnouncement(payload){
  let token=await ensureAdminSession();
  if(!token)throw new Error('登入狀態不存在，請先重新登入管理後台。');
  const request=()=>fetch(SUPABASE_URL+'/functions/v1/ai-generate-announcement',{method:'POST',headers:{'Content-Type':'application/json',apikey:SUPABASE_ANON_KEY,Authorization:'Bearer '+token},body:JSON.stringify(payload)});
  let r=await request();
  if(r.status===401){const refreshed=await refreshAccessToken();if(refreshed){token=localStorage.getItem('access_token');r=await request();}}
  const d=await r.json().catch(()=>({})); if(!r.ok)throw new Error(d?.error||d?.message||d?.detail||('HTTP '+r.status)); return d;
}

async function generateAiAnnouncement(){
  if(!configured()){msg('aiAnnouncementMsg','❌ Supabase 尚未設定。');return}
  const topic=$('aiTopic')?.value.trim()||'', eventInfo=$('aiEventInfo')?.value.trim()||'', audience=$('aiAudience')?.value.trim()||'', importantNotes=$('aiImportantNotes')?.value.trim()||'', style=$('aiStyle')?.value||'活潑';
  if(!topic){msg('aiAnnouncementMsg','請先輸入公告主題。');return}
  const btn=$('generateAiAnnouncement'); if(btn)btn.disabled=true; msg('aiAnnouncementMsg','🤖 AI 正在撰寫公告…');
  try{
    const d=await callAiAnnouncement({topic,event_info:eventInfo,audience,important_notes:importantNotes,style});
    $('aiGeneratedTitle').value=d.title||'';$('aiGeneratedSummary').value=d.summary||'';$('aiGeneratedContent').value=d.content||'';
    msg('aiAnnouncementMsg','✅ 產生完成。你可以修改後套用到公告編輯器。');
  }catch(e){
    console.error(e);
    if(String(e.message).includes('登入狀態不存在')){msg('aiAnnouncementMsg','❌ 目前瀏覽器沒有可用的管理員登入 Session。請先重新登入一次，再按 AI 產生。');return}
    msg('aiAnnouncementMsg','❌ '+e.message);
  }finally{if(btn)btn.disabled=false}
}
function clearAiAnnouncement(){['aiTopic','aiEventInfo','aiAudience','aiImportantNotes','aiGeneratedTitle','aiGeneratedSummary','aiGeneratedContent'].forEach(id=>{if($(id))$(id).value=''});if($('aiStyle'))$('aiStyle').value='活潑';msg('aiAnnouncementMsg','')}
function applyAiAnnouncement(){
  const title=$('aiGeneratedTitle')?.value.trim()||'',content=$('aiGeneratedContent')?.value.trim()||'';
  if(!title||!content){msg('aiAnnouncementMsg','❌ 請先產生公告。');return}
  if($('title'))$('title').value=title; if($('content'))$('content').value=content;
  const newsTab=document.querySelector('[data-tab="newsTab"]'); if(newsTab)newsTab.click();
  msg('publishMsg','✅ AI 草稿已套用；請確認後按「儲存公告」。');
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
  if($('competitionSearch'))$('competitionSearch').addEventListener('input',renderAdminCompetitions); if($('competitionStatusFilter'))$('competitionStatusFilter').addEventListener('change',renderAdminCompetitions); if($('competitionCategoryFilter'))$('competitionCategoryFilter').addEventListener('change',renderAdminCompetitions); if($('registrationSearch'))$('registrationSearch').addEventListener('input',renderCompetitionRegistrations); if($('exportCompetitionRegistrations'))$('exportCompetitionRegistrations').onclick=exportCompetitionRegistrations; if($('registrationStatusFilter'))$('registrationStatusFilter').addEventListener('change',renderCompetitionRegistrations);if($('attendanceStatusFilter'))$('attendanceStatusFilter').addEventListener('change',renderCompetitionAttendance); if($('loadActivityAnalytics'))$('loadActivityAnalytics').onclick=loadActivityAnalytics; if($('loadActivityBadges'))$('loadActivityBadges').onclick=loadActivityBadgesAdmin; if($('addActivityReward'))$('addActivityReward').onclick=addActivityReward;
  if($('loginButton'))$('loginButton').onclick=login;if($('refreshDashboard'))$('refreshDashboard').onclick=dashboard;if($('logoutButton'))$('logoutButton').onclick=logout;if($('saveContent'))$('saveContent').onclick=save;if($('publishButton'))$('publishButton').onclick=publish;if($('saveProduct'))$('saveProduct').onclick=saveProduct;if($('clearProduct'))$('clearProduct').onclick=clearProduct;if($('createVisitor'))$('createVisitor').onclick=createVisitor;if($('refreshGrowthAdmin'))$('refreshGrowthAdmin').onclick=growthAdmin;if($('refreshRewardsAdmin'))$('refreshRewardsAdmin').onclick=loadRewardManagers;if($('saveReward'))$('saveReward').onclick=saveGrowthReward;if($('clearReward'))$('clearReward').onclick=clearReward;if($('adjustGrowthPoints'))$('adjustGrowthPoints').onclick=adjustGrowthPoints;if($('saveGrowthTask'))$('saveGrowthTask').onclick=saveGrowthTask;if($('clearGrowthTask'))$('clearGrowthTask').onclick=clearGrowthTask;if($('saveGrowthAchievement'))$('saveGrowthAchievement').onclick=saveGrowthAchievement;if($('clearGrowthAchievement'))$('clearGrowthAchievement').onclick=clearGrowthAchievement;if($('growthMemberSearch'))$('growthMemberSearch').addEventListener('input',growthAdmin);if($('resetGrowthMember'))$('resetGrowthMember').onclick=resetGrowthMember;if($('growthResetMemberSelect'))$('growthResetMemberSelect').addEventListener('change',e=>loadGrowthResetHistory(e.target.value));if($('growthLogSearch'))$('growthLogSearch').addEventListener('input',renderGrowthLogs);if($('growthLogFilter'))$('growthLogFilter').addEventListener('change',renderGrowthLogs);if($('orderSearch'))$('orderSearch').addEventListener('input',renderAdminOrders);if($('orderStatusFilter'))$('orderStatusFilter').addEventListener('change',renderAdminOrders);if($('refreshOrdersAdmin'))$('refreshOrdersAdmin').onclick=ordersAdmin;if($('attendanceStatusFilter'))$('attendanceStatusFilter').addEventListener('change',renderCompetitionAttendance);if($('registrationSearch'))$('registrationSearch').addEventListener('input',renderCompetitionRegistrations);if($('registrationStatusFilter'))$('registrationStatusFilter').addEventListener('change',renderCompetitionRegistrations);if($('setSharedVisitorPassword'))$('setSharedVisitorPassword').onclick=setSharedVisitorPassword;if($('createCoupon'))$('createCoupon').onclick=createCoupon;if($('createNotification'))$('createNotification').onclick=createNotification;if($('generateAiAnnouncement'))$('generateAiAnnouncement').onclick=generateAiAnnouncement;if($('clearAiAnnouncement'))$('clearAiAnnouncement').onclick=clearAiAnnouncement;if($('applyAiAnnouncement'))$('applyAiAnnouncement').onclick=applyAiAnnouncement;if($('addCompetitionResult'))$('addCompetitionResult').onclick=()=>addCompetitionResult();if($('saveCompetition'))$('saveCompetition').onclick=saveCompetition;if($('showCompetitionQr'))$('showCompetitionQr').onclick=showCompetitionQr;if($('copyCompetitionQr'))$('copyCompetitionQr').onclick=copyCompetitionQr;if($('settleCompetition'))$('settleCompetition').onclick=settleCompetition;if($('publishCompetition'))$('publishCompetition').onclick=async()=>{const ok=await saveCompetition();const id=$('competitionId').value;if(ok&&id)await setCompetitionPublished(id,true)};if($('unpublishCompetition'))$('unpublishCompetition').onclick=async()=>{const id=$('competitionId').value;if(id)await setCompetitionPublished(id,false)};if($('clearCompetition'))$('clearCompetition').onclick=clearCompetition;if($('addCompetitionCategory'))$('addCompetitionCategory').onclick=addCompetitionCategory;if($('saveQuickLink'))$('saveQuickLink').onclick=saveQuickLink;if($('clearQuickLink'))$('clearQuickLink').onclick=clearQuickLink;if($('saveVideo'))$('saveVideo').onclick=saveVideo;if($('clearVideo'))$('clearVideo').onclick=clearVideo;if($('refreshVideosAdmin'))$('refreshVideosAdmin').onclick=loadVideosAdmin;if($('uploadDownloadFile'))$('uploadDownloadFile').onclick=uploadDownloadFile;if($('refreshDownloadFiles'))$('refreshDownloadFiles').onclick=loadDownloadFilesAdmin;if($('videoUrl'))$('videoUrl').addEventListener('input',previewVideo);if($('videoAdminSearch'))$('videoAdminSearch').addEventListener('input',renderAdminVideos);document.querySelectorAll('.tab').forEach(b=>b.onclick=()=>{document.querySelectorAll('.tabPanel').forEach(x=>x.classList.add('hidden'));document.querySelectorAll('.tab').forEach(x=>x.classList.remove('active'));$(b.dataset.tab).classList.remove('hidden');b.classList.add('active');if(b.dataset.tab==='dashboardTab')dashboard();if(b.dataset.tab==='newsTab')news();if(b.dataset.tab==='productTab')products();if(b.dataset.tab==='orderTab')ordersAdmin();if(b.dataset.tab==='visitorTab')visitors();if(b.dataset.tab==='growthTab')growthAdmin();if(b.dataset.tab==='rewardTab')loadRewardManagers();if(b.dataset.tab==='couponTab')coupons();if(b.dataset.tab==='competitionTab'){competitionCategories();competitions();if(!$('competitionResults').children.length)addCompetitionResult()}if(b.dataset.tab==='quickLinkTab')quickLinks();if(b.dataset.tab==='videoTab')loadVideosAdmin();if(b.dataset.tab==='downloadTab')loadDownloadFilesAdmin();if(b.dataset.tab==='supportTab')tickets();if(b.dataset.tab==='notificationTab')notifications()})}
document.addEventListener('DOMContentLoaded',()=>{bindMobileAdminNav();bind();const session=recoverStoredSession();if(session.access){localStorage.setItem('access_token',session.access);if(session.refresh)localStorage.setItem('refresh_token',session.refresh);$('login').classList.add('hidden');$('dashboard').classList.remove('hidden');load()}else if(!configured())msg('loginError','請把你原本可用的 config.js 放回來。')});
