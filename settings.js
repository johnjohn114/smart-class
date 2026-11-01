(()=> {
 const K='announcement_zone_theme';
 const radios=[...document.querySelectorAll('input[name="theme"]')];
 const current=localStorage.getItem(K)||'system';
 function apply(m){const dark=m==='dark'||(m==='system'&&matchMedia('(prefers-color-scheme: dark)').matches);document.documentElement.dataset.theme=dark?'dark':'light'}
 radios.forEach(r=>{r.checked=r.value===current;r.addEventListener('change',()=>{if(!r.checked)return;localStorage.setItem(K,r.value);apply(r.value);document.getElementById('status').textContent='已儲存設定。'})});
 apply(current);
 matchMedia('(prefers-color-scheme: dark)').addEventListener?.('change',()=>{if((localStorage.getItem(K)||'system')==='system')apply('system')});
 const menuToggle=document.querySelector('.mobileNavToggle');
 menuToggle?.addEventListener('click',()=>{const nav=menuToggle.nextElementSibling;if(!nav)return;const open=nav.classList.toggle('mobileOpen');menuToggle.setAttribute('aria-expanded',String(open));menuToggle.textContent=open?'✕ 關閉選單':'☰ 選單'});
 document.querySelectorAll('.navDropdown>button').forEach(btn=>btn.addEventListener('click',e=>{e.preventDefault();const parent=btn.closest('.navDropdown');const open=parent.classList.toggle('open');btn.setAttribute('aria-expanded',String(open));document.querySelectorAll('.navDropdown.open').forEach(other=>{if(other!==parent){other.classList.remove('open');other.querySelector(':scope>button')?.setAttribute('aria-expanded','false')}})}));
 document.addEventListener('click',e=>{if(!e.target.closest('.navDropdown'))document.querySelectorAll('.navDropdown.open').forEach(d=>{d.classList.remove('open');d.querySelector(':scope>button')?.setAttribute('aria-expanded','false')})});
 const version=document.getElementById('installedVersion');
 if(window.AndroidApp&&typeof AndroidApp.getVersionName==='function'){try{version.textContent=AndroidApp.getVersionName()}catch(_){version.textContent='無法讀取'}}else version.textContent='網站版';
 const push=document.getElementById('pushStatus');
 const environment=document.getElementById('pushEnvironment');
 const permission=document.getElementById('pushPermission');
 const tokenStatus=document.getElementById('pushTokenStatus');
 const registration=document.getElementById('pushRegistrationStatus');
 const isAndroid=!!(window.AndroidApp&&typeof AndroidApp.requestPushToken==='function');
 environment.textContent=isAndroid?'Android App':'網站／非 Android 環境';
 function saveState(message,registered){
   push.textContent=message;
   try{localStorage.setItem('push_registration_status',JSON.stringify({message,registered,checkedAt:new Date().toISOString()}))}catch(_){}
 }
 function refreshPermission(){
   if(!isAndroid){permission.textContent='無法從網站讀取 Android 權限';return}
   try{
     const state=AndroidApp.getPushPermissionStatus();
     permission.textContent=state==='permission_granted'?'✅ 已允許':state==='permission_required'?'⚠️ 尚未允許':'❌ 系統通知已關閉';
   }catch(_){permission.textContent='無法讀取權限狀態'}
 }
 try{
   const saved=JSON.parse(localStorage.getItem('push_registration_status')||'null');
   if(saved){push.textContent=saved.message||'尚未執行推播診斷';registration.textContent=saved.registered?'✅ 已登記':saved.registered===false?'❌ 未登記':'尚未確認'}
 }catch(_){}
 refreshPermission();
 window.onNativePushToken=function(token){
   refreshPermission();
   if(!token){tokenStatus.textContent='❌ 未取得';registration.textContent='未完成';saveState('❌ 尚未取得 Firebase 推播識別碼，請稍後重試。',false);return}
   tokenStatus.textContent='✅ 已取得（識別碼不予顯示）';
   registration.textContent='登記中…';
   if(typeof SUPABASE_URL==='undefined'||typeof SUPABASE_ANON_KEY==='undefined'){
     registration.textContent='❌ Supabase 設定缺失';saveState('❌ 無法登記：Supabase 設定尚未載入。',false);return;
   }
   fetch(SUPABASE_URL+'/rest/v1/device_push_tokens?on_conflict=token',{
     method:'POST',
     headers:{apikey:SUPABASE_ANON_KEY,Authorization:'Bearer '+(localStorage.getItem('visitor_access_token')||SUPABASE_ANON_KEY),'Content-Type':'application/json',Prefer:'resolution=merge-duplicates,return=minimal'},
     body:JSON.stringify({token:token,platform:'android',updated_at:new Date().toISOString()})
   }).then(response=>{
     if(response.ok){registration.textContent='✅ 已成功登記';saveState('✅ 推播診斷完成：已取得識別碼，且裝置已成功登記。',true)}
     else{registration.textContent='❌ 登記失敗（HTTP '+response.status+'）';saveState('❌ 已取得識別碼，但 Supabase 登記失敗（HTTP '+response.status+'）。',false)}
   }).catch(()=>{registration.textContent='❌ 網路連線失敗';saveState('❌ 已取得識別碼，但無法連線至 Supabase 完成登記。',false)});
 };
 window.onNativePushTokenError=function(message){
   refreshPermission();tokenStatus.textContent='❌ 未取得';registration.textContent='未完成';
   saveState(message||'❌ 無法取得 Firebase 推播識別碼。',false);
 };
 document.getElementById('retryPushRegistration')?.addEventListener('click',()=>{
   if(!isAndroid){saveState('目前不是 Android App 環境，無法檢查原生推播註冊。',null);return}
   refreshPermission();tokenStatus.textContent='檢查中…';registration.textContent='等待 Firebase 回應…';
   saveState('正在重新檢查推播權限並向 Firebase 取得識別碼…',null);
   try{AndroidApp.requestPushToken()}catch(_){saveState('❌ 無法呼叫 Android 推播服務。',false)}
 });
})();