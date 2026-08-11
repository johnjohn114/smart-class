const F = [
"site_name","hero_title","hero_text","hero_image",
"about_title","about_subtitle","about1_title","about1_text",
"about2_title","about2_text","features_title","features_subtitle",
"f1_title","f1_text","f2_title","f2_text","f3_title","f3_text",
"f4_title","f4_text","contact1","contact2","contact3"
];

const $ = (id) => document.getElementById(id);

function configReady() {
return typeof SUPABASE_URL !== "undefined" &&
typeof SUPABASE_ANON_KEY !== "undefined" &&
SUPABASE_URL &&
SUPABASE_ANON_KEY &&
!String(SUPABASE_URL).includes("你的") &&
!String(SUPABASE_ANON_KEY).includes("你的");
}

function authHeaders() {
const token = localStorage.getItem("access_token");

return {
"Content-Type": "application/json",
"apikey": SUPABASE_ANON_KEY,
"Authorization": "Bearer " + (token || SUPABASE_ANON_KEY)
};
}

function showLoginError(msg) {
const el = $("loginError");
if (el) el.textContent = msg;
}

/* =========================
管理員登入
========================= */

async function login() {
const emailEl = $("email");
const passwordEl = $("password");

if (!configReady()) {
showLoginError("尚未設定 Supabase。請把你原本的 config.js 放回來。");
return;
}

const email = emailEl.value.trim();
const password = passwordEl.value;

if (!email || !password) {
showLoginError("請輸入管理員 Email 與密碼。");
return;
}

showLoginError("登入中…");

try {
const r = await fetch(
SUPABASE_URL + "/auth/v1/token?grant_type=password",
{
method: "POST",
headers: {
"Content-Type": "application/json",
"apikey": SUPABASE_ANON_KEY
},
body: JSON.stringify({ email, password })
}
);

```
let d = {};
try {
  d = await r.json();
} catch (_) {}

if (!r.ok) {
  const msg = d.error_description || d.msg || d.message || "";

  if (r.status === 400) {
    showLoginError(
      "登入失敗：Email 或密碼錯誤，或此帳號尚未完成驗證。"
    );
  } else if (r.status === 401) {
    showLoginError(
      "登入失敗：Supabase 驗證被拒絕，請確認帳號與密碼。"
    );
  } else {
    showLoginError(
      "登入失敗：" + (msg || ("HTTP " + r.status))
    );
  }

  return;
}

if (!d.access_token) {
  showLoginError("登入失敗：沒有取得登入 Token。");
  return;
}

localStorage.setItem("access_token", d.access_token);

if (d.refresh_token) {
  localStorage.setItem("refresh_token", d.refresh_token);
}

$("login").classList.add("hidden");
$("dashboard").classList.remove("hidden");

showLoginError("");

await load();
```

} catch (e) {
console.error(e);

```
showLoginError(
  "無法連線到 Supabase。請確認網址、Key 與網路連線。"
);
```

}
}

/* =========================
載入
========================= */

async function load() {
await content();
await news();
}

/* =========================
網站內容
========================= */

async function content() {
if (!configReady() || !localStorage.getItem("access_token")) {
return;
}

try {
const r = await fetch(
SUPABASE_URL + "/rest/v1/site_settings?select=*&id=eq.1",
{
headers: authHeaders()
}
);

```
if (r.status === 401) {
  showLoginError("登入狀態已失效，請重新登入。");
  logout();
  return;
}

if (!r.ok) return;

const a = await r.json();

if (a[0]) {
  F.forEach(k => {
    const el = $(k);

    if (el) {
      el.value = a[0][k] ?? "";
    }
  });
}
```

} catch (e) {
console.error(e);
}
}

