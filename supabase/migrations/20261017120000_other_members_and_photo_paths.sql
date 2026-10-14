-- Three changes from the review of the release (#130).
--
-- 1. An index on packs.moved_into. can_read_files_in follows moved_into for
--    each file that a member reads or deletes, and the policies of Storage
--    call it for each file.
-- 2. One function for the rule that a pack has members other than the
--    person. state_of_invitation, packs_deleted_with_account and
--    delete_account each wrote it out.
-- 3. A dog keeps a photo path that Storage has (see
--    keep_photo_path_in_storage).

create index packs_moved_into on public.packs (moved_into) where moved_into is not null;

-- Whether the pack has a member other than the person. A person in such a
-- pack is not its only member: an invitation into another pack refuses
-- them (ADR 0005), and their account deletion leaves the pack to the others.
create function public.has_other_members(pack uuid, person uuid) returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (select from public.members where members.pack_id = pack and members.account_id <> person);
$$;

revoke execute on function public.has_other_members(uuid, uuid) from public, anon, authenticated;

create or replace function public.state_of_invitation(invitation public.invitations, person uuid) returns text
language sql
stable
set search_path = ''
as $$
  select case
    when members.pack_id = invitation.pack_id then 'member'
    when invitation.used_at is not null then 'used'
    when invitation.expires_at <= now() then 'expired'
    when public.has_other_members(members.pack_id, person) then 'in_other_pack'
    else 'open'
  end
  from public.members where members.account_id = person;
$$;

create or replace function public.packs_deleted_with_account() returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select public.pack_and_packs_moved_into(members.pack_id)
  from public.members
  where members.account_id = (select auth.uid())
    and members.pack_id is not null
    and not public.has_other_members(members.pack_id, members.account_id);
$$;

create or replace function public.delete_account() returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  pack uuid;
  deleted_packs uuid[];
begin
  if caller is null then
    raise exception 'Only a signed-in person can delete their account.' using errcode = '42501';
  end if;
  select members.pack_id into pack from public.members where account_id = caller for update;
  if pack is not null then
    -- The lock keeps a join into the pack out until the deletion ends.
    perform from public.packs where id = pack for update;
    if public.has_other_members(pack, caller) then
      update public.packs set pack_owner_id = (
          select account_id from public.members
          where pack_id = pack and account_id <> caller
          order by joined_at, account_id
          limit 1)
        where id = pack and pack_owner_id = caller;
    else
      -- The rows go, and do not stay with a deletion time (ADR 0006),
      -- because no member is left who needs to learn about the deletion.
      deleted_packs := array(select public.pack_and_packs_moved_into(pack));
      if exists (
        select from storage.objects
        where bucket_id in ('tracks', 'dog-photos')
          and (storage.foldername(name))[1] = any (deleted_packs::text[])
      ) then
        raise exception 'The files of the pack must be deleted first.' using errcode = 'P0001';
      end if;
      delete from public.completed_streets where pack_id = any (deleted_packs);
      delete from public.completed_areas where pack_id = any (deleted_packs);
      delete from public.walk_dogs where pack_id = any (deleted_packs);
      delete from public.walks where pack_id = any (deleted_packs);
      delete from public.dogs where pack_id = any (deleted_packs);
      delete from public.invitations where pack_id = any (deleted_packs);
      delete from public.departures where pack_id = any (deleted_packs);
      update public.members set pack_id = null where account_id = caller;
      delete from public.packs where id = any (deleted_packs);
    end if;
  end if;
  -- This also deletes the member row, and the sessions of the account.
  delete from auth.users where id = caller;
end;
$$;

-- Two phones can change the same dog at nearly the same time. When one
-- phone gives the dog a new photo, it deletes the file of the old photo
-- (#127). The other phone may not have that change yet, and its next upload
-- of the dog names the path of the old photo. The same happens when one
-- phone removes the photo. So an update keeps the path of the row when the
-- new path is not in Storage, and the row never points to a missing file.
-- The phone uploads a new photo before its row, so a new path is in Storage.
create function public.keep_photo_path_in_storage() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.photo_path is distinct from old.photo_path
    and new.photo_path is not null
    and not exists (
      select from storage.objects where bucket_id = 'dog-photos' and name = new.photo_path
    ) then
    new.photo_path := old.photo_path;
  end if;
  return new;
end;
$$;

revoke execute on function public.keep_photo_path_in_storage() from public, anon, authenticated;

create trigger keep_photo_path_in_storage before update on public.dogs
  for each row execute function public.keep_photo_path_in_storage();
