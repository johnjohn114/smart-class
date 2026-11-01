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
 try{const saved=JSON.parse(localStorage.getItem('push_registration_status')||'null');if(saved?.message)push.textContent=saved.message}catch(_){}
 window.onNativePushToken=function(token){if(!token){push.textContent='尚未取得推播識別碼，請稍後重試。';return}push.textContent='已取得推播識別碼，正在登記裝置…';try{const r=fetch(SUPABASE_URL+'/rest/v1/device_push_tokens?on_conflict=token',{method:'POST',headers:{apikey:SUPABASE_ANON_KEY,Authorization:'Bearer '+(localStorage.getItem('visitor_access_token')||SUPABASE_ANON_KEY),'Content-Type':'application/json',Prefer:'resolution=merge-duplicates,return=minimal'},body:JSON.stringify({token,platform:'android',updated_at:new Date().toISOString()})});r.then(x=>{push.textContent=x.ok?'✅ 推播裝置註冊成功。':'❌ 推播裝置註冊失敗（HTTP '+x.status+'）。'}).catch(()=>{push.textContent='❌ 無法連線，請稍後重試。'})}catch(_){push.textContent='❌ 推播裝置註冊失敗。'}};
 window.onNativePushTokenError=message=>{push.textContent=message||'無法取得推播識別碼。'};
 document.getElementById('retryPushRegistration')?.addEventListener('click',()=>{if(window.AndroidApp&&typeof AndroidApp.requestPushToken==='function'){push.textContent='正在向 Android 取得推播識別碼…';AndroidApp.requestPushToken()}else push.textContent='目前不是 Android App 環境。'});
})();