-- The only member of a pack joins another pack, and brings their dogs (ADR
-- 0005 as revised by ADR 0006, #105).
--
-- The join moves the dogs of the old pack, with their walks, the dogs of
-- the walks and the completed records, into the new pack. Each moved row
-- gets the time of the move as its change, so that the phones of the new
-- pack download it. The old pack then disappears. It keeps the pack that it
-- moved into, so that the other phones of the person learn where their
-- dogs went.
--
-- The GPS tracks and the photos stay in the folder of the old pack in
-- Storage, because SQL cannot move a file. This migration clears the paths
-- of the moved rows. The migration 20261014200000_read_files_of_moved_packs
-- keeps them instead, and lets the members of the new pack read the folder
-- of the old pack.

alter table public.packs add column moved_into uuid references public.packs (id);

-- A walk and its dogs, and a dog and its completed records, are always in
-- the same pack. During a move, these checks wait until every row of the
-- pack has moved.
alter table public.walk_dogs
  alter constraint walk_dogs_walk_id_pack_id_fkey deferrable initially immediate,
  alter constraint walk_dogs_dog_id_pack_id_fkey deferrable initially immediate;
alter table public.completed_areas
  alter constraint completed_areas_dog_id_pack_id_fkey deferrable initially immediate;
alter table public.completed_streets
  alter constraint completed_streets_dog_id_pack_id_fkey deferrable initially immediate;

-- Refuses a row of a pack that has disappeared. The lock waits for a move of
-- the pack that runs at the same time, so that an upload that started before
-- the move cannot leave a row in the old pack.
create function public.refuse_row_of_deleted_pack() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform from public.packs where id = new.pack_id and deleted_at is null for key share;
  if not found then
    raise exception 'The pack has disappeared.' using errcode = '23503';
  end if;
  return new;
end;
$$;

revoke execute on function public.refuse_row_of_deleted_pack() from public, anon, authenticated;

create trigger refuse_row_of_deleted_pack before insert or update on public.dogs
  for each row execute function public.refuse_row_of_deleted_pack();
create trigger refuse_row_of_deleted_pack before insert or update on public.walks
  for each row execute function public.refuse_row_of_deleted_pack();
create trigger refuse_row_of_deleted_pack before insert or update on public.walk_dogs
  for each row execute function public.refuse_row_of_deleted_pack();
create trigger refuse_row_of_deleted_pack before insert or update on public.completed_areas
  for each row execute function public.refuse_row_of_deleted_pack();
create trigger refuse_row_of_deleted_pack before insert or update on public.completed_streets
  for each row execute function public.refuse_row_of_deleted_pack();

-- Moves the dogs of the old pack, with their walks, the dogs of the walks
-- and the completed records, into the new pack, and lets the old pack
-- disappear. The caller holds the lock of the old pack.
create function public.move_pack(old_pack uuid, new_pack uuid) returns void
language plpgsql
set search_path = ''
as $$
begin
  set constraints public.walk_dogs_walk_id_pack_id_fkey, public.walk_dogs_dog_id_pack_id_fkey,
    public.completed_areas_dog_id_pack_id_fkey, public.completed_streets_dog_id_pack_id_fkey deferred;
  update public.dogs set pack_id = new_pack, photo_path = null where pack_id = old_pack;
  update public.walks set pack_id = new_pack, track_path = null where pack_id = old_pack;
  update public.walk_dogs set pack_id = new_pack where pack_id = old_pack;
  update public.completed_areas set pack_id = new_pack where pack_id = old_pack;
  update public.completed_streets set pack_id = new_pack where pack_id = old_pack;
  set constraints public.walk_dogs_walk_id_pack_id_fkey, public.walk_dogs_dog_id_pack_id_fkey,
    public.completed_areas_dog_id_pack_id_fkey, public.completed_streets_dog_id_pack_id_fkey immediate;
  update public.packs set deleted_at = now(), moved_into = new_pack where id = old_pack;
end;
$$;

revoke execute on function public.move_pack(uuid, uuid) from public, anon, authenticated;

-- Whether the person can join with the invitation:
--   'open'          the person can join. The only member of a pack brings
--                   their dogs along.
--   'member'        the person is a member of the pack already, for example
--                   the pack owner who opens their own invitation.
--   'used'          somebody joined with the invitation.
--   'expired'       the invitation is older than 7 days.
--   'in_other_pack' the person is a member of another pack with other
--                   members, and must leave it first (ADR 0005).
create or replace function public.state_of_invitation(invitation public.invitations, person uuid) returns text
language sql
stable
set search_path = ''
as $$
  select case
    when members.pack_id = invitation.pack_id then 'member'
    when invitation.used_at is not null then 'used'
    when invitation.expires_at <= now() then 'expired'
    when exists (select from public.members others
                 where others.pack_id = members.pack_id and others.account_id <> person) then 'in_other_pack'
    else 'open'
  end
  from public.members where members.account_id = person;
$$;

-- Makes the calling person a member of the pack of the invitation, and uses
-- up the invitation. The only member of a pack brings their dogs along, and
-- their old pack disappears. It returns 'joined', or the state of the
-- invitation that keeps the person out (see `state_of_invitation`), or
-- 'unknown'.
create or replace function public.join_pack(token text) returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  invitation public.invitations;
  old_pack uuid;
  state text;
begin
  if caller is null then
    raise exception 'Only a signed-in person can join a pack.' using errcode = '42501';
  end if;
  invitation := public.invitation_with_token(token);
  if invitation.id is null then
    return 'unknown';
  end if;
  -- The locks keep these out until this join ends: a second join with the
  -- same invitation, a pack that the person makes, a join into the old pack
  -- of the person, and a move of the new pack.
  select * into invitation from public.invitations where id = invitation.id for update;
  perform from public.packs where id = invitation.pack_id and deleted_at is null for share;
  if not found then
    return 'unknown';
  end if;
  select members.pack_id into old_pack from public.members where account_id = caller for update;
  if not found then
    raise exception 'The account has no member row.' using errcode = 'P0002';
  end if;
  if old_pack <> invitation.pack_id then
    perform from public.packs where id = old_pack for update;
  end if;
  state := public.state_of_invitation(invitation, caller);
  if state <> 'open' then
    return state;
  end if;
  if old_pack is not null then
    perform public.move_pack(old_pack, invitation.pack_id);
  end if;
  update public.invitations set used_at = now(), used_by = caller where id = invitation.id;
  update public.members set pack_id = invitation.pack_id, joined_at = now() where account_id = caller;
  return 'joined';
end;
$$;

-- Whether the pack moved into the pack of the calling person, because its
-- only member joined that pack. Another phone of that person still has the
-- old pack, and moves its dogs into the new pack without a question.
create function public.has_moved_into_pack_of_caller(pack_id uuid) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select from public.packs
    where packs.id = has_moved_into_pack_of_caller.pack_id and packs.moved_into = (select public.pack_of_caller())
  );
$$;

revoke execute on function public.has_moved_into_pack_of_caller(uuid) from public, anon;
grant execute on function public.has_moved_into_pack_of_caller(uuid) to authenticated;
