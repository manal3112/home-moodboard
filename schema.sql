-- Home Moodboard: Supabase setup
-- 1. Replace YOUR_EMAIL@example.com near the bottom with the email you'll sign in with.
-- 2. Paste this whole file into Supabase → SQL Editor → New query → Run.
-- Safe to re-run: it skips things that already exist.

create extension if not exists pgcrypto;

-- People allowed to see and edit the board ------------------------------
create table if not exists public.members (
  email     text primary key check (email = lower(email)),
  added_at  timestamptz not null default now()
);

create or replace function public.is_member()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.members
    where email = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;
grant execute on function public.is_member() to authenticated;

-- Rooms (editable from the app) -----------------------------------------
create table if not exists public.rooms (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  position    int  not null default 0,
  created_at  timestamptz not null default now()
);

-- Board items: Instagram posts, photos, sketches, links, notes ----------
create table if not exists public.items (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null check (kind in ('instagram','image','sketch','link','note')),
  title       text not null default '',
  url         text,
  note        text not null default '',
  room_id     uuid references public.rooms(id) on delete set null,
  type        text,
  priority    text not null default 'nice' check (priority in ('must','nice','avoid')),
  image_path  text,
  created_by  text default lower(auth.jwt() ->> 'email'),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists items_created_at_idx on public.items (created_at desc);

create table if not exists public.comments (
  id          uuid primary key default gen_random_uuid(),
  item_id     uuid not null references public.items(id) on delete cascade,
  author      text not null default lower(auth.jwt() ->> 'email'),
  body        text not null,
  created_at  timestamptz not null default now()
);
create index if not exists comments_item_idx on public.comments (item_id);

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

drop trigger if exists items_touch on public.items;
create trigger items_touch before update on public.items
  for each row execute function public.touch_updated_at();

-- Row-level security: only members can read or write anything ------------
alter table public.members  enable row level security;
alter table public.rooms    enable row level security;
alter table public.items    enable row level security;
alter table public.comments enable row level security;

drop policy if exists "members only" on public.members;
create policy "members only" on public.members  for all to authenticated using (public.is_member()) with check (public.is_member());
drop policy if exists "members only" on public.rooms;
create policy "members only" on public.rooms    for all to authenticated using (public.is_member()) with check (public.is_member());
drop policy if exists "members only" on public.items;
create policy "members only" on public.items    for all to authenticated using (public.is_member()) with check (public.is_member());
drop policy if exists "members only" on public.comments;
create policy "members only" on public.comments for all to authenticated using (public.is_member()) with check (public.is_member());

-- Private storage bucket for photos, screenshots and sketches ------------
insert into storage.buckets (id, name, public, file_size_limit)
values ('moodboard', 'moodboard', false, 20971520)
on conflict (id) do nothing;

drop policy if exists "moodboard read"   on storage.objects;
drop policy if exists "moodboard insert" on storage.objects;
drop policy if exists "moodboard update" on storage.objects;
drop policy if exists "moodboard delete" on storage.objects;
create policy "moodboard read"   on storage.objects for select to authenticated using (bucket_id = 'moodboard' and public.is_member());
create policy "moodboard insert" on storage.objects for insert to authenticated with check (bucket_id = 'moodboard' and public.is_member());
create policy "moodboard update" on storage.objects for update to authenticated using (bucket_id = 'moodboard' and public.is_member());
create policy "moodboard delete" on storage.objects for delete to authenticated using (bucket_id = 'moodboard' and public.is_member());

-- Live updates: everyone sees new items and comments without reloading ---
do $$
begin
  begin alter publication supabase_realtime add table public.items;    exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.comments; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.rooms;    exception when duplicate_object then null; end;
end $$;

-- Starting rooms (rename, reorder or remove them later in the app) -------
insert into public.rooms (name, position)
select name, pos from (values
  ('Living Room',1),('Dining',2),('Kitchen',3),('Pooja Room',4),('Master Bedroom',5),
  ('Bedroom 2',6),('Bedroom 3',7),('Bathrooms',8),('Entry / Foyer',9),('Balcony',10)
) as v(name, pos)
where not exists (select 1 from public.rooms);

-- You: the first member. Add the architects later from the app. ---------
insert into public.members (email) values (lower('YOUR_EMAIL@example.com'))
on conflict do nothing;
