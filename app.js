const esc=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
const $=id=>document.getElementById(id);
function configured(){return typeof SUPABASE_URL!=='undefined'&&typeof SUPABASE_ANON_KEY!=='undefined'&&SUPABASE_URL&&SUPABASE_ANON_KEY&&!String(SUPABASE_URL).includes('你的')&&!String(SUPABASE_URL).includes('請填入')&&!String(SUPABASE_ANON_KEY).includes('你的');}
function auth(){const t=localStorage.getItem('visitor_access_token');return {apikey:SUPABASE_ANON_KEY,Authorization:'Bearer '+(t||SUPABASE_ANON_KEY),'Content-Type':'application/json'};}
function visitorToken(){return localStorage.getItem('visitor_access_token');}
async function refreshVisitorSession(){
  const rt=localStorage.getItem('visitor_refresh_token');
  if(!rt||!configured())return false;
  try{
    const r=await fetch(SUPABASE_URL+'/auth/v1/token?grant_type=refresh_token',{method:'POST',headers:{'Content-Type':'application/json','apikey':SUPABASE_ANON_KEY},body:JSON.stringify({refresh_token:rt})});
    const d=await r.json().catch(()=>({}));
    if(!r.ok||!d.access_token)return false;
    localStorage.setItem('visitor_access_token',d.access_token);
    if(d.refresh_token)localStorage.setItem('visitor_refresh_token',d.refresh_token);
    return true;
  }catch(e){return false}
}
async function ensureVisitorSession(){
  if(!visitorToken())return false;
  const u=await getCurrentUser();
  if(u)return true;
  const refreshed=await refreshVisitorSession();
  if(!refreshed){visitorLogout();return false;}
  return !!(await getCurrentUser());
}
async function visitorLogin(){if(!configured()){show('visitorLoginError','尚未設定 Supabase。');return}const email=$('visitorEmail').value.trim(),password=$('visitorPassword').value;if(!email||!password){show('visitorLoginError','請輸入 Email 與密碼。');return}show('visitorLoginError','登入中…');$('visitorLoginButton')?.setAttribute('disabled','disabled');try{const r=await fetch(SUPABASE_URL+'/auth/v1/token?grant_type=password',{method:'POST',headers:{'Content-Type':'application/json','apikey':SUPABASE_ANON_KEY},body:JSON.stringify({email,password})});const d=await r.json().catch(()=>({}));if(!r.ok||!d.access_token){show('visitorLoginError',d.error_description||d.msg||'登入失敗，請確認帳號密碼。');return}localStorage.setItem('visitor_access_token',d.access_token);if(d.refresh_token)localStorage.setItem('visitor_refresh_token',d.refresh_token);$('visitorGate')?.classList.add('hidden');$('visitorLogout')?.classList.remove('hidden');await loadSite();await loadMyTickets()}catch(e){console.error(e);show('visitorLoginError','無法連線到 Supabase。')}finally{$('visitorLoginButton')?.removeAttribute('disabled')}}
function visitorLogout(){localStorage.removeItem('visitor_access_token');localStorage.removeItem('visitor_refresh_token');location.href='index.html';}
function bindMobileNav(){
  document.querySelectorAll('.mobileNavToggle').forEach(btn=>{
    btn.addEventListener('click',()=>{
      const nav=btn.nextElementSibling; if(!nav)return;
      const open=nav.classList.toggle('mobileOpen');
      btn.setAttribute('aria-expanded',open?'true':'false');
      btn.textContent=open?'✕ 關閉選單':'☰ 選單';
    });
  });
  document.querySelectorAll('nav a').forEach(a=>a.addEventListener('click',()=>{
    const nav=a.closest('nav'); const btn=nav?.previousElementSibling;
    if(nav?.classList.contains('mobileOpen')){nav.classList.remove('mobileOpen');btn?.setAttribute('aria-expanded','false');if(btn)btn.textContent='☰ 選單';}
  }));
}
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

