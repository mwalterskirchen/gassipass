-- The home base of the pack and the ring stamps (#142).
--
-- Each pack has a home base, the centre of its rings. It is stored with the
-- pack: latitude, longitude and the time when a member set it. Only the
-- members of the pack read it, through the policy of the packs. Any member
-- can move it, and the last write wins (ADR 0006). A phone uploads the home
-- base only after a member moved it there, so a new name from a phone that
-- has not seen a move keeps the move.
--
-- A ring stamp is a permanent record with a date, like a completed area
-- (ADR 0007), so it follows the rules of completed_areas: one record stays
-- for each dog, ring number and centre, and the earliest one wins. Of two
-- records with the same date, the one with the smaller ID wins, as on the
-- phones. The other records stay with a deletion time. A stamp keeps its
-- radius and its centre, so that the stamps of an old home base keep their
-- place.

alter table public.packs
  add column home_latitude double precision check (home_latitude between -90 and 90),
  add column home_longitude double precision check (home_longitude between -180 and 180),
  add column home_set_at timestamptz,
  add constraint packs_home_base_whole check (
    (home_latitude is null) = (home_longitude is null) and (home_latitude is null) = (home_set_at is null));

-- The grant on the name stays, and the home base gets its own.
grant update (home_latitude, home_longitude, home_set_at) on table public.packs to authenticated;

create table public.completed_rings (
  id uuid primary key,
  pack_id uuid not null references public.packs (id),
  dog_id uuid not null,
  -- The number of the ring, from 1.
  ring integer not null check (ring >= 1),
  radius_m double precision not null check (radius_m > 0),
  -- The home base of the time of the stamp.
  centre_latitude double precision not null check (centre_latitude between -90 and 90),
  centre_longitude double precision not null check (centre_longitude between -180 and 180),
  completed_at timestamptz not null,
  changed_at timestamptz not null default now(),
  deleted_at timestamptz,
  foreign key (dog_id, pack_id) references public.dogs (id, pack_id) deferrable initially immediate
);

create unique index completed_rings_one_per_dog_ring_and_centre
  on public.completed_rings (dog_id, ring, centre_latitude, centre_longitude)
  where deleted_at is null;
create index completed_rings_pack_id_changed_at on public.completed_rings (pack_id, changed_at);

create trigger note_change before insert or update on public.completed_rings
  for each row execute function public.note_change();
create trigger refuse_row_of_deleted_pack before insert or update on public.completed_rings
  for each row execute function public.refuse_row_of_deleted_pack();

-- Keeps the earliest stamp of the dog, ring and centre. A later new stamp
-- gets a deletion time, and an earlier new stamp gives the stored one a
-- deletion time.
create function public.keep_earliest_completed_ring() returns trigger
language plpgsql
set search_path = ''
as $$
declare
  stored public.completed_rings;
begin
  if new.deleted_at is not null then
    return new;
  end if;
  select * into stored from public.completed_rings
    where dog_id = new.dog_id and ring = new.ring and centre_latitude = new.centre_latitude
      and centre_longitude = new.centre_longitude and id <> new.id and deleted_at is null
    for update;
  if not found then
    return new;
  end if;
  if (stored.completed_at, stored.id) < (new.completed_at, new.id) then
    new.deleted_at := now();
  else
    update public.completed_rings set deleted_at = now() where id = stored.id;
  end if;
  return new;
end;
$$;

revoke execute on function public.keep_earliest_completed_ring() from public, anon, authenticated;

create trigger keep_earliest before insert or update on public.completed_rings
  for each row execute function public.keep_earliest_completed_ring();

alter table public.completed_rings enable row level security;
revoke all on table public.completed_rings from anon, authenticated;
grant select, insert, update on table public.completed_rings to authenticated;

create policy "A member reads the ring stamps of their pack" on public.completed_rings
  for select to authenticated
  using (pack_id = (select public.pack_of_caller()));
create policy "A member uploads a ring stamp into their pack" on public.completed_rings
  for insert to authenticated
  with check (pack_id = (select public.pack_of_caller()));
create policy "A member changes a ring stamp of their pack" on public.completed_rings
  for update to authenticated
  using (pack_id = (select public.pack_of_caller()))
  with check (pack_id = (select public.pack_of_caller()));

-- The ring stamps move with the dogs, like the completed records. The home
-- base of the old pack goes with it, and the dogs get the rings of the new
-- pack.
create or replace function public.move_pack(old_pack uuid, new_pack uuid) returns void
language plpgsql
set search_path = ''
as $$
begin
  set constraints public.walk_dogs_walk_id_pack_id_fkey, public.walk_dogs_dog_id_pack_id_fkey,
    public.completed_areas_dog_id_pack_id_fkey, public.completed_streets_dog_id_pack_id_fkey,
    public.area_steps_dog_id_pack_id_fkey, public.completed_rings_dog_id_pack_id_fkey deferred;
  update public.dogs set pack_id = new_pack where pack_id = old_pack;
  update public.walks set pack_id = new_pack where pack_id = old_pack;
  update public.walk_dogs set pack_id = new_pack where pack_id = old_pack;
  update public.completed_areas set pack_id = new_pack where pack_id = old_pack;
  update public.completed_streets set pack_id = new_pack where pack_id = old_pack;
  update public.area_steps set pack_id = new_pack where pack_id = old_pack;
  update public.completed_rings set pack_id = new_pack where pack_id = old_pack;
  set constraints public.walk_dogs_walk_id_pack_id_fkey, public.walk_dogs_dog_id_pack_id_fkey,
    public.completed_areas_dog_id_pack_id_fkey, public.completed_streets_dog_id_pack_id_fkey,
    public.area_steps_dog_id_pack_id_fkey, public.completed_rings_dog_id_pack_id_fkey immediate;
  update public.packs set deleted_at = now(), moved_into = new_pack where id = old_pack;
end;
$$;

-- The ring stamps go with the pack of the only member, like the completed
-- records.
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
      delete from public.completed_rings where pack_id = any (deleted_packs);
      delete from public.area_steps where pack_id = any (deleted_packs);
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