async function save() {
if (!configReady()) return;

const body = {};

F.forEach(k => {
const el = $(k);
body[k] = el ? el.value : "";
});

try {
const r = await fetch(
SUPABASE_URL + "/rest/v1/site_settings?id=eq.1",
{
method: "PATCH",
headers: {
...authHeaders(),
"Prefer": "return=minimal"
},
body: JSON.stringify(body)
}
);

```
$("contentMsg").textContent = r.ok
  ? "✅ 已儲存"
  : "❌ 儲存失敗（請檢查 Supabase 權限）";
```

} catch (e) {
console.error(e);
$("contentMsg").textContent = "❌ 無法連線";
}
}

/* =========================
公告
========================= */

async function publish() {
const titleEl = $("title");
const contentEl = $("content");
const dateEl = $("date");

if (!titleEl || !contentEl || !dateEl) return;

if (!titleEl.value.trim() || !contentEl.value.trim()) {
$("publishMsg").textContent = "請填寫標題與內容";
return;
}

try {
const r = await fetch(
SUPABASE_URL + "/rest/v1/announcements",
{
method: "POST",
headers: {
...authHeaders(),
"Prefer": "return=minimal"
},
body: JSON.stringify({
title: titleEl.value.trim(),
content: contentEl.value,
date: dateEl.value ||
new Date().toISOString().slice(0, 10),
published: true
})
}
);

```
$("publishMsg").textContent = r.ok
  ? "✅ 已發布"
  : "❌ 發布失敗（請檢查 announcements 權限）";

if (r.ok) {
  titleEl.value = "";
  dateEl.value = "";
  contentEl.value = "";
  await news();
}
```

} catch (e) {
console.error(e);
$("publishMsg").textContent = "❌ 無法連線";
}
}

async function news() {
if (!configReady() || !localStorage.getItem("access_token")) {
return;
}

try {
const r = await fetch(
SUPABASE_URL +
"/rest/v1/announcements?select=*&order=created_at.desc",
{
headers: authHeaders()
}
);

```
if (r.status === 401) {
  logout();
  return;
}

if (!r.ok) return;

const a = await r.json();

$("adminList").innerHTML =
  a.map(x =>
    '<article class="notice">' +
      '<div class="date">' + esc(x.date) + '</div>' +
      '<h3>' + esc(x.title) + '</h3>' +
      '<p>' +
        esc(x.content).replace(/\n/g, "<br>") +
      '</p>' +
      '<button type="button" class="deleteNotice" data-id="' +
        esc(x.id) +
      '">刪除</button>' +
    '</article>'
  ).join("") ||
  '<div class="empty">目前沒有公告。</div>';

document.querySelectorAll(".deleteNotice").forEach(button => {
  button.addEventListener("click", function () {
    del(this.dataset.id);
  });
});
```

} catch (e) {
console.error(e);
}
}

async function del(id) {
if (!confirm("確定刪除這則公告？")) return;

try {
const r = await fetch(
SUPABASE_URL +
"/rest/v1/announcements?id=eq." +
encodeURIComponent(id),
{
method: "DELETE",
headers: authHeaders()
}
);

```
if (!r.ok) {
  alert("刪除失敗，請檢查 Supabase 權限。");
  return;
}

await news();
```

} catch (e) {
console.error(e);
}
}

/* =========================
訪客帳號管理
========================= */

function visitorFunctionUrl() {
return SUPABASE_URL + "/functions/v1/manage-visitors";
}

async function visitorRequest(data) {
const token = localStorage.getItem("access_token");

if (!token) {
throw new Error("管理員登入狀態已失效，請重新登入。");
}

const r = await fetch(
visitorFunctionUrl(),
{
method: "POST",
headers: {
"Content-Type": "application/json",
"apikey": SUPABASE_ANON_KEY,
"Authorization": "Bearer " + token
},
body: JSON.stringify(data)
}
);

let result = {};

try {
result = await r.json();
} catch (_) {}

if (!r.ok) {
throw new Error(
result.error ||
result.message ||
("HTTP " + r.status)
);
}

return result;
}

/* 取得訪客 */

