create table if not exists public.site_settings (
id integer primary key default 1,
site_name text default '商業簡介',
hero_title text default '商業簡介',
hero_text text default '繽紛、活潑、充滿特色的專屬網站',
hero_image text default '1000116817.jpg',
about_title text default '✨ 商業簡介',
about_subtitle text default '讓訪客快速了解你、你的品牌與網站',
about1_title text default '🌟 我們是誰？',
about1_text text default '在這裡介紹你的品牌、社群或作品。',
about2_title text default '💫 我們的特色',
about2_text text default '活潑的視覺設計、清楚的資訊分類與簡單方便的網站導覽。',
features_title text default '⭐ 網站特色 ⭐',
features_subtitle text default '用可愛的卡片展示你的內容',
f1_title text default '角色／品牌', f1_text text default '放入角色、LOGO 或品牌介紹。',
f2_title text default '精彩內容', f2_text text default '展示作品、活動或特色內容。',
f3_title text default '活動挑戰', f3_text text default '放入活動、比賽或挑戰資訊。',
f4_title text default '精彩企劃', f4_text text default '放置你的特色企劃與最新內容。',
contact1 text default '📧 Email：example@email.com',
contact2 text default '💬 社群：加入我們的社群',
contact3 text default '📱 聯絡方式：請填入你的資訊',
created_at timestamptz default now(), updated_at timestamptz default now());
insert into public.site_settings(id) values(1) on conflict(id) do nothing;
alter table public.site_settings enable row level security;
drop policy if exists "public can read site settings" on public.site_settings;
drop policy if exists "authenticated admins can update site settings" on public.site_settings;
create policy "public can read site settings" on public.site_settings for select using(true);
create policy "authenticated admins can update site settings" on public.site_settings for update to authenticated using(true) with check(true);
