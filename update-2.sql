-- Home Moodboard: update 2
-- Adds documents, the clickable floor plan, comment replies and @mentions,
-- names for people, Instagram covers, link previews and markups.
-- Paste this whole file into Supabase → SQL Editor → New query → Run.
-- Safe to run more than once. It doesn't touch existing items or comments.

-- Extra details on board items (cover choice, link preview, markup links)
alter table public.items    add column if not exists meta jsonb not null default '{}'::jsonb;

-- Display names, used for @mentions
alter table public.members  add column if not exists name text;

-- Where each room sits on the floor plan: a list of [x, y, width, height] boxes, 0 to 1
alter table public.rooms    add column if not exists area jsonb;

-- Replies and @mentions
alter table public.comments add column if not exists parent_id uuid references public.comments(id) on delete cascade;
alter table public.comments add column if not exists mentions text[] not null default '{}';
create index if not exists comments_parent_idx on public.comments (parent_id);

-- Shared documents (files live in the same private storage bucket, under docs/)
create table if not exists public.documents (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  path         text not null,
  size         bigint,
  mime         text,
  room_id      uuid references public.rooms(id) on delete set null,
  note         text not null default '',
  uploaded_by  text default lower(auth.jwt() ->> 'email'),
  created_at   timestamptz not null default now()
);
create index if not exists documents_created_at_idx on public.documents (created_at desc);

-- Board-wide settings (the floor plan image)
create table if not exists public.settings (
  key         text primary key,
  value       jsonb,
  updated_at  timestamptz not null default now()
);

alter table public.documents enable row level security;
alter table public.settings  enable row level security;
drop policy if exists "members only" on public.documents;
create policy "members only" on public.documents for all to authenticated using (public.is_member()) with check (public.is_member());
drop policy if exists "members only" on public.settings;
create policy "members only" on public.settings  for all to authenticated using (public.is_member()) with check (public.is_member());

-- Allow files up to 50 MB (the most the free Supabase plan allows per file)
update storage.buckets set file_size_limit = 52428800 where id = 'moodboard';

-- Live updates for the new tables
do $$
begin
  begin alter publication supabase_realtime add table public.documents; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.settings;  exception when duplicate_object then null; end;
end $$;
