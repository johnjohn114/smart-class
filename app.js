const esc=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
const $=id=>document.getElementById(id);
function configured(){return typeof SUPABASE_URL!=='undefined'&&typeof SUPABASE_ANON_KEY!=='undefined'&&SUPABASE_URL&&SUPABASE_ANON_KEY&&!String(SUPABASE_URL).includes('你的')&&!String(SUPABASE_URL).includes('請填入')&&!String(SUPABASE_ANON_KEY).includes('你的');}
function auth(){const t=localStorage.getItem('visitor_access_token');return {apikey:SUPABASE_ANON_KEY,Authorization:'Bearer '+(t||SUPABASE_ANON_KEY),'Content-Type':'application/json'};}
function visitorToken(){return localStorage.getItem('visitor_access_token');}
async function visitorLogin(){if(!configured()){show('visitorLoginError','尚未設定 Supabase。');return}const email=$('visitorEmail').value.trim(),password=$('visitorPassword').value;if(!email||!password){show('visitorLoginError','請輸入 Email 與密碼。');return}show('visitorLoginError','登入中…');try{const r=await fetch(SUPABASE_URL+'/auth/v1/token?grant_type=password',{method:'POST',headers:{'Content-Type':'application/json','apikey':SUPABASE_ANON_KEY},body:JSON.stringify({email,password})});const d=await r.json().catch(()=>({}));if(!r.ok||!d.access_token){show('visitorLoginError',d.error_description||d.msg||'登入失敗，請確認帳號密碼。');return}localStorage.setItem('visitor_access_token',d.access_token);if(d.refresh_token)localStorage.setItem('visitor_refresh_token',d.refresh_token);$('visitorGate')?.classList.add('hidden');$('visitorLogout')?.classList.remove('hidden');await loadSite();await loadMyTickets()}catch(e){console.error(e);show('visitorLoginError','無法連線到 Supabase。')}}
function visitorLogout(){localStorage.removeItem('visitor_access_token');localStorage.removeItem('visitor_refresh_token');location.href='index.html';}
function show(id,msg){const e=$(id);if(e)e.textContent=msg;}
async function loadSite(){if(!configured())return;try{const h={apikey:SUPABASE_ANON_KEY,Authorization:'Bearer '+SUPABASE_ANON_KEY};const s=await fetch(SUPABASE_URL+'/rest/v1/site_settings?select=*&id=eq.1',{headers:h});if(s.ok){const a=await s.json();if(a[0])apply(a[0])}const n=await fetch(SUPABASE_URL+'/rest/v1/announcements?select=*&published=eq.true&published_at=lte.'+encodeURIComponent(new Date().toISOString())+'&order=pinned.desc,published_at.desc,created_at.desc&limit=3',{headers:h});if(n.ok){const rows=await n.json();$('newsList')&&($('newsList').innerHTML=rows.length?rows.map(card).join(''):'<div class="empty">目前還沒有公告。</div>')}}catch(e){console.error(e);$('newsList')&&($('newsList').innerHTML='<div class="empty">目前無法載入公告。</div>')}}
function card(x){
  const link=x.link_url?'<p><a class="btn secondary" href="'+esc(x.link_url)+'" target="_blank" rel="noopener noreferrer">🔗 '+esc(x.link_label||'查看連結')+'</a></p>':'';
  return '<article class="notice"><div class="date">'+(x.pinned?'📌 ':'')+esc(x.date||String(x.published_at||'').slice(0,10))+' · '+esc(x.category||'最新消息')+'</div><h3>'+esc(x.title)+'</h3><p>'+esc(x.content).replace(/\n/g,'<br>')+'</p>'+link+'</article>';
}
function apply(s){const ids=['siteName','heroTitle','heroText','aboutTitle','aboutSubtitle','about1Title','about1Text','about2Title','about2Text','featuresTitle','featuresSubtitle','f1Title','f1Text','f2Title','f2Text','f3Title','f3Text','f4Title','f4Text','contact1','contact2','contact3'];const keys=['site_name','hero_title','hero_text','about_title','about_subtitle','about1_title','about1_text','about2_title','about2_text','features_title','features_subtitle','f1_title','f1_text','f2_title','f2_text','f3_title','f3_text','f4_title','f4_text','contact1','contact2','contact3'];ids.forEach((id,i)=>{const e=$(id);if(e&&s[keys[i]]!=null)e.textContent=s[keys[i]]});if(s.hero_image&&$('heroImage'))$('heroImage').src=s.hero_image;if(s.site_name){document.title=s.site_name;if($('footerName'))$('footerName').textContent=s.site_name;if($('footerText'))$('footerText').textContent='© 2026 '+s.site_name+'｜私人網站'}}
async function loadAllNews(category='all'){if(!configured())return;const h={apikey:SUPABASE_ANON_KEY,Authorization:'Bearer '+SUPABASE_ANON_KEY};let url=SUPABASE_URL+'/rest/v1/announcements?select=*&published=eq.true&published_at=lte.'+encodeURIComponent(new Date().toISOString())+'&order=pinned.desc,published_at.desc,created_at.desc';if(category!=='all')url+='&category=eq.'+encodeURIComponent(category);const r=await fetch(url,{headers:h});const rows=r.ok?await r.json():[];if($('allNews'))$('allNews').innerHTML=rows.length?rows.map(card).join(''):'<div class="empty">目前沒有符合條件的公告。</div>';document.querySelectorAll('.filter').forEach(b=>b.onclick=()=>{document.querySelectorAll('.filter').forEach(x=>x.classList.remove('active'));b.classList.add('active');loadAllNews(b.dataset.category)})}
async function loadProducts(){if(!configured())return;const h={apikey:SUPABASE_ANON_KEY,Authorization:'Bearer '+SUPABASE_ANON_KEY};const r=await fetch(SUPABASE_URL+'/rest/v1/products?select=*&active=eq.true&order=created_at.desc',{headers:h});const rows=r.ok?await r.json():[];if($('productGrid'))$('productGrid').innerHTML=rows.length?rows.map(productCard).join(''):'<div class="empty">目前沒有上架商品。</div>'}
function productCard(p){return '<article class="productCard">'+(p.image_url?'<img src="'+esc(p.image_url)+'" alt="'+esc(p.name)+'">':'<div class="productImage">📦</div>')+'<div class="productBody"><div class="date">'+esc(p.category||'商品')+'</div><h3>'+esc(p.name)+'</h3><p>'+esc(p.description||'')+'</p><strong>NT$ '+Number(p.price||0).toLocaleString()+'</strong></div></article>'}
async function sendTicket(){if(!visitorToken()){show('ticketMsg','請先登入訪客帳號。');return}const subject=$('ticketSubject').value.trim(),message=$('ticketMessage').value.trim();if(!subject||!message){show('ticketMsg','請填寫主旨與內容。');return}const r=await fetch(SUPABASE_URL+'/rest/v1/support_tickets',{method:'POST',headers:auth(),body:JSON.stringify({subject,message})});show('ticketMsg',r.ok?'✅ 已送出，管理員會處理。':'❌ 送出失敗，請稍後再試。');if(r.ok){$('ticketSubject').value='';$('ticketMessage').value='';await loadMyTickets()}}
async function loadMyTickets(){if(!$('myTickets')||!visitorToken())return;const r=await fetch(SUPABASE_URL+'/rest/v1/support_tickets?select=*&order=created_at.desc',{headers:auth()});const rows=r.ok?await r.json():[];$('myTickets').innerHTML=rows.length?rows.map(t=>'<article class="notice"><div class="date">'+esc(t.status)+' · '+esc(String(t.created_at).slice(0,10))+'</div><h3>'+esc(t.subject)+'</h3><p>'+esc(t.message).replace(/\n/g,'<br>')+'</p>'+(t.admin_reply?'<hr><p><b>管理員回覆：</b>'+esc(t.admin_reply).replace(/\n/g,'<br>')+'</p>':'')+'</article>').join(''):'<div class="empty">尚無客服紀錄。</div>'}

