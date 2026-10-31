(function(){
'use strict';
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
async function loadReleases(){
 if(typeof SUPABASE_URL==='undefined'||typeof SUPABASE_ANON_KEY==='undefined')return [];
 const r=await fetch(SUPABASE_URL+'/rest/v1/app_releases?select=id,version_code,version_name,release_notes,apk_url,published,published_at,created_at&published=eq.true&order=version_code.desc',{headers:{apikey:SUPABASE_ANON_KEY,Authorization:'Bearer '+SUPABASE_ANON_KEY}});
 if(!r.ok)throw new Error('無法讀取更新紀錄（HTTP '+r.status+'）。');
 return await r.json();
}
function render(rows){
 const list=document.getElementById('appReleaseList');if(!list)return;
 list.innerHTML=rows.length?rows.map(x=>'<article class="notice"><div class="date">📅 '+esc((x.published_at||x.created_at||'').slice(0,10))+'</div><h3>版本 '+esc(x.version_name)+'</h3><p>'+esc(x.release_notes||'').replace(/\n/g,'<br>')+'</p><a class="btn secondary" href="'+esc(x.apk_url)+'" target="_blank" rel="noopener noreferrer">⬇️ 下載此版本 APK</a></article>').join(''):'<div class="empty">目前還沒有已發布的 App 更新。</div>';
 const latest=rows[0];const v=document.getElementById('appCurrentVersion');if(v&&window.AndroidApp&&AndroidApp.getVersionName)v.textContent='目前安裝版本：'+AndroidApp.getVersionName();
 const latestEl=document.getElementById('appLatestVersion');if(latestEl)latestEl.textContent=latest?'最新版本：'+latest.version_name:'尚無已發布版本';
}
async function init(){const list=document.getElementById('appReleaseList');if(!list)return;try{render(await loadReleases())}catch(e){list.innerHTML='<div class="empty">'+esc(e.message)+'</div>'}}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
window.AppReleaseCenter={loadReleases};
})();