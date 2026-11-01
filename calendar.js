(function(){
'use strict';
const $=id=>document.getElementById(id);
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let events=[],view=new Date(),selected=iso(new Date());
function iso(d){return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0')}
function configured(){return typeof SUPABASE_URL!=='undefined'&&typeof SUPABASE_ANON_KEY!=='undefined'&&SUPABASE_URL&&SUPABASE_ANON_KEY}
async function load(){
 if(!configured()){$('calendarEvents').innerHTML='<div class="empty">尚未設定資料庫。</div>';return}
 try{
  const url=SUPABASE_URL+'/rest/v1/announcements?select=id,title,content,event_date,event_end_date,category,published_at&published=eq.true&event_date=not.is.null&event_date_confirmed=eq.true&order=event_date.asc';
  const r=await fetch(url,{headers:{apikey:SUPABASE_ANON_KEY,Authorization:'Bearer '+SUPABASE_ANON_KEY}});
  if(!r.ok)throw new Error('HTTP '+r.status);
  events=await r.json();render();
 }catch(e){$('calendarEvents').innerHTML='<div class="empty">行事曆載入失敗，請稍後再試。</div>';console.warn(e)}
}
function inRange(e,d){return e.event_date<=d&&(!e.event_end_date||e.event_end_date>=d)}
function render(){
 const first=new Date(view.getFullYear(),view.getMonth(),1),start=new Date(first);start.setDate(1-first.getDay());
 $('calendarMonth').textContent=view.getFullYear()+' 年 '+(view.getMonth()+1)+' 月';
 const names=['日','一','二','三','四','五','六'];
 let html=names.map(x=>'<div class="calendarWeekday">週'+x+'</div>').join('');
 const today=iso(new Date());
 for(let i=0;i<42;i++){const d=new Date(start);d.setDate(start.getDate()+i);const key=iso(d),matches=events.filter(e=>inRange(e,key));
 html+='<button type="button" class="calendarDay'+(d.getMonth()!==view.getMonth()?' muted':'')+(key===today?' today':'')+(key===selected?' selected':'')+'" data-date="'+key+'"><b>'+d.getDate()+'</b>'+(matches.length?'<span class="calendarDots">'+matches.slice(0,5).map(()=>'<i class="calendarDot"></i>').join('')+'</span>':'')+'</button>'}
 $('calendarGrid').innerHTML=html;
 $('calendarGrid').querySelectorAll('[data-date]').forEach(b=>b.addEventListener('click',()=>{selected=b.dataset.date;render();renderAgenda()}));
 renderAgenda();
}
function renderAgenda(){
 const rows=events.filter(e=>inRange(e,selected));
 $('calendarSelectedTitle').textContent=selected+' 的事項';
 $('calendarEvents').innerHTML=rows.length?rows.map(e=>'<article class="calendarEvent"><small>'+esc(e.category||'公告')+(e.event_end_date&&e.event_end_date!==e.event_date?' · 至 '+esc(e.event_end_date):'')+'</small><h3>'+esc(e.title)+'</h3><p>'+esc(String(e.content||'').slice(0,180))+'</p><a href="news.html#announcement-'+encodeURIComponent(e.id)+'">查看完整公告 →</a></article>').join(''):'<div class="empty">這一天沒有已確認的公告事項。</div>';
}
$('calendarPrev').onclick=()=>{view=new Date(view.getFullYear(),view.getMonth()-1,1);render()};
$('calendarNext').onclick=()=>{view=new Date(view.getFullYear(),view.getMonth()+1,1);render()};
$('calendarToday').onclick=()=>{view=new Date();selected=iso(view);render()};
load();
})();