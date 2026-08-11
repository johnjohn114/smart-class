const F = [
"site_name",
"hero_title",
"hero_text",
"hero_image",
"about_title",
"about_subtitle",
"about1_title",
"about1_text",
"about2_title",
"about2_text",
"features_title",
"features_subtitle",
"f1_title",
"f1_text",
"f2_title",
"f2_text",
"f3_title",
"f3_text",
"f4_title",
"f4_text",
"contact1",
"contact2",
"contact3"
];

const $ = (id) => document.getElementById(id);

function configReady() {
return (
typeof SUPABASE_URL !== "undefined" &&
typeof SUPABASE_ANON_KEY !== "undefined" &&
SUPABASE_URL &&
SUPABASE_ANON_KEY &&
!String(SUPABASE_URL).includes("你的") &&
!String(SUPABASE_ANON_KEY).includes("你的")
);
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

// =========================
// 登入
// =========================

async function login() {
const emailEl = $("email");
const passwordEl = $("password");

if (!emailEl || !passwordEl) {
console.error("找不到 email 或 password");
return;
}

if (!configReady()) {
showLoginError("Supabase 設定沒有正確載入，請檢查 config.js。");
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
body: JSON.stringify({
email: email,
password: password
})
}
);

let d = {};

try {
  d = await r.json();
} catch (_) {
  d = {};
}

console.log("Supabase 登入回應：", r.status, d);

if (!r.ok) {
  const msg =
    d.error_description ||
    d.msg ||
    d.message ||
    d.error ||
    "";

  showLoginError(
    "登入失敗：" + (msg || ("HTTP " + r.status))
  );

  return;
}

if (!d.access_token) {
  showLoginError("登入失敗：沒有取得 access_token。");
  console.error("Supabase 回應沒有 access_token：", d);
  return;
}

localStorage.setItem("access_token", d.access_token);

if (d.refresh_token) {
  localStorage.setItem("refresh_token", d.refresh_token);
}

const loginBox = $("loginBox");
const dashboard = $("dashboard");

if (loginBox) loginBox.classList.add("hidden");
if (dashboard) dashboard.classList.remove("hidden");

showLoginError("");

await load();

} catch (e) {
console.error("登入錯誤：", e);
showLoginError("無法連線到 Supabase，請檢查網址、Key 與網路。");
}
}

// =========================
// 載入
// =========================

async function load() {
await content();
await news();
}

// =========================
// 網站內容
// =========================

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

if (r.status === 401) {
  showLoginError("登入狀態已失效，請重新登入。");
  logout();
  return;
}

if (!r.ok) {
  console.error("載入網站內容失敗：", r.status);
  return;
}

const a = await r.json();

if (a[0]) {
  F.forEach((k) => {
    const el = $(k);
    if (el) el.value = a[0][k] ?? "";
  });
}

} catch (e) {
console.error("content() 錯誤：", e);
}
}

// =========================
// 儲存
// =========================