async function loadCompetitionMenu(){
  const menus=[...document.querySelectorAll('#competitionMenu')];
  if(!menus.length||!configured())return;
  const cacheKey='competition-menu-v4';
  const now=Date.now();
  try{
    const cached=sessionStorage.getItem(cacheKey);
    if(cached){
      const data=JSON.parse(cached);
      if(data?.at && now-data.at<5*60*1000 && Array.isArray(data.groups)){
        renderCompetitionMenus(menus,data.groups); return;
      }
    }
  }catch(e){}
  const h={apikey:SUPABASE_ANON_KEY,Authorization:'Bearer '+SUPABASE_ANON_KEY};
  try{
    const [cr,gr]=await Promise.all([
      fetch(SUPABASE_URL+'/rest/v1/competitions?select=id,name,category&published=eq.true&order=event_date.desc,created_at.desc&limit=200',{headers:h}),
      fetch(SUPABASE_URL+'/rest/v1/competition_categories?select=name,parent_category&order=name.asc&limit=100',{headers:h})
    ]);
    const rows=cr.ok?await cr.json():[];
    const cats=gr.ok?await gr.json():[];
    const groups={minecraft:[],egg:[],custom:[]};
    cats.forEach(c=>{
      if(!c?.name||c.name==='Minecraft'||c.name==='蛋仔')return;
      if(c.parent_category==='蛋仔') groups.egg.push(c.name);
      else groups.custom.push(c.name);
    });
    // 若舊資料尚未完成 migration，名稱含「蛋仔」的既有分類仍歸入蛋仔子選單。
    rows.forEach(x=>{
      const cat=x?.category;
      if(!cat||cat==='Minecraft'||cat==='蛋仔')return;
      if(!cats.some(c=>c.name===cat) && cat.includes('蛋仔') && !groups.egg.includes(cat)) groups.egg.push(cat);
      else if(!cats.some(c=>c.name===cat) && !groups.custom.includes(cat)) groups.custom.push(cat);
    });
    groups.egg.sort((a,b)=>a.localeCompare(b,'zh-Hant'));
    groups.custom.sort((a,b)=>a.localeCompare(b,'zh-Hant'));
    const data={at:now,groups};
    try{sessionStorage.setItem(cacheKey,JSON.stringify(data));}catch(e){}
    renderCompetitionMenus(menus,groups);
  }catch(e){
    console.error('歷屆成績選單載入失敗:',e);
    renderCompetitionMenus(menus,{minecraft:[],egg:[],custom:[]});
  }
}
function renderCompetitionMenus(menus,groups){
  const link=(cat,icon)=>'<a href="competitions.html?category='+encodeURIComponent(cat)+'">'+icon+' '+esc(cat)+' 分類</a>';
  const eggChildren=(groups.egg||[]).map(cat=>'<a class="dropdownSubLink" href="competitions.html?category='+encodeURIComponent(cat)+'">'+esc(cat)+'</a>').join('');
  const custom=(groups.custom||[]).map(cat=>link(cat,'🏷️')).join('');
  const egg=
    '<div class="dropdownNested">'+
      '<a class="dropdownNestedTitle" href="competitions.html?category='+encodeURIComponent('蛋仔')+'">🥚 蛋仔派對 <span>▸</span></a>'+
      (eggChildren?'<div class="dropdownSubmenu">'+eggChildren+'</div>':'')+
    '</div>';
  const html='<a href="competitions.html">📚 全部歷屆成績</a><a href="competitions.html#leaderboard">🏆 達人榜</a>'+link('Minecraft','🎮')+egg+custom;
  menus.forEach(m=>m.innerHTML=html);
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
function competitionStatus(date){
  if(!date)return {key:'unknown',label:'日期未設定',icon:'📅'};
  const d=new Date(date+'T00:00:00');
  const now=new Date();
  const today=new Date(now.getFullYear(),now.getMonth(),now.getDate());
  const event=new Date(d.getFullYear(),d.getMonth(),d.getDate());
  if(event.getTime()>today.getTime())return {key:'upcoming',label:'即將開始',icon:'🟢'};
  if(event.getTime()===today.getTime())return {key:'today',label:'今天舉行',icon:'🟡'};
  return {key:'ended',label:'已結束',icon:'⚪'};
}
function competitionStatusBadge(date){const s=competitionStatus(date);return '<span class="competitionStatus status-'+s.key+'">'+s.icon+' '+s.label+'</span>';}
function competitionResultCard(r){
  const medal=r.place===1?'🥇':r.place===2?'🥈':r.place===3?'🥉':'';
  return '<article class="notice competitionResult"><div class="date">'+medal+' 第 '+esc(r.place)+' 名</div><h3>'+esc(r.player_name)+'</h3>'+(r.score!==null&&r.score!==undefined&&r.score!==''?'<p><b>分數：</b>'+esc(r.score)+'</p>':'')+(r.prize?'<p><b>獎項：</b>'+esc(r.prize)+'</p>':'')+'</article>';
}
const LEADERBOARD_POINTS={1:5,2:3,3:2};

function leaderboardPoints(place){
  const n=Number(place);
  return LEADERBOARD_POINTS[n]??1;
}
function leaderboardMedal(rank){
  return rank===1?'🥇':rank===2?'🥈':rank===3?'🥉':'🏅';
}
function leaderboardRankClass(rank){
  return rank<=3?' topRank':'';
}
function renderLeaderboardRow(x){
  const medal=leaderboardMedal(x.rank);
  const displayName=x.player_name||'未命名會員';
  return '<article class="leaderboardRow'+leaderboardRankClass(x.rank)+'">'+
    '<div class="leaderboardRank">'+medal+' <b>#'+x.rank+'</b></div>'+
    '<div class="leaderboardPlayer"><h3>'+esc(displayName)+'</h3><div class="leaderboardMeta">'+
      '積分 <b>'+x.points+'</b>　·　參賽 '+x.events+' 場　·　🥇 '+x.first+'　🥈 '+x.second+'　🥉 '+x.third+
    '</div></div>'+
  '</article>';
}
async function loadLeaderboard(category){
  const box=$('leaderboardList'), summary=$('leaderboardSummary');
  if(!box||!configured())return;
  box.innerHTML='<div class="loading">正在整理達人榜…</div>';
  if(summary)summary.innerHTML='';
  const h={apikey:SUPABASE_ANON_KEY,Authorization:'Bearer '+SUPABASE_ANON_KEY};
  try{
    const cr=await fetch(SUPABASE_URL+'/rest/v1/competitions?select=id,name,category,event_date&published=eq.true&order=event_date.desc,created_at.desc&limit=2000',{headers:h});
    if(!cr.ok){throw new Error('competitions '+cr.status)}
    const comps=await cr.json();
    const compMap=new Map(comps.map(c=>[String(c.id),c]));
    const ids=comps.map(c=>String(c.id));
    if(category) comps.splice(0,comps.length,...comps.filter(c=>c.category===category));
    const allowed=new Set(comps.map(c=>String(c.id)));
    if(!ids.length || !allowed.size){
      if(summary)summary.innerHTML='<div class="leaderboardStat"><b>0</b><span>上榜玩家</span></div><div class="leaderboardStat"><b>'+comps.length+'</b><span>計入比賽</span></div>';
      box.innerHTML='<div class="empty">目前還沒有公開比賽成績建立達人榜。</div>';
      return;
    }
    const rr=await fetch(SUPABASE_URL+'/rest/v1/competition_results?select=competition_id,user_id,player_name,place,score,prize&competition_id=in.('+[...allowed].map(encodeURIComponent).join(',')+')&limit=5000',{headers:h});
    if(!rr.ok){throw new Error('competition_results '+rr.status)}
    const results=await rr.json();
    const map=new Map();
    results.forEach(r=>{
      const cid=String(r.competition_id||'');
      if(!allowed.has(cid))return;
      const key=r.user_id?('u:'+r.user_id):('n:'+String(r.player_name||'').trim().toLowerCase());
      if(!key || key==='n:')return;
      if(!map.has(key))map.set(key,{player_name:r.player_name||'未命名會員',points:0,events:0,first:0,second:0,third:0});
      const x=map.get(key), place=Number(r.place);
      x.points+=leaderboardPoints(place);
      x.events+=1;
      if(place===1)x.first++;
      else if(place===2)x.second++;
      else if(place===3)x.third++;
      if(r.player_name)x.player_name=r.player_name;
    });
    const rows=[...map.values()].sort((a,b)=>
      b.points-a.points||b.first-a.first||b.second-a.second||b.third-a.third||b.events-a.events||String(a.player_name).localeCompare(String(b.player_name),'zh-Hant')
    );
    let last=null;
    rows.forEach((x,i)=>{
      const same=last&&x.points===last.points&&x.first===last.first&&x.second===last.second&&x.third===last.third&&x.events===last.events;
      x.rank=same?last.rank:i+1; last=x;
    });
    if(summary)summary.innerHTML='<div class="leaderboardStat"><b>'+rows.length+'</b><span>上榜玩家</span></div><div class="leaderboardStat"><b>'+comps.length+'</b><span>計入比賽</span></div>';
    box.innerHTML=rows.length?rows.slice(0,50).map(renderLeaderboardRow).join(''):'<div class="empty">目前還沒有足夠的公開成績建立達人榜。</div>';
    if(rows.length>50)box.innerHTML+='<div class="empty leaderboardMore">目前顯示前 50 名。</div>';
  }catch(e){
    console.error('達人榜載入失敗:',e);
    box.innerHTML='<div class="empty">目前無法載入達人榜，請稍後再試。</div>';
  }
}


async function getMyRegistration(competitionId){
  if(!visitorToken())return null;
  const uid=(await getCurrentUser())?.id;if(!uid)return null;
  const r=await fetch(SUPABASE_URL+'/rest/v1/competition_registrations?select=*&competition_id=eq.'+encodeURIComponent(competitionId)+'&user_id=eq.'+encodeURIComponent(uid)+'&limit=1',{headers:auth()});
  if(!r.ok)return null; const a=await r.json(); return a[0]||null;
}
async function loadRegistrationProfile(){
  const u=await getCurrentUser(); if(!u)return null;
  const r=await fetch(SUPABASE_URL+'/rest/v1/profiles?id=eq.'+encodeURIComponent(u.id)+'&select=id,nickname,member_no',{headers:auth()});
  const p=(r.ok?(await r.json()):[])[0]||{};
  return {id:u.id,email:u.email||'',nickname:p.nickname||'',member_no:p.member_no};
}
function registrationStatusText(status){return {active:'已報名',pending:'待審核',approved:'已通過',rejected:'未通過',cancelled:'已取消'}[status]||'未報名'}
function registrationStatusIcon(status){return {active:'🟢',pending:'🟡',approved:'🟢',rejected:'🔴',cancelled:'⚪'}[status]||'📝'}
function registrationDeadlineText(c){if(!c.registration_deadline)return '';const d=new Date(c.registration_deadline);if(Number.isNaN(d.getTime()))return '';return ' · 報名截止：'+d.toLocaleString('zh-TW',{year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit'})}
function registrationForm(c,reg,profile){
  const status=reg?.status||'未報名'; const active=['active','pending','approved'].includes(status);
  const deadlinePassed=c.registration_deadline && Date.now()>new Date(c.registration_deadline).getTime();
  const fields=Array.isArray(c.registration_fields)?c.registration_fields:[];
  const custom=reg?.custom_fields||{};
  const fieldHtml=fields.map((name,i)=>'<label>'+esc(name)+'<input data-reg-field="'+esc(String(i))+'" data-field-name="'+esc(name)+'" value="'+esc(custom[name]||'')+'" maxlength="200" '+(active?'disabled':'')+'></label>').join('');
  let actions='';
  if(active) actions='<button class="btn secondary" data-reg-edit="'+esc(c.id)+'">✏️ 修改報名</button><button class="btn secondary" data-reg-cancel="'+esc(c.id)+'">❌ 取消報名</button>';
  else if(!deadlinePassed) actions='<button class="btn" data-reg-submit="'+esc(c.id)+'">📝 '+(status==='cancelled'?'重新報名':status==='rejected'?'重新申請':'我要報名')+'</button>';
  else actions='<span class="sub">⛔ 報名已截止</span>';
  return '<div class="registrationBox" data-registration-box="'+esc(c.id)+'"><div class="registrationStatus">'+registrationStatusIcon(status)+' 報名狀態：<b>'+esc(registrationStatusText(status))+'</b>'+registrationDeadlineText(c)+(c.registration_capacity?' · 名額上限：'+esc(c.registration_capacity):'')+'</div>'+
    (active?'<p class="sub">已完成報名。如需更改資料，可按「修改報名」。':'<p class="sub">登入會員可直接報名，會員基本資料會自動帶入。'+(c.registration_approval?' 此活動需要管理員審核。':'')+'</p>')+
    '<div class="registrationForm"><label>會員編號<input value="'+esc(profile?.member_no!=null?String(profile.member_no).padStart(3,'0'):'—')+'" readonly></label><label>暱稱<input data-reg-nickname value="'+esc(reg?.nickname||profile?.nickname||'')+'" maxlength="40" '+(active?'disabled':'')+'></label><label>Email<input value="'+esc(reg?.email||profile?.email||'')+'" readonly></label><label>備註／補充說明<textarea data-reg-note maxlength="1000" rows="3" '+(active?'disabled':'')+'>'+esc(reg?.note||'')+'</textarea></label>'+fieldHtml+'</div><div class="competitionActions">'+actions+'</div><small data-reg-msg></small></div>';
}
async function prepareRegistrationBox(c,box){
  if(!box||!visitorToken())return;
  const profile=await loadRegistrationProfile(); const reg=await getMyRegistration(c.id);
  box.innerHTML=registrationForm(c,reg,profile); bindRegistrationBox(c,box);
}
function bindRegistrationBox(c,box){
  const submit=box.querySelector('[data-reg-submit]'); const edit=box.querySelector('[data-reg-edit]'); const cancel=box.querySelector('[data-reg-cancel]');
  if(submit)submit.onclick=()=>submitRegistration(c,box);
  if(edit)edit.onclick=()=>{box.querySelectorAll('input[data-reg-nickname],textarea[data-reg-note],input[data-reg-field]').forEach(x=>x.disabled=false);edit.remove();const b=document.createElement('button');b.className='btn';b.textContent='💾 儲存修改';box.querySelector('.competitionActions').prepend(b);b.onclick=()=>updateRegistration(c,box)};
  if(cancel)cancel.onclick=()=>cancelRegistration(c,box);
}
function collectCustomFields(box){const out={};box.querySelectorAll('[data-reg-field]').forEach(x=>{const n=x.dataset.fieldName;if(n)out[n]=x.value.trim()});return out}
async function createMemberNotification(title,content){try{const uid=(await getCurrentUser())?.id;if(!uid)return;await fetch(SUPABASE_URL+'/rest/v1/notifications',{method:'POST',headers:{...auth(),Prefer:'return=minimal'},body:JSON.stringify([{user_id:uid,type:'比賽',title,content}])})}catch(e){console.error('通知建立失敗',e)}}
async function submitRegistration(c,box){
  const profile=await loadRegistrationProfile(); if(!profile){box.querySelector('[data-reg-msg]').textContent='請先登入。';return}
  const nickname=box.querySelector('[data-reg-nickname]')?.value.trim()||''; const note=box.querySelector('[data-reg-note]')?.value.trim()||null; if(!nickname){box.querySelector('[data-reg-msg]').textContent='請輸入暱稱。';return}
  const existing=await getMyRegistration(c.id); const custom_fields=collectCustomFields(box);
  const url=SUPABASE_URL+'/rest/v1/competition_registrations'+(existing?'?id=eq.'+encodeURIComponent(existing.id):'');
  const opts=existing?{method:'PATCH',headers:{...auth(),Prefer:'return=minimal'},body:JSON.stringify({member_no:profile.member_no,nickname,email:profile.email,note,custom_fields,status:'active',cancelled_at:null})}:{method:'POST',headers:{...auth(),Prefer:'return=representation'},body:JSON.stringify({competition_id:c.id,user_id:profile.id,member_no:profile.member_no,nickname,email:profile.email,note,custom_fields,status:'active'})};
  const r=await fetch(url,opts); const d=await r.json().catch(()=>({})); const msgEl=box.querySelector('[data-reg-msg]');
  if(!r.ok){msgEl.textContent='❌ '+(d.message||d.hint||'報名失敗，請稍後再試。');return}
  const resultStatus=(d?.[0]?.status)||null; msgEl.textContent=resultStatus==='pending'?'✅ 已送出報名，等待管理員審核。':'✅ '+(existing?'已重新報名！':'報名成功！'); await createMemberNotification('📝 '+c.name+' 報名結果',resultStatus==='pending'?'報名已送出，等待管理員審核。':'報名已成功。'); await prepareRegistrationBox(c,box); loadMyCompetitions();
}
async function updateRegistration(c,box){
  const nickname=box.querySelector('[data-reg-nickname]')?.value.trim()||''; const note=box.querySelector('[data-reg-note]')?.value.trim()||null; if(!nickname){box.querySelector('[data-reg-msg]').textContent='請輸入暱稱。';return}
  const uid=(await getCurrentUser())?.id;if(!uid)return; const custom_fields=collectCustomFields(box);
  const r=await fetch(SUPABASE_URL+'/rest/v1/competition_registrations?competition_id=eq.'+encodeURIComponent(c.id)+'&user_id=eq.'+encodeURIComponent(uid)+'&status=in.(active,pending,approved)',{method:'PATCH',headers:{...auth(),Prefer:'return=minimal'},body:JSON.stringify({nickname,note,custom_fields})});
  box.querySelector('[data-reg-msg]').textContent=r.ok?'✅ 報名資料已更新。':'❌ 更新失敗，請稍後再試。'; if(r.ok)await prepareRegistrationBox(c,box); if(r.ok)loadMyCompetitions();
}
async function cancelRegistration(c,box){
  if(!confirm('確定要取消這場活動的報名嗎？'))return; const uid=(await getCurrentUser())?.id;if(!uid)return;
  const r=await fetch(SUPABASE_URL+'/rest/v1/competition_registrations?competition_id=eq.'+encodeURIComponent(c.id)+'&user_id=eq.'+encodeURIComponent(uid)+'&status=in.(active,pending,approved)',{method:'PATCH',headers:{...auth(),Prefer:'return=minimal'},body:JSON.stringify({status:'cancelled',cancelled_at:new Date().toISOString()})});
  box.querySelector('[data-reg-msg]').textContent=r.ok?'✅ 已取消報名。':'❌ 取消失敗，請稍後再試。'; if(r.ok){await createMemberNotification('📝 '+c.name+' 已取消報名','你的報名已取消。');await prepareRegistrationBox(c,box);loadMyCompetitions();}
}

async function loadCompetitionPage(){
  const box=$('competitionList');
  if(!box||!configured())return;
  const h={apikey:SUPABASE_ANON_KEY,Authorization:'Bearer '+SUPABASE_ANON_KEY};
  const params=new URLSearchParams(location.search);
  const id=params.get('id');
  const category=params.get('category');
  const status=params.get('status');
  await loadLeaderboard(category);
  let url=SUPABASE_URL+'/rest/v1/competitions?select=*&published=eq.true&order=event_date.desc,created_at.desc';
  if(id)url+='&id=eq.'+encodeURIComponent(id);
  else if(category)url+='&category=eq.'+encodeURIComponent(category);
  const r=await fetch(url,{headers:h});
  let comps=r.ok?await r.json():[];
  if(status&&['upcoming','today','ended'].includes(status))comps=comps.filter(c=>competitionStatus(c.event_date).key===status);
  comps.sort((a,b)=>{
    const rank={upcoming:0,today:1,unknown:2,ended:3};
    const ra=rank[competitionStatus(a.event_date).key]??2, rb=rank[competitionStatus(b.event_date).key]??2;
    if(ra!==rb)return ra-rb;
    return String(b.event_date||'').localeCompare(String(a.event_date||''))||String(b.created_at||'').localeCompare(String(a.created_at||''));
  });
  if(!comps.length){box.innerHTML='<div class="empty">目前沒有符合條件的活動／比賽。</div>';return}
  const all=[];
  for(const c of comps){
    const rr=await fetch(SUPABASE_URL+'/rest/v1/competition_results?select=*&competition_id=eq.'+encodeURIComponent(c.id)+'&order=place.asc',{headers:h});
    const results=rr.ok?await rr.json():[];
    const regBox=(visitorToken()&&competitionStatus(c.event_date).key!=='ended')?'<div id="reg-'+esc(c.id)+'" class="registrationBox"><div class="loading">正在載入報名資訊…</div></div>':'';
    all.push('<section class="competitionCard"><div class="competitionHeader"><div><div class="date">'+esc(c.category||'未分類')+' · '+esc(c.event_date||'未設定日期')+' '+competitionStatusBadge(c.event_date)+'</div><h2>'+esc(c.name)+'</h2></div></div>'+(c.description?'<p class="sub">'+esc(c.description).replace(/\n/g,'<br>')+'</p>':'')+regBox+'<div class="competitionResults">'+(results.length?results.map(competitionResultCard).join(''):'<div class="empty">這場比賽尚未輸入成績。</div>')+'</div></section>');
  }
  box.innerHTML=all.join('');
  for(const c of comps){const rb=$('reg-'+c.id);if(rb)prepareRegistrationBox(c,rb);}
}



async function loadMyProfile(){
  const box=$('myProfile'); if(!box||!visitorToken()) return;
  const u=await getCurrentUser(); if(!u) return;
  const r=await fetch(SUPABASE_URL+'/rest/v1/profiles?id=eq.'+encodeURIComponent(u.id)+'&select=id,nickname,member_no,role,created_at',{headers:auth()});
  const a=r.ok?await r.json():[]; const p=a[0]; if(!p)return;
  const vr=await fetch(SUPABASE_URL+'/rest/v1/visitor_accounts?id=eq.'+encodeURIComponent(u.id)+'&select=active',{headers:auth()});
  const va=vr.ok?(await vr.json())[0]:null;
  if($('myAccountStatus'))$('myAccountStatus').textContent=va?.active===false?'⚪ 已停用':'🟢 啟用中';
  if($('myMemberNo'))$('myMemberNo').textContent=p.member_no!=null?String(p.member_no).padStart(3,'0'):'—';
  if($('myEmail'))$('myEmail').textContent=u.email||'—';
  if($('myCreatedAt'))$('myCreatedAt').textContent=p.created_at?new Date(p.created_at).toLocaleDateString('zh-TW'):'—';
  if($('profileNickname'))$('profileNickname').value=p.nickname||'';
}
async function saveMyProfile(){
  if(!visitorToken())return;
  const nickname=$('profileNickname')?.value.trim()||'';
  if(!nickname){show('profileMsg','請輸入暱稱。');return}
  const r=await fetch(SUPABASE_URL+'/rest/v1/profiles?id=eq.'+encodeURIComponent((await getCurrentUser()).id),{method:'PATCH',headers:{...auth(),Prefer:'return=minimal'},body:JSON.stringify({nickname})});
  show('profileMsg',r.ok?'✅ 個人資料已更新。':'❌ 更新失敗，請稍後再試。');
}
async function changeMyPassword(){
  const pw=$('newPassword')?.value||'', pw2=$('newPassword2')?.value||'';
  if(pw.length<8){show('passwordMsg','密碼至少需要 8 碼。');return}
  if(pw!==pw2){show('passwordMsg','兩次輸入的密碼不一致。');return}
  const r=await fetch(SUPABASE_URL+'/auth/v1/user',{method:'PUT',headers:{...auth()},body:JSON.stringify({password:pw})});
  show('passwordMsg',r.ok?'✅ 密碼已更新。':'❌ 密碼更新失敗，請重新登入後再試。');
  if(r.ok){$('newPassword').value='';$('newPassword2').value='';}
}
async function loadMyCompetitions(){
  const box=$('myCompetitions'); if(!box||!visitorToken())return;
  const uid=(await getCurrentUser())?.id;if(!uid)return;
  const r=await fetch(SUPABASE_URL+'/rest/v1/competition_registrations?select=*,competitions(id,name,category,event_date,description,published)&user_id=eq.'+encodeURIComponent(uid)+'&order=created_at.desc',{headers:auth()});
  const regs=r.ok?await r.json():[];
  const rr=await fetch(SUPABASE_URL+'/rest/v1/competition_results?select=id,competition_id,place,score,prize,player_name&user_id=eq.'+encodeURIComponent(uid)+'&order=created_at.desc',{headers:auth()});
  const results=rr.ok?await rr.json():[];
  const resultByComp=new Map(results.map(x=>[x.competition_id,x]));
  box.innerHTML=regs.length?regs.map(x=>{const res=resultByComp.get(x.competition_id);return '<article class="notice"><div class="date">'+esc(x.competitions?.category||'')+' · '+esc(x.competitions?.event_date||'未設定日期')+' '+competitionStatusBadge(x.competitions?.event_date)+'</div><h3>📝 '+esc(x.competitions?.name||'活動／比賽')+'</h3><p><b>報名狀態：</b>'+esc(registrationStatusText(x.status))+'　<b>報名暱稱：</b>'+esc(x.nickname||'')+(x.note?'　<b>備註：</b>'+esc(x.note):'')+'</p>'+(res?'<p>🏆 <b>成績：</b>第 '+esc(res.place)+' 名'+(res.score!=null?'　分數 '+esc(res.score):'')+(res.prize?'　獎項 '+esc(res.prize):'')+'</p>':'')+'</article>'}).join(''):'<div class="empty">目前還沒有報名或比賽紀錄。</div>';
}
async function loadMyAwards(){
  const box=$('myAwards'); if(!box||!visitorToken())return;
  const r=await fetch(SUPABASE_URL+'/rest/v1/competition_results?select=id,place,score,prize,player_name,competitions(name,category,event_date)&user_id=eq.'+encodeURIComponent((await getCurrentUser()).id)+'&or=(prize.not.is.null,place.lte.3)&order=created_at.desc',{headers:auth()});
  const rows=r.ok?await r.json():[];
  const awards=rows.filter(x=>x.prize||Number(x.place)<=3);
  box.innerHTML=awards.length?awards.map(x=>'<article class="notice"><div class="date">'+(Number(x.place)===1?'🥇':Number(x.place)===2?'🥈':Number(x.place)===3?'🥉':'🏅')+' '+esc(x.competitions?.category||'')+' · '+esc(x.competitions?.event_date||'')+'</div><h3>'+esc(x.competitions?.name||'比賽')+'</h3><p><b>名次：</b>'+esc(x.place)+(x.prize?'　<b>獎項：</b>'+esc(x.prize):'')+'</p></article>').join(''):'<div class="empty">目前還沒有獎項紀錄。</div>';
}
let myNotificationRows=[];
function notificationIcon(type){return type==='比賽'?'🏆':type==='優惠券'?'🎟️':type==='客服'?'💬':'📢'}
async function loadNotificationBadge(){
  const btn=document.querySelector('.myNavMenu')?.previousElementSibling;
  if(!btn||!visitorToken()||!configured())return;
  const uid=(await getCurrentUser())?.id;if(!uid)return;
  const r=await fetch(SUPABASE_URL+'/rest/v1/notifications?select=id&user_id=eq.'+encodeURIComponent(uid)+'&read_at=is.null',{headers:auth()});
  const rows=r.ok?await r.json():[];
  let badge=btn.querySelector('.notificationBadge');
  if(rows.length){if(!badge){badge=document.createElement('span');badge.className='notificationBadge';btn.appendChild(badge)}badge.textContent=rows.length>99?'99+':String(rows.length)}else if(badge)badge.remove();
}
function renderMyNotifications(){
  const box=$('myNotifications'); if(!box)return;
  const filter=$('notificationFilter')?.value||'all';
  const rows=filter==='unread'?myNotificationRows.filter(x=>!x.read_at):filter==='read'?myNotificationRows.filter(x=>x.read_at):myNotificationRows;
  const unread=myNotificationRows.filter(x=>!x.read_at).length;
  const summary=$('notificationSummary'); if(summary)summary.textContent='共 '+myNotificationRows.length+' 則通知 · 未讀 '+unread+' 則';
  box.innerHTML=rows.length?rows.map(x=>'<article class="notice '+(x.read_at?'':'unreadNotice')+'"><div class="date">'+(x.read_at?'':'🔴 未讀 · ')+notificationIcon(x.type)+' '+esc(x.type||'一般')+' · '+esc(String(x.created_at).slice(0,16).replace('T',' '))+'</div><h3>'+esc(x.title)+'</h3><p>'+esc(x.content).replace(/\n/g,'<br>')+'</p>'+(!x.read_at?'<button class="markRead" data-notice="'+esc(x.id)+'">標記已讀</button>':'')+'</article>').join(''):'<div class="empty">'+(filter==='unread'?'目前沒有未讀通知。':filter==='read'?'目前沒有已讀通知。':'目前沒有通知。')+'</div>';
  document.querySelectorAll('.markRead').forEach(b=>b.onclick=()=>markNotificationRead(b.dataset.notice));
}
async function loadMyNotifications(){
  const box=$('myNotifications'); if(!box||!visitorToken())return;
  const uid=(await getCurrentUser())?.id;if(!uid)return;
  const r=await fetch(SUPABASE_URL+'/rest/v1/notifications?select=*&user_id=eq.'+encodeURIComponent(uid)+'&order=created_at.desc',{headers:auth()});
  myNotificationRows=r.ok?await r.json():[]; renderMyNotifications(); loadNotificationBadge();
}
async function markNotificationRead(id){const r=await fetch(SUPABASE_URL+'/rest/v1/notifications?id=eq.'+encodeURIComponent(id),{method:'PATCH',headers:{...auth(),Prefer:'return=minimal'},body:JSON.stringify({read_at:new Date().toISOString()})});if(r.ok)await loadMyNotifications();}
async function markAllNotificationsRead(){
  const uid=(await getCurrentUser())?.id;if(!uid)return;
  const r=await fetch(SUPABASE_URL+'/rest/v1/notifications?user_id=eq.'+encodeURIComponent(uid)+'&read_at=is.null',{method:'PATCH',headers:{...auth(),Prefer:'return=minimal'},body:JSON.stringify({read_at:new Date().toISOString()})});
  if(r.ok){show('notificationMsg','✅ 已全部標記為已讀。');await loadMyNotifications();}else show('notificationMsg','❌ 操作失敗，請稍後再試。');
}
async function deleteReadNotifications(){
  const uid=(await getCurrentUser())?.id;if(!uid)return;
  const count=myNotificationRows.filter(x=>x.read_at).length;
  if(!count){show('notificationMsg','目前沒有已讀通知可刪除。');return;}
  if(!confirm('確定刪除全部 '+count+' 則已讀通知？刪除後無法復原。'))return;
  const r=await fetch(SUPABASE_URL+'/rest/v1/notifications?user_id=eq.'+encodeURIComponent(uid)+'&read_at=not.is.null',{method:'DELETE',headers:{...auth(),Prefer:'return=minimal'}});
  if(r.ok){show('notificationMsg','✅ 已刪除 '+count+' 則已讀通知。');await loadMyNotifications();}else show('notificationMsg','❌ 刪除失敗，請確認資料庫權限後再試。');
}


function searchTextScore(row, q, fields){
  const query=q.toLowerCase();
  let score=0;
  fields.forEach((key,i)=>{const v=String(row[key]??'').toLowerCase(); if(v.includes(query)) score += i===0?5:2;});
  return score;
}
function searchResultCard(item){
  const icon=item.type==='news'?'📢':item.type==='product'?'🛍️':'🏆';
  return '<article class="searchResult"><div class="date">'+icon+' '+esc(item.label)+'</div><h3><a href="'+esc(item.url)+'">'+esc(item.title)+'</a></h3>'+(item.meta?'<p class="searchMeta">'+esc(item.meta)+'</p>':'')+(item.text?'<p>'+esc(item.text).replace(/\n/g,'<br>')+'</p>':'')+'</article>';
}
async function runSiteSearch(){
  const input=$('siteSearchInput'), box=$('searchResults'), count=$('searchCount');
  if(!input||!box||!configured())return;
  const q=input.value.trim();
  if(!q){box.innerHTML='<div class="empty">請輸入關鍵字開始搜尋。</div>';if(count)count.textContent='';return}
  box.innerHTML='<div class="loading">正在搜尋全站內容…</div>'; if(count)count.textContent='';
  const h={apikey:SUPABASE_ANON_KEY,Authorization:'Bearer '+SUPABASE_ANON_KEY};
  const now=encodeURIComponent(new Date().toISOString());
  const urls={
    news:SUPABASE_URL+'/rest/v1/announcements?select=id,title,content,date,category,link_url,published_at&published=eq.true&published_at=lte.'+now+'&order=pinned.desc,published_at.desc,created_at.desc&limit=1000',
    products:SUPABASE_URL+'/rest/v1/products?select=id,name,description,category,price&active=eq.true&order=created_at.desc&limit=1000',
    competitions:SUPABASE_URL+'/rest/v1/competitions?select=id,name,description,category,event_date&published=eq.true&order=event_date.desc,created_at.desc&limit=1000'
  };
  try{
    const [nr,pr,cr]=await Promise.all(Object.values(urls).map(u=>fetch(u,{headers:h})));
    const [newsRows,productRows,competitionRows]=await Promise.all([nr.ok?nr.json():[],pr.ok?pr.json():[],cr.ok?cr.json():[]]);
    const results=[];
    newsRows.forEach(x=>{const score=searchTextScore(x,q,['title','content','category']);if(score)results.push({score,type:'news',label:x.category||'最新消息',title:x.title,text:x.content,meta:x.date||'',url:x.link_url||('news.html')});});
    productRows.forEach(x=>{const score=searchTextScore(x,q,['name','description','category']);if(score)results.push({score,type:'product',label:x.category||'商品',title:x.name,text:x.description,meta:x.price!=null?'NT$ '+Number(x.price).toLocaleString():'',url:'products.html'});});
    competitionRows.forEach(x=>{const score=searchTextScore(x,q,['name','description','category']);if(score)results.push({score,type:'competition',label:x.category||'活動／比賽',title:x.name,text:x.description,meta:x.event_date||'日期未設定',url:'competitions.html?id='+encodeURIComponent(x.id)});});
    results.sort((a,b)=>b.score-a.score||a.title.localeCompare(b.title,'zh-Hant'));
    if(count)count.textContent='找到 '+results.length+' 筆結果';
    box.innerHTML=results.length?results.map(searchResultCard).join(''):'<div class="empty">找不到「'+esc(q)+'」相關內容。<br><small>可以試試商品名稱、活動名稱、公告關鍵字或分類。</small></div>';
  }catch(e){console.error('全站搜尋失敗:',e);box.innerHTML='<div class="empty">目前無法完成搜尋，請稍後再試。</div>';}
}
function initSiteSearch(){
  const form=$('siteSearchForm'), input=$('siteSearchInput');
  if(!form||!input)return;
  const params=new URLSearchParams(location.search); if(params.get('q'))input.value=params.get('q');
  form.addEventListener('submit',e=>{e.preventDefault();const q=input.value.trim();if(q)history.replaceState(null,'','search.html?q='+encodeURIComponent(q));runSiteSearch();});
  if(input.value.trim())runSiteSearch();
}

function showMySection(id){document.querySelectorAll('.myPanel').forEach(x=>x.classList.add('hidden'));$(id)?.classList.remove('hidden');document.querySelectorAll('.mySubnav a').forEach(a=>a.classList.toggle('active',a.dataset.target===id));}

window.addEventListener('DOMContentLoaded',async()=>{bindMobileNav();initSiteSearch();if($('visitorLoginButton'))$('visitorLoginButton').onclick=visitorLogin;if($('visitorLogout'))$('visitorLogout').onclick=visitorLogout;const sessionOk=await ensureVisitorSession();if(sessionOk){$('visitorGate')?.classList.add('hidden');$('visitorLogout')?.classList.remove('hidden')}else if($('visitorGate'))$('visitorGate').classList.remove('hidden');if($('sendTicket'))$('sendTicket').onclick=sendTicket;if(sessionOk)loadSite();else if(!$('visitorGate'))loadSite();if($('myCoupons')&&sessionOk)loadMyCoupons();loadQuickLinks();loadCompetitionMenu();loadNotificationBadge();if($('competitionList'))loadCompetitionPage();if($('myProfile')&&sessionOk){loadMyProfile();loadMyCompetitions();loadMyAwards();loadMyNotifications();$('saveMyProfile')?.addEventListener('click',saveMyProfile);$('changeMyPassword')?.addEventListener('click',changeMyPassword);$('markAllNotifications')?.addEventListener('click',markAllNotificationsRead);$('deleteReadNotifications')?.addEventListener('click',deleteReadNotifications);showMySection(location.hash?location.hash.slice(1):'myProfilePanel');document.querySelectorAll('.mySubnav a').forEach(a=>a.addEventListener('click',e=>{e.preventDefault();const target=a.dataset.target;history.replaceState(null,'','#'+target);showMySection(target);}));} });
window.addEventListener('hashchange',()=>{const id=location.hash.slice(1);if(id&&$(id))showMySection(id);});