async function loadVisitors() {
const list = $("visitorList");

if (!list) return;

list.innerHTML =
'<div class="loading">正在載入訪客…</div>';

try {
const result = await visitorRequest({
action: "list"
});

```
const visitors = result.visitors || [];

if (!visitors.length) {
  list.innerHTML =
    '<div class="empty">目前沒有訪客帳號。</div>';
  return;
}

list.innerHTML = visitors.map(v => {

  const created = v.created_at
    ? new Date(v.created_at).toLocaleString("zh-TW")
    : "";

  return (
    '<article class="notice">' +
      '<div class="date">' +
        esc(created) +
      '</div>' +

      '<h3>👤 ' +
        esc(v.username) +
      '</h3>' +

      '<p>' +
        (v.active
          ? "目前可以登入網站"
          : "目前已停用") +
      '</p>' +

      '<button type="button" ' +
        'class="deleteVisitor" ' +
        'data-id="' + esc(v.id) + '">' +
        '刪除帳號' +
      '</button>' +

    '</article>'
  );

}).join("");

document.querySelectorAll(".deleteVisitor").forEach(button => {
  button.addEventListener("click", function () {
    deleteVisitor(this.dataset.id);
  });
});
```

} catch (e) {
console.error(e);

```
list.innerHTML =
  '<div class="empty">載入訪客失敗：' +
  esc(e.message) +
  '</div>';
```

}
}

/* 建立訪客 */

async function createVisitor() {
const usernameEl = $("visitorUsername");
const passwordEl = $("visitorPassword");
const msg = $("visitorMsg");

if (!usernameEl || !passwordEl || !msg) return;

const username = usernameEl.value.trim();
const password = passwordEl.value;

if (!username || !password) {
msg.textContent = "❌ 請輸入帳號與密碼";
return;
}

msg.textContent = "正在建立訪客帳號…";

try {
await visitorRequest({
action: "create",
username: username,
password: password
});

```
msg.textContent = "✅ 訪客帳號建立成功";

usernameEl.value = "";
passwordEl.value = "";

await loadVisitors();
```

} catch (e) {
console.error(e);

```
msg.textContent = "❌ " + e.message;
```

}
}

/* 刪除訪客 */

async function deleteVisitor(id) {
if (!id) return;

if (!confirm(
"確定要刪除這個訪客帳號嗎？\n\n刪除後將無法使用這個帳號登入網站。"
)) {
return;
}

const msg = $("visitorMsg");

if (msg) {
msg.textContent = "正在刪除訪客帳號…";
}

try {
await visitorRequest({
action: "delete",
id: id
});

```
if (msg) {
  msg.textContent = "✅ 訪客帳號已刪除";
}

await loadVisitors();
```

} catch (e) {
console.error(e);

```
if (msg) {
  msg.textContent = "❌ " + e.message;
}
```

}
}

/* =========================
分頁
========================= */

function tab(id, b) {
document
.querySelectorAll(".tabPanel")
.forEach(x => x.classList.add("hidden"));

const panel = $(id);

if (panel) {
panel.classList.remove("hidden");
}

document
.querySelectorAll(".tab")
.forEach(x => x.classList.remove("active"));

if (b) {
b.classList.add("active");
}

if (id === "newsTab") {
news();
} else if (id === "visitorTab") {
loadVisitors();
} else {
content();
}
}

/* =========================
登出
========================= */

function logout() {
localStorage.removeItem("access_token");
localStorage.removeItem("refresh_token");
location.reload();
}

/* =========================
HTML 安全處理
========================= */

function esc(s) {
return String(s ?? "").replace(/[&<>"']/g, m => ({
"&": "&",
"<": "<",
">": ">",
'"': """,
"'": "'"
}[m]));
}

/* =========================
啟動
========================= */

document.addEventListener("DOMContentLoaded", () => {

if (!configReady()) {
showLoginError(
"設定檔尚未完成：請將原本可用的 config.js 放回此資料夾。"
);
return;
}

if (localStorage.getItem("access_token")) {
$("login").classList.add("hidden");
$("dashboard").classList.remove("hidden");
load();
}

});
