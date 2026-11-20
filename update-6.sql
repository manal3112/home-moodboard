-- update-6: "Who's here" becomes owner-only, with last seen and viewing history.
-- While someone has the board open it quietly checks in (which section, which idea), and logs the ideas and
-- documents they open. Only board owners (the admins table) can read any of it; everyone else sees nothing.
-- Safe to run more than once.

-- 1. Retire update-5's shared live channel: anyone who could join it could also see everyone on it.
drop policy if exists "members see who's here" on realtime.messages;
drop policy if exists "members share they're here" on realtime.messages;

-- 2. Last seen: one row per person, refreshed about every 45 seconds while they have the board open.
create table if not exists public.last_seen (
  email    text primary key,
  at       timestamptz not null default now(),
  section  text,
  item_id  uuid,
  room_id  uuid,
  away     boolean not null default false
);

-- 3. What each person opened.
create table if not exists public.views (
  id       bigint generated always as identity primary key,
  email    text not null,
  item_id  uuid references public.items(id) on delete cascade,
  doc_id   uuid references public.documents(id) on delete cascade,
  at       timestamptz not null default now()
);
create index if not exists views_email_at_idx on public.views (email, at desc);
create index if not exists views_item_idx     on public.views (item_id, at desc);

-- Only owners can read. There are no insert/update policies: people can only write through check_in() below,
-- and only as themselves.
alter table public.last_seen enable row level security;
alter table public.views     enable row level security;
drop policy if exists "owners read" on public.last_seen;
create policy "owners read" on public.last_seen for select to authenticated using (public.is_admin());
drop policy if exists "owners read" on public.views;
create policy "owners read" on public.views for select to authenticated using (public.is_admin());

-- Called by the app. Returns the server's clock so "online now" isn't thrown off by a phone's wrong time.
create or replace function public.check_in(p_section text, p_item uuid, p_room uuid, p_away boolean, p_doc uuid default null)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare e text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if not public.is_member() then return now(); end if;
  insert into public.last_seen as s (email, at, section, item_id, room_id, away)
  values (e, now(), left(p_section, 20), p_item, p_room, coalesce(p_away, false))
  on conflict (email) do update set at = excluded.at, section = excluded.section, item_id = excluded.item_id,
    room_id = excluded.room_id, away = excluded.away;
  -- Log each idea or document once per half hour, so leaving it open doesn't flood the history.
  if p_item is not null and exists (select 1 from public.items where id = p_item)
     and not exists (select 1 from public.views where email = e and item_id = p_item and at > now() - interval '30 minutes') then
    insert into public.views (email, item_id) values (e, p_item);
  end if;
  if p_doc is not null and exists (select 1 from public.documents where id = p_doc)
     and not exists (select 1 from public.views where email = e and doc_id = p_doc and at > now() - interval '30 minutes') then
    insert into public.views (email, doc_id) values (e, p_doc);
  end if;
  return now();
end $$;
revoke all on function public.check_in(text, uuid, uuid, boolean, uuid) from public, anon;
grant execute on function public.check_in(text, uuid, uuid, boolean, uuid) to authenticated;

-- Live updates for the owner's "Here now" (row security still applies, so only owners receive them).
do $$ begin
  begin alter publication supabase_realtime add table public.last_seen; exception when duplicate_object then null; end;
end $$;
