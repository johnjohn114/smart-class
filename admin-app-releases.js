(function(){
'use strict';
const $=id=>document.getElementById(id);
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function headers(){return {apikey:SUPABASE_ANON_KEY,Authorization:'Bearer '+(localStorage.getItem('access_token')||''),'Content-Type':'application/json',Prefer:'return=representation'}}
function msg(t){$('appReleaseMsg').textContent=t}
async function load(){
 const r=await fetch(SUPABASE_URL+'/rest/v1/app_releases?select=*&order=version_code.desc',{headers:headers()});
 if(!r.ok){msg('讀取失敗，請確認已執行 Supabase 更新資料表 SQL。');return}
 const rows=await r.json();
 $('appReleaseAdminList').innerHTML=rows.length?rows.map(x=>'<article class="notice"><div class="date">'+(x.published?'🟢 已發布':'📝 草稿')+' · '+esc(x.published_at||x.created_at||'')+'</div><h3>'+esc(x.version_name)+'（versionCode '+x.version_code+'）</h3><p>'+esc(x.release_notes)+'</p><p><a href="'+esc(x.apk_url)+'" target="_blank" rel="noopener">APK 連結</a></p><div class="competitionActions"><button type="button" data-toggle="'+x.id+'" data-published="'+x.published+'">'+(x.published?'取消發布':'發布')+'</button> <button type="button" data-edit="'+x.id+'">編輯</button> <button type="button" data-delete="'+x.id+'">刪除</button></div></article>').join(''):'<div class="empty">尚無版本紀錄。</div>';
 rows.forEach(x=>{});
 $('appReleaseAdminList').querySelectorAll('[data-toggle]').forEach(b=>b.onclick=()=>toggle(b.dataset.toggle,b.dataset.published==='true'));
 $('appReleaseAdminList').querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>edit(b.dataset.edit,rows));
 $('appReleaseAdminList').querySelectorAll('[data-delete]').forEach(b=>b.onclick=()=>removeRelease(b.dataset.delete));
}
function clear(){ $('releaseId').value='';$('releaseVersionCode').value='';$('releaseVersionName').value='';$('releaseNotes').value='';$('releaseApkUrl').value='';$('releasePublished').checked=false; }
function edit(id,rows){const x=rows.find(a=>a.id===id);if(!x)return;$('releaseId').value=x.id;$('releaseVersionCode').value=x.version_code;$('releaseVersionName').value=x.version_name;$('releaseNotes').value=x.release_notes||'';$('releaseApkUrl').value=x.apk_url;$('releasePublished').checked=x.published;window.scrollTo({top:0,behavior:'smooth'});}
async function save(){
 const id=$('releaseId').value,code=Number($('releaseVersionCode').value),name=$('releaseVersionName').value.trim(),notes=$('releaseNotes').value.trim(),url=$('releaseApkUrl').value.trim(),published=$('releasePublished').checked;
 if(!Number.isInteger(code)||code<1||!name||!url){msg('請填寫有效的 versionCode、版本號及 APK 下載網址。');return}
 try{const u=new URL(url);if(u.protocol!=='https:')throw new Error()}catch(e){msg('APK 下載網址必須是有效的 HTTPS 網址。');return}
 const body={version_code:code,version_name:name,release_notes:notes,apk_url:url,published,published_at:published?new Date().toISOString():null,created_by:localStorage.getItem('admin_user_id')||null};
 const r=await fetch(SUPABASE_URL+'/rest/v1/app_releases'+(id?'?id=eq.'+encodeURIComponent(id):''),{method:id?'PATCH':'POST',headers:headers(),body:JSON.stringify(body)});
 if(!r.ok){const d=await r.json().catch(()=>({}));msg('儲存失敗：'+(d.message||d.details||'請確認管理員權限、SQL 與 versionCode 是否重複。'));return}
 msg('✅ 已儲存版本資訊。');clear();await load();
}
async function toggle(id,published){const r=await fetch(SUPABASE_URL+'/rest/v1/app_releases?id=eq.'+encodeURIComponent(id),{method:'PATCH',headers:headers(),body:JSON.stringify({published:!published,published_at:!published?new Date().toISOString():null})});if(!r.ok){msg('發布狀態更新失敗。');return}await load()}
async function removeRelease(id){if(!confirm('確定刪除此版本紀錄？'))return;const r=await fetch(SUPABASE_URL+'/rest/v1/app_releases?id=eq.'+encodeURIComponent(id),{method:'DELETE',headers:headers()});if(!r.ok){msg('刪除失敗，請確認管理員權限。');return}await load()}
function init(){if(!$('appReleaseAdminList'))return;$('saveAppRelease').onclick=save;$('clearAppRelease').onclick=clear;$('refreshAppReleases').onclick=load;load()}
document.addEventListener('DOMContentLoaded',init);
})();