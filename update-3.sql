-- Home Moodboard: update 3
-- Adds upvotes on board items, and an access list for the AI features.
-- Paste this whole file into Supabase → SQL Editor → New query → Run.
-- Safe to run more than once. Run update-2.sql first if you haven't.

-- Board owners: the only people who can choose who uses the AI features.
-- Starts as the first person added to the board (the email you put in schema.sql).
-- To add another owner later, run:  insert into public.admins (email) values ('their@email.com');
create table if not exists public.admins (
  email text primary key check (email = lower(email))
);
insert into public.admins (email)
select email from public.members order by added_at limit 1
on conflict do nothing;

-- People allowed to use the AI features (room briefs, Suggest details). Starts with the owners.
create table if not exists public.ai_users (
  email     text primary key check (email = lower(email)),
  added_at  timestamptz not null default now()
);
insert into public.ai_users (email) select email from public.admins on conflict do nothing;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_member() and exists (
    select 1 from public.admins where email = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;
create or replace function public.can_use_ai()
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_member() and exists (
    select 1 from public.ai_users where email = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;
grant execute on function public.is_admin()   to authenticated;
grant execute on function public.can_use_ai() to authenticated;

alter table public.admins   enable row level security;
alter table public.ai_users enable row level security;
-- Members can see who the owners are; nobody can change owners from the app.
drop policy if exists "members read" on public.admins;
create policy "members read" on public.admins for select to authenticated using (public.is_member());
-- Members can see who has AI access; only owners can grant or remove it.
drop policy if exists "members read" on public.ai_users;
drop policy if exists "owners add"   on public.ai_users;
drop policy if exists "owners remove" on public.ai_users;
create policy "members read"  on public.ai_users for select to authenticated using (public.is_member());
create policy "owners add"    on public.ai_users for insert to authenticated with check (public.is_admin());
create policy "owners remove" on public.ai_users for delete to authenticated using (public.is_admin());

-- Upvotes: one per person per item.
create table if not exists public.reactions (
  item_id     uuid not null references public.items(id) on delete cascade,
  email       text not null default lower(auth.jwt() ->> 'email'),
  created_at  timestamptz not null default now(),
  primary key (item_id, email)
);
alter table public.reactions enable row level security;
drop policy if exists "members read"   on public.reactions;
drop policy if exists "own vote add"    on public.reactions;
drop policy if exists "own vote remove" on public.reactions;
create policy "members read"    on public.reactions for select to authenticated using (public.is_member());
create policy "own vote add"    on public.reactions for insert to authenticated
  with check (public.is_member() and email = lower(auth.jwt() ->> 'email'));
create policy "own vote remove" on public.reactions for delete to authenticated
  using (public.is_member() and email = lower(auth.jwt() ->> 'email'));

do $$
begin
  begin alter publication supabase_realtime add table public.reactions; exception when duplicate_object then null; end;
end $$;
