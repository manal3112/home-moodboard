-- update-5: "Who's here" (live presence).
-- Lets signed-in board members see who else has the board open, on a PRIVATE realtime channel:
-- only people on the members list can join it or see who's on it. Safe to run more than once.

drop policy if exists "members see who's here" on realtime.messages;
create policy "members see who's here" on realtime.messages
  for select to authenticated
  using (realtime.topic() = 'presence:board' and public.is_member());

drop policy if exists "members share they're here" on realtime.messages;
create policy "members share they're here" on realtime.messages
  for insert to authenticated
  with check (realtime.topic() = 'presence:board' and public.is_member());
