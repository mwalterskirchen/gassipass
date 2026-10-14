-- A walk from before the accounts has an empty member name, which meant the
-- person who recorded it on their phone. It gets the name of the member who
-- uploads it. When the only member of a pack joins another pack, they bring
-- such walks along, and the walks get their name with the move (#105).
--
-- This replaces the rule that only the pack owner names such walks, because
-- the person who joins was the pack owner of their old pack.

drop trigger name_walk_of_pack_owner on public.walks;
drop function public.name_walk_of_pack_owner();

create function public.name_walk_of_uploader() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.member_name = '' then
    new.member_name := coalesce(
      (select members.name from public.members where members.account_id = (select auth.uid())),
      '');
  end if;
  return new;
end;
$$;

revoke execute on function public.name_walk_of_uploader() from public, anon, authenticated;

create trigger name_walk_of_uploader before insert or update on public.walks
  for each row execute function public.name_walk_of_uploader();