function couponStatus(c){
  if(c.used) return {text:'⚫ 已使用',cls:'used'};
  if(c.expires_at && new Date(c.expires_at)<new Date()) return {text:'⚪ 已過期',cls:'expired'};
  const soon=c.expires_at && (new Date(c.expires_at)-new Date()<7*86400000);
  return {text:soon?'🟡 即將到期':'🟢 可使用',cls:soon?'soon':'available'};
}
function couponCard(c){
  const s=couponStatus(c);
  return '<article class="couponCard '+s.cls+'"><div class="couponTop"><span>'+esc(s.text)+'</span><span>🎟️</span></div><h3>'+esc(c.title)+'</h3><p>'+esc(c.description||'')+'</p>'+(c.discount?'<strong class="couponDiscount">'+esc(c.discount)+'</strong>':'')+'<div class="couponCode">'+esc(c.code)+'</div><div class="date">'+(c.expires_at?'有效至：'+esc(String(c.expires_at).slice(0,10)):'無期限')+'</div></article>';
}
async function loadMyCoupons(){
  const box=$('myCoupons'), gate=$('couponGate');
  if(!box) return;
  if(!visitorToken()){
    box.classList.add('hidden'); gate?.classList.remove('hidden'); return;
  }
  gate?.classList.add('hidden'); box.classList.remove('hidden');
  const r=await fetch(SUPABASE_URL+'/rest/v1/coupons?select=*&order=created_at.desc',{headers:auth()});
  const rows=r.ok?await r.json():[];
  box.innerHTML=rows.length?rows.map(couponCard).join(''):'<div class="empty">目前沒有優惠券。</div>';
}

