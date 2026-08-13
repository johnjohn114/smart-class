const F=['site_name','hero_title','hero_text','hero_image','about_title','about_subtitle','about1_title','about1_text','about2_title','about2_text','features_title','features_subtitle','f1_title','f1_text','f2_title','f2_text','f3_title','f3_text','f4_title','f4_text','contact1','contact2','contact3'];
const $=id=>document.getElementById(id); const esc=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
function configured(){return typeof SUPABASE_URL!=='undefined'&&typeof SUPABASE_ANON_KEY!=='undefined'&&SUPABASE_URL&&SUPABASE_ANON_KEY&&!String(SUPABASE_URL).includes('你的')&&!String(SUPABASE_URL).includes('請填入')&&!String(SUPABASE_ANON_KEY).includes('你的')}
function auth(){const t=localStorage.getItem('access_token');return {'Content-Type':'application/json',apikey:SUPABASE_ANON_KEY,Authorization:'Bearer '+(t||SUPABASE_ANON_KEY)}}
function msg(id,t){if($(id))$(id).textContent=t}
async function login(){if(!configured()){msg('loginError','請把可用的 config.js 放回來。');return}const email=$('email').value.trim(),password=$('password').value;if(!email||!password){msg('loginError','請輸入 Email 與密碼。');return}msg('loginError','登入中…');try{const r=await fetch(SUPABASE_URL+'/auth/v1/token?grant_type=password',{method:'POST',headers:{'Content-Type':'application/json',apikey:SUPABASE_ANON_KEY},body:JSON.stringify({email,password})});const d=await r.json().catch(()=>({}));if(!r.ok||!d.access_token){msg('loginError',d.error_description||d.msg||'登入失敗。');return}localStorage.setItem('access_token',d.access_token);if(d.refresh_token)localStorage.setItem('refresh_token',d.refresh_token);const pr=await fetch(SUPABASE_URL+'/rest/v1/profiles?select=role&id=eq.'+encodeURIComponent(d.user?.id||'') ,{headers:{...auth(),'Authorization':'Bearer '+d.access_token}});const pa=pr.ok?await pr.json():[];if(pa[0]?.role!=='admin'){localStorage.removeItem('access_token');localStorage.removeItem('refresh_token');msg('loginError','此帳號不是管理員帳號。');return} $('login').classList.add('hidden');$('dashboard').classList.remove('hidden');await load() }catch(e){console.error(e);msg('loginError','無法連線到 Supabase。')}}
async function load(){await content();await news();await products();await visitors();await coupons();await tickets()}
async function content(){if(!configured()||!localStorage.getItem('access_token'))return;const r=await fetch(SUPABASE_URL+'/rest/v1/site_settings?select=*&id=eq.1',{headers:auth()});if(r.status===401){logout();return}if(!r.ok)return;const a=await r.json();if(a[0])F.forEach(k=>{if($(k))$(k).value=a[0][k]??''})}
async function save(){const body={};F.forEach(k=>body[k]=$(k)?.value||'');const r=await fetch(SUPABASE_URL+'/rest/v1/site_settings?id=eq.1',{method:'PATCH',headers:{...auth(),Prefer:'return=minimal'},body:JSON.stringify(body)});msg('contentMsg',r.ok?'✅ 已儲存':'❌ 儲存失敗：請檢查 RLS 權限。')}
async function publish(){const id=$('announcementId')?.value||'';const body={title:$('title').value.trim(),category:$('category').value,published_at:new Date($('published_at').value||new Date()).toISOString(),pinned:$('pinned').checked,content:$('content').value,published:true};if(!body.title||!body.content){msg('publishMsg','請填寫標題與內容。');return}const url=SUPABASE_URL+'/rest/v1/announcements'+(id?'?id=eq.'+encodeURIComponent(id):'');const r=await fetch(url,{method:id?'PATCH':'POST',headers:{...auth(),Prefer:'return=representation'},body:JSON.stringify(body)});msg('publishMsg',r.ok?'✅ 已儲存公告':'❌ 儲存失敗：請檢查 announcements RLS。');if(r.ok){clearAnnouncement();await news()}}
function clearAnnouncement(){$('title').value='';$('content').value='';$('category').value='最新消息';$('published_at').value='';$('pinned').checked=false;if($('announcementId'))$('announcementId').value=''}
async function news(){if(!configured()||!localStorage.getItem('access_token'))return;const r=await fetch(SUPABASE_URL+'/rest/v1/announcements?select=*&order=pinned.desc,published_at.desc,created_at.desc',{headers:auth()});if(!r.ok)return;const a=await r.json();$('adminList').innerHTML=a.map(x=>'<article class="notice"><div class="date">'+(x.pinned?'📌 ':'')+esc(x.category)+' · '+esc(String(x.published_at||x.date||'').slice(0,16).replace('T',' '))+'</div><h3>'+esc(x.title)+'</h3><p>'+esc(x.content).replace(/\n/g,'<br>')+'</p><button data-edit="'+esc(x.id)+'">✏️ 編輯</button> <button data-del="'+esc(x.id)+'">🗑️ 刪除</button></article>').join('')||'<div class="empty">目前沒有公告。</div>';document.querySelectorAll('[data-del]').forEach(b=>b.onclick=()=>delAnnouncement(b.dataset.del));document.querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>editAnnouncement(b.dataset.edit))}
async function editAnnouncement(id){const r=await fetch(SUPABASE_URL+'/rest/v1/announcements?id=eq.'+encodeURIComponent(id)+'&select=*',{headers:auth()});const a=r.ok?await r.json():[];const x=a[0];if(!x)return;$('announcementId')?.setAttribute('value',x.id);if(!$('announcementId')){const i=document.createElement('input');i.type='hidden';i.id='announcementId';document.querySelector('#newsTab .editor').prepend(i);i.value=x.id}else $('announcementId').value=x.id;$('title').value=x.title||'';$('content').value=x.content||'';$('category').value=x.category||'最新消息';$('pinned').checked=!!x.pinned;$('published_at').value=x.published_at?new Date(x.published_at).toISOString().slice(0,16):'';document.querySelector('[data-tab="newsTab"]').click();}
async function delAnnouncement(id){if(!confirm('確定刪除這則公告？'))return;const r=await fetch(SUPABASE_URL+'/rest/v1/announcements?id=eq.'+encodeURIComponent(id),{method:'DELETE',headers:auth()});if(!r.ok){let d=await r.json().catch(()=>({}));alert('刪除失敗：'+(d.message||d.hint||('HTTP '+r.status)));return}await news()}
async function products(){if(!$('adminProducts')||!configured()||!localStorage.getItem('access_token'))return;const r=await fetch(SUPABASE_URL+'/rest/v1/products?select=*&order=created_at.desc',{headers:auth()});const a=r.ok?await r.json():[];$('adminProducts').innerHTML=a.map(p=>'<article class="productCard">'+(p.image_url?'<img src="'+esc(p.image_url)+'" alt="'+esc(p.name)+'">':'<div class="productImage">📦</div>')+'<div class="productBody"><div class="date">'+(p.active?'🟢 上架':'⚪ 下架')+' · '+esc(p.category||'')+'</div><h3>'+esc(p.name)+'</h3><p>'+esc(p.description||'')+'</p><strong>NT$ '+Number(p.price||0).toLocaleString()+'</strong><div><button data-pedit="'+p.id+'">✏️ 編輯</button> <button data-pdel="'+p.id+'">🗑️ 刪除</button></div></div></article>').join('')||'<div class="empty">目前沒有商品。</div>';document.querySelectorAll('[data-pdel]').forEach(b=>b.onclick=()=>deleteProduct(b.dataset.pdel));document.querySelectorAll('[data-pedit]').forEach(b=>b.onclick=()=>editProduct(b.dataset.pedit))}
async function saveProduct(){const id=$('productId').value;const body={name:$('productName').value.trim(),category:$('productCategory').value.trim(),price:Number($('productPrice').value||0),image_url:$('productImage').value.trim(),description:$('productDescription').value,active:$('productActive').checked};if(!body.name){msg('productMsg','請輸入商品名稱。');return}const r=await fetch(SUPABASE_URL+'/rest/v1/products'+(id?'?id=eq.'+encodeURIComponent(id):''),{method:id?'PATCH':'POST',headers:{...auth(),Prefer:'return=representation'},body:JSON.stringify(body)});msg('productMsg',r.ok?'✅ 商品已儲存':'❌ 商品儲存失敗');if(r.ok){clearProduct();await products()}}
function clearProduct(){$('productId').value='';$('productName').value='';$('productCategory').value='';$('productPrice').value='';$('productImage').value='';$('productDescription').value='';$('productActive').checked=true}
async function editProduct(id){const r=await fetch(SUPABASE_URL+'/rest/v1/products?id=eq.'+encodeURIComponent(id)+'&select=*',{headers:auth()});const a=r.ok?await r.json():[];const p=a[0];if(!p)return;$('productId').value=p.id;$('productName').value=p.name||'';$('productCategory').value=p.category||'';$('productPrice').value=p.price||0;$('productImage').value=p.image_url||'';$('productDescription').value=p.description||'';$('productActive').checked=!!p.active;document.querySelector('[data-tab="productTab"]').click()}
async function deleteProduct(id){if(!confirm('確定刪除商品？'))return;const r=await fetch(SUPABASE_URL+'/rest/v1/products?id=eq.'+encodeURIComponent(id),{method:'DELETE',headers:auth()});if(!r.ok){alert('刪除失敗：請檢查 products RLS。');return}await products()}
async function visitors(){
  if(!$('visitorList')||!configured()||!localStorage.getItem('access_token'))return;
  const r=await fetch(SUPABASE_URL+'/rest/v1/visitor_accounts?select=*&order=created_at.desc',{headers:auth()});
  const a=r.ok?await r.json():[];
  $('visitorList').innerHTML=a.map(v=>'<article class="notice"><div class="date">'+esc(v.active?'🟢 啟用':'⚪ 停用')+'</div><h3>'+esc(v.email)+'</h3></article>').join('')||'<div class="empty">目前沒有訪客帳號。</div>';
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
async function coupons(){
  if(!$('adminCoupons')||!configured()||!localStorage.getItem('access_token'))return;
  await visitors();
  const r=await fetch(SUPABASE_URL+'/rest/v1/coupons?select=*,visitor_accounts(email)&order=created_at.desc',{headers:auth()});
  const a=r.ok?await r.json():[];
  $('adminCoupons').innerHTML=a.map(c=>'<article class="notice"><div class="date">'+esc(c.visitor_accounts?.email||'')+' · '+esc(c.expires_at?String(c.expires_at).slice(0,10):'無期限')+'</div><h3>🎟️ '+esc(c.title)+'</h3><p>'+esc(c.description||'')+'</p><p><b>優惠碼：</b>'+esc(c.code)+(c.discount?'　<b>'+esc(c.discount)+'</b>':'')+'</p><button data-cdel="'+esc(c.id)+'">🗑️ 刪除優惠券</button></article>').join('')||'<div class="empty">目前沒有優惠券。</div>';
  document.querySelectorAll('[data-cdel]').forEach(b=>b.onclick=()=>deleteCoupon(b.dataset.cdel));
}
async function createCoupon(){
  const title=$('couponTitle').value.trim(), description=$('couponDescription').value.trim(), code=$('couponCode').value.trim(), discount=$('couponDiscount').value.trim(), expires=$('couponExpires').value, target=$('couponVisitor').value;
  if(!title||!code){msg('couponMsg','請至少填寫優惠券名稱與優惠碼。');return}
  const body={title,description,code,discount:discount||null,expires_at:expires?expires+'T23:59:59Z':null};
  try{
    if(target==='all'){
      const vr=await fetch(SUPABASE_URL+'/rest/v1/visitor_accounts?select=id&active=eq.true',{headers:auth()});
      const visitors=vr.ok?await vr.json():[];
      if(!visitors.length){msg('couponMsg','目前沒有啟用中的訪客。');return}
      body.user_id=undefined;
      const rows=visitors.map(v=>({...body,user_id:v.id}));
      const r=await fetch(SUPABASE_URL+'/rest/v1/coupons',{method:'POST',headers:{...auth(),Prefer:'return=minimal'},body:JSON.stringify(rows)});
      if(!r.ok)throw new Error('發送失敗 HTTP '+r.status);
    }else{
      body.user_id=target;
      const r=await fetch(SUPABASE_URL+'/rest/v1/coupons',{method:'POST',headers:{...auth(),Prefer:'return=minimal'},body:JSON.stringify(body)});
      if(!r.ok)throw new Error('發送失敗 HTTP '+r.status);
    }
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
async function tickets(){if(!$('ticketList')||!configured()||!localStorage.getItem('access_token'))return;const r=await fetch(SUPABASE_URL+'/rest/v1/support_tickets?select=*&order=created_at.desc',{headers:auth()});const a=r.ok?await r.json():[];$('ticketList').innerHTML=a.map(t=>'<article class="notice"><div class="date">'+esc(t.status)+' · '+esc(String(t.created_at).slice(0,16).replace('T',' '))+'</div><h3>'+esc(t.subject)+'</h3><p>'+esc(t.message).replace(/\n/g,'<br>')+'</p><label>管理員回覆<textarea data-reply="'+t.id+'" rows="4">'+esc(t.admin_reply||'')+'</textarea></label><button data-replybtn="'+t.id+'">💬 儲存回覆</button></article>').join('')||'<div class="empty">目前沒有客服訊息。</div>';document.querySelectorAll('[data-replybtn]').forEach(b=>b.onclick=()=>replyTicket(b.dataset.replybtn))}
async function replyTicket(id){const ta=document.querySelector('[data-reply="'+CSS.escape(id)+'"]');const reply=ta?ta.value:'';const r=await fetch(SUPABASE_URL+'/rest/v1/support_tickets?id=eq.'+encodeURIComponent(id),{method:'PATCH',headers:{...auth(),Prefer:'return=minimal'},body:JSON.stringify({admin_reply:reply,status:reply?'answered':'open'})});alert(r.ok?'已儲存回覆。':'儲存失敗。');if(r.ok)await tickets()}
function logout(){localStorage.removeItem('access_token');localStorage.removeItem('refresh_token');location.reload()}
function bind(){if($('loginButton'))$('loginButton').onclick=login;if($('logoutButton'))$('logoutButton').onclick=logout;if($('saveContent'))$('saveContent').onclick=save;if($('publishButton'))$('publishButton').onclick=publish;if($('saveProduct'))$('saveProduct').onclick=saveProduct;if($('clearProduct'))$('clearProduct').onclick=clearProduct;if($('createVisitor'))$('createVisitor').onclick=createVisitor;if($('setSharedVisitorPassword'))$('setSharedVisitorPassword').onclick=setSharedVisitorPassword;if($('createCoupon'))$('createCoupon').onclick=createCoupon;document.querySelectorAll('.tab').forEach(b=>b.onclick=()=>{document.querySelectorAll('.tabPanel').forEach(x=>x.classList.add('hidden'));document.querySelectorAll('.tab').forEach(x=>x.classList.remove('active'));$(b.dataset.tab).classList.remove('hidden');b.classList.add('active');if(b.dataset.tab==='newsTab')news();if(b.dataset.tab==='productTab')products();if(b.dataset.tab==='visitorTab')visitors();if(b.dataset.tab==='couponTab')coupons();if(b.dataset.tab==='supportTab')tickets()})}
document.addEventListener('DOMContentLoaded',()=>{bind();if(localStorage.getItem('access_token')){$('login').classList.add('hidden');$('dashboard').classList.remove('hidden');load()}else if(!configured())msg('loginError','請把你原本可用的 config.js 放回來。')});
