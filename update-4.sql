-- Home Moodboard: update 4
-- Adds voice notes to comments.
-- Paste this whole file into Supabase → SQL Editor → New query → Run.
-- Safe to run more than once. Run update-2.sql and update-3.sql first if you haven't.

-- The recording is stored in the private "moodboard" bucket; this column points to it.
alter table public.comments add column if not exists audio_path text;