const competitionCategoryIcon=name=>{
  const icons={Minecraft:'🎮',蛋仔:'🥚'};
  return icons[name]||'🏆';
};

async function fetchCompetitionCategories(headers){
  // 優先使用後台管理的分類表；若公開 RLS 尚未開放，則自動由已公布比賽回推分類。
  let categories=[];
  try{
    const r=await fetch(SUPABASE_URL+'/rest/v1/competition_categories?select=id,name&order=name.asc',{headers});
    if(r.ok){
      const rows=await r.json();
      categories=rows.map(x=>x.name).filter(Boolean);
    }
  }catch(e){
    console.warn('讀取分類表失敗，改用已公布比賽分類。',e);
  }
  return [...new Set(categories)];
}

async function loadCompetitionMenu(){
  const menu=$('competitionMenu');
  if(!menu||!configured())return;
  const h={apikey:SUPABASE_ANON_KEY,Authorization:'Bearer '+SUPABASE_ANON_KEY};

  const r=await fetch(
    SUPABASE_URL+'/rest/v1/competitions?select=id,name,category&published=eq.true&order=event_date.desc,created_at.desc',
    {headers:h}
  );
  const rows=r.ok?await r.json():[];

  let categories=await fetchCompetitionCategories(h);
  rows.forEach(x=>{if(x.category&&!categories.includes(x.category))categories.push(x.category);});

  if(!categories.length){
    menu.innerHTML='<a href="competitions.html">📚 全部歷屆成績</a><span class="dropdownEmpty">目前沒有分類</span>';
    return;
  }

  const groups={};
  categories.forEach(cat=>groups[cat]=[]);
  rows.forEach(x=>{
    if(x.category){
      (groups[x.category]||(groups[x.category]=[])).push(x);
    }
  });

  menu.innerHTML='<a href="competitions.html">📚 全部歷屆成績</a>'
    +categories.map(cat=>{
      const icon=competitionCategoryIcon(cat);
      const items=groups[cat]||[];
      const list=items.length
        ? items.map(x=>'<a href="competitions.html?id='+encodeURIComponent(x.id)+'">'+esc(x.name)+'</a>').join('')
        : '<span class="dropdownEmpty">目前沒有公布比賽</span>';
      return '<div class="dropdownGroup"><b>'+icon+' '+esc(cat)+'</b>'
        +'<a href="competitions.html?category='+encodeURIComponent(cat)+'">查看 '+esc(cat)+' 全部成績</a>'
        +list+'</div>';
    }).join('');
}

async function loadCompetitionFilters(){
  const box=$('competitionFilters');
  if(!box||!configured())return;

  const h={apikey:SUPABASE_ANON_KEY,Authorization:'Bearer '+SUPABASE_ANON_KEY};
  const params=new URLSearchParams(location.search);
  const current=params.get('category')||'';

  const r=await fetch(
    SUPABASE_URL+'/rest/v1/competitions?select=category&published=eq.true',
    {headers:h}
  );
  const rows=r.ok?await r.json():[];

  let categories=await fetchCompetitionCategories(h);
  rows.forEach(x=>{if(x.category&&!categories.includes(x.category))categories.push(x.category);});

  box.innerHTML='<a class="'+(!current?'active':'')+'" href="competitions.html">全部</a>'
    +categories.map(cat=>{
      const active=current===cat?'active':'';
      return '<a class="'+active+'" href="competitions.html?category='+encodeURIComponent(cat)+'">'
        +competitionCategoryIcon(cat)+' '+esc(cat)+'</a>';
    }).join('');
}