async function save() {
if (!configReady()) return;

if (!localStorage.getItem("access_token")) {
const msg = $("contentMsg");
if (msg) msg.textContent = "❌ 請先登入";
return;
}

const body = {};

F.forEach((k) => {
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

const msg = $("contentMsg");

if (r.ok) {
  if (msg) msg.textContent = "✅ 已儲存";
} else {
  let errorText = "";

  try {
    const d = await r.json();
    errorText =
      d.message ||
      d.error ||
      d.hint ||
      "";
  } catch (_) {}

  if (msg) {
    msg.textContent =
      "❌ 儲存失敗：" +
      (errorText || ("HTTP " + r.status));
  }

  if (r.status === 401) {
    logout();
  }
}

} catch (e) {
console.error("save() 錯誤：", e);

const msg = $("contentMsg");
if (msg) msg.textContent = "❌ 無法連線";

}
}

// =========================
// 發布公告
// =========================

async function publish() {
const titleEl = $("title");
const contentEl = $("content");
const dateEl = $("date");
const msg = $("publishMsg");

if (!titleEl || !contentEl || !dateEl) {
console.error("找不到公告表單元素");
return;
}

if (!titleEl.value.trim() || !contentEl.value.trim()) {
if (msg) msg.textContent = "請填寫標題與內容";
return;
}

if (!configReady()) {
if (msg) msg.textContent = "❌ Supabase 設定錯誤";
return;
}

if (!localStorage.getItem("access_token")) {
if (msg) msg.textContent = "❌ 請先登入";
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

if (r.ok) {
  if (msg) msg.textContent = "✅ 已發布";

  titleEl.value = "";
  contentEl.value = "";
  dateEl.value = "";

  await news();

} else {
  let errorText = "";

  try {
    const d = await r.json();
    errorText =
      d.message ||
      d.error ||
      d.hint ||
      "";
  } catch (_) {}

  if (r.status === 401) {
    if (msg) msg.textContent = "❌ 登入已失效，請重新登入";
    logout();
    return;
  }

  if (msg) {
    msg.textContent =
      "❌ 發布失敗：" +
      (errorText || ("HTTP " + r.status));
  }

  console.error("發布公告失敗：", r.status, errorText);
}

} catch (e) {
console.error("publish() 錯誤：", e);
if (msg) msg.textContent = "❌ 無法連線到 Supabase";
}
}

// =========================
// 公告列表
// =========================

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

if (r.status === 401) {
  logout();
  return;
}

if (!r.ok) {
  console.error("載入公告失敗：", r.status);
  return;
}

const a = await r.json();
const list = $("adminList");

if (!list) {
  console.error("找不到 adminList");
  return;
}

list.innerHTML =
  a.map((x) => {
    return (
      '<article class="notice">' +
      '<div class="date">' + esc(x.date) + "</div>" +
      "<h3>" + esc(x.title) + "</h3>" +
      "<p>" +
      esc(x.content).replace(/\n/g, "<br>") +
      "</p>" +
      '<button type="button" onclick="window.deleteAnnouncement(' +
      JSON.stringify(String(x.id)) +
      ')">刪除</button>' +
      "</article>"
    );
  }).join("") ||
  '<div class="empty">目前沒有公告。</div>';

} catch (e) {
console.error("news() 錯誤：", e);
}
}

// =========================
// 刪除公告
// =========================

async function deleteAnnouncement(id) {
if (!id) {
alert("找不到公告 ID。");
return;
}

if (!confirm("確定刪除這則公告？")) {
return;
}

try {
const r = await fetch(
SUPABASE_URL +
"/rest/v1/announcements?id=eq." +
encodeURIComponent(id),
{
method: "DELETE",
headers: {
...authHeaders(),
"Prefer": "return=minimal"
}
}
);

if (r.status === 401) {
  alert("登入狀態已失效，請重新登入。");
  logout();
  return;
}

if (!r.ok) {
  let errorText = "";

  try {
    const d = await r.json();
    errorText =
      d.message ||
      d.error ||
      d.hint ||
      "";
  } catch (_) {}

  alert(
    "刪除失敗：" +
    (errorText || ("HTTP " + r.status))
  );

  return;
}

await news();

} catch (e) {
console.error("deleteAnnouncement() 錯誤：", e);
alert("無法連線，公告沒有刪除。");
}
}

// =========================
// 分頁
// =========================

function tab(id, b) {
document
.querySelectorAll(".tabPanel")
.forEach((x) => x.classList.add("hidden"));

const panel = $(id);

if (panel) {
panel.classList.remove("hidden");
}

document
.querySelectorAll(".tab")
.forEach((x) => x.classList.remove("active"));

if (b) {
b.classList.add("active");
}

if (id === "newsTab") {
news();
} else {
content();
}
}

// =========================
// 登出
// =========================

function logout() {
localStorage.removeItem("access_token");
localStorage.removeItem("refresh_token");
location.reload();
}

// =========================
// HTML 安全轉義
// =========================

function esc(s) {
return String(s ?? "").replace(
/[&<>"']/g,
(m) => ({
"&": "&",
"<": "<",
">": ">",
'"': """,
"'": "'"
}[m])
);
}

// =========================
// 暴露給 HTML
// =========================

window.login = login;
window.save = save;
window.publish = publish;
window.news = news;
window.content = content;
window.tab = tab;
window.logout = logout;
window.del = deleteAnnouncement;
window.deleteAnnouncement = deleteAnnouncement;

// =========================
// 頁面載入
// =========================

document.addEventListener("DOMContentLoaded", () => {
console.log("admin.js 已成功載入");

if (!configReady()) {
showLoginError(
"設定檔尚未完成，請確認 config.js 已正確載入。"
);
return;
}

const token = localStorage.getItem("access_token");

if (token) {
const loginBox = $("login");
const dashboard = $("dashboard");

if (loginBox) {
  loginBox.classList.add("hidden");
}

if (dashboard) {
  dashboard.classList.remove("hidden");
}

load();

}
});
