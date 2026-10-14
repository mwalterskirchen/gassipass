-- A person deletes their account (#107). The App Store requires it.
--
-- The account and the member row are deleted. The walks that the person
-- recorded stay with the dogs, because a walk keeps only the name of the
-- member. When the pack owner deletes their account and the pack has other
-- members, the member who joined first becomes the pack owner. When the
-- person is the only member, the pack and everything in it is deleted.
--
-- SQL cannot delete a file in Storage. So the phone of the only member first
-- deletes the files of the pack through the Storage API, in the folder of
-- each pack that `packs_deleted_with_account` gives, and then deletes the
-- account.

-- A pack that has disappeared, because its only member joined another pack,
-- loses its pack owner when that person deletes their account. Its row stays,
-- because the members of the new pack read its files through it. A pack that
-- exists always has a pack owner.
alter table public.packs
  alter column pack_owner_id drop not null,
  add constraint packs_pack_owner_of_existing_pack check (pack_owner_id is not null or deleted_at is not null),
  drop constraint packs_pack_owner_id_fkey,
  add constraint packs_pack_owner_id_fkey foreign key (pack_owner_id) references auth.users (id) on delete set null;

-- The pack, and each pack that moved into it, also through another pack that
-- moved later.
create function public.pack_and_packs_moved_into(pack uuid) returns setof uuid
language sql
stable
set search_path = ''
as $$
  with recursive moved (id) as (
    select pack
    union
    select packs.id from public.packs join moved on packs.moved_into = moved.id
  )
  select id from moved;
$$;

revoke execute on function public.pack_and_packs_moved_into(uuid) from public, anon, authenticated;

-- Whether the calling person reads the files in the folder: the folder of
-- their pack, or of a pack that moved into it, also through another pack.
-- It reads the packs as the definer, because a member cannot read a pack
-- that has disappeared.
create or replace function public.can_read_files_in(folder text) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select from public.pack_and_packs_moved_into((select public.pack_of_caller())) as pack (id)
    where pack.id::text = folder
  );
$$;

-- A member deletes the files that they read, so that the only member can
-- delete the files of each pack that moved into their pack.
drop policy "A member deletes a file of their pack" on storage.objects;
create policy "A member deletes a file of their pack" on storage.objects
  for delete to authenticated
  using (bucket_id in ('tracks', 'dog-photos')
    and public.can_read_files_in((storage.foldername(name))[1]));

-- The packs whose folders in Storage the phone deletes before it deletes
-- the account: for the only member of a pack, the pack and each pack that
-- moved into it. A person in a pack with other members, or in no pack, gets
-- none.
create function public.packs_deleted_with_account() returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select public.pack_and_packs_moved_into(members.pack_id)
  from public.members
  where members.account_id = (select auth.uid())
    and members.pack_id is not null
    and not exists (
      select from public.members others
      where others.pack_id = members.pack_id and others.account_id <> members.account_id
    );
$$;

-- Deletes the account of the calling person (see the top of this file). The
-- only member must delete the files of the pack first.
create function public.delete_account() returns void
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
    if exists (select from public.members where pack_id = pack and account_id <> caller) then
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

revoke execute on function public.packs_deleted_with_account(), public.delete_account() from public, anon;
grant execute on function public.packs_deleted_with_account(), public.delete_account() to authenticated;