async function loadQuickLinks(){
  const panel=$('quickLinksPanel');
  const list=$('quickLinksList');
  if(!panel||!list||!configured()){if(panel)panel.classList.add('hidden');return}
  const h={apikey:SUPABASE_ANON_KEY,Authorization:'Bearer '+SUPABASE_ANON_KEY};
  try{
    const r=await fetch(SUPABASE_URL+'/rest/v1/quick_links?select=id,name,url,icon,sort_order&visible=eq.true&order=sort_order.asc,created_at.asc',{headers:h});
    if(!r.ok){panel.classList.add('hidden');return}
    const rows=await r.json();
    if(!rows.length){panel.classList.add('hidden');return}
    list.innerHTML=rows.map(x=>{
      const icon=x.icon?'<span class="quickLinkIcon">'+esc(x.icon)+'</span>':'<span class="quickLinkIcon">🔗</span>';
      const target=/^https?:\/\//i.test(x.url)?' target="_blank" rel="noopener noreferrer"':'';
      return '<a class="quickLinkItem" href="'+esc(x.url)+'"'+target+'>'+icon+'<span>'+esc(x.name)+'</span></a>';
    }).join('');
    panel.classList.remove('hidden');
  }catch(e){
    console.error('快速連結載入失敗:',e);
    panel.classList.add('hidden');
  }
}


async function getCurrentUser(){
  const token=visitorToken();
  if(!token)return null;
  try{
    const r=await fetch(SUPABASE_URL+'/auth/v1/user',{headers:{apikey:SUPABASE_ANON_KEY,Authorization:'Bearer '+token}});
    if(!r.ok)return null;
    return await r.json();
  }catch(e){return null}
}
function competitionResultCard(r){
  const medal=r.place===1?'🥇':r.place===2?'🥈':r.place===3?'🥉':'';
  return '<article class="notice competitionResult"><div class="date">'+medal+' 第 '+esc(r.place)+' 名</div><h3>'+esc(r.player_name)+'</h3>'+(r.score!==null&&r.score!==undefined&&r.score!==''?'<p><b>分數：</b>'+esc(r.score)+'</p>':'')+(r.prize?'<p><b>獎項：</b>'+esc(r.prize)+'</p>':'')+'</article>';
}
async function loadCompetitionPage(){
  const box=$('competitionList');
  if(!box||!configured())return;
  const h={apikey:SUPABASE_ANON_KEY,Authorization:'Bearer '+SUPABASE_ANON_KEY};
  const params=new URLSearchParams(location.search);
  const id=params.get('id');
  const category=params.get('category');
  let url=SUPABASE_URL+'/rest/v1/competitions?select=*&published=eq.true&order=event_date.desc,created_at.desc';
  if(id)url+='&id=eq.'+encodeURIComponent(id);
  else if(category)url+='&category=eq.'+encodeURIComponent(category);
  const r=await fetch(url,{headers:h});
  const comps=r.ok?await r.json():[];
  if(!comps.length){box.innerHTML='<div class="empty">目前沒有已公布的比賽成績。</div>';return}
  const all=[];
  for(const c of comps){
    const rr=await fetch(SUPABASE_URL+'/rest/v1/competition_results?select=*&competition_id=eq.'+encodeURIComponent(c.id)+'&order=place.asc',{headers:h});
    const results=rr.ok?await rr.json():[];
    all.push('<section class="competitionCard"><div class="competitionHeader"><div><div class="date">'+esc(c.category)+' · '+esc(c.event_date||'未設定日期')+'</div><h2>'+esc(c.name)+'</h2></div></div>'+(c.description?'<p class="sub">'+esc(c.description).replace(/\n/g,'<br>')+'</p>':'')+'<div class="competitionResults">'+(results.length?results.map(competitionResultCard).join(''):'<div class="empty">這場比賽尚未輸入成績。</div>')+'</div></section>');
  }
  box.innerHTML=all.join('');
}

window.addEventListener('DOMContentLoaded',()=>{if($('visitorLoginButton'))$('visitorLoginButton').onclick=visitorLogin;if($('visitorLogout'))$('visitorLogout').onclick=visitorLogout;if(visitorToken()){$('visitorGate')?.classList.add('hidden');$('visitorLogout')?.classList.remove('hidden')}else if($('visitorGate'))$('visitorGate').classList.remove('hidden');if($('sendTicket'))$('sendTicket').onclick=sendTicket;if($('visitorGate')&&visitorToken())loadSite();else if(!$('visitorGate'))loadSite();if($('myCoupons')&&visitorToken())loadMyCoupons();loadQuickLinks();loadCompetitionMenu();loadCompetitionFilters();if($('competitionList')&&visitorToken())loadCompetitionPage();});
