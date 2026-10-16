-- The steps of the area stamp (#141).
--
-- The stamp of an area grows in steps. A dog gets the entry stamp with the
-- first segment that it collects in the area, and a step at 25%, 50% and 75%
-- completion. The full stamp, when the dog completes the area, stays in
-- completed_areas. Each step is a permanent record with a date, like a
-- completed area (ADR 0007), so it follows the rules of completed_areas: one
-- record stays for each dog, area and step, and the earliest one wins. Of two
-- records with the same date, the one with the smaller ID wins, as on the
-- phones. The other records stay with a deletion time.

create table public.area_steps (
  id uuid primary key,
  pack_id uuid not null references public.packs (id),
  dog_id uuid not null,
  -- The BFS number of the area.
  area integer not null,
  -- 0 for the entry stamp, or the completion of the step in percent.
  step integer not null check (step in (0, 25, 50, 75)),
  reached_at timestamptz not null,
  changed_at timestamptz not null default now(),
  deleted_at timestamptz,
  foreign key (dog_id, pack_id) references public.dogs (id, pack_id) deferrable initially immediate
);

create unique index area_steps_one_per_dog_area_and_step on public.area_steps (dog_id, area, step)
  where deleted_at is null;
create index area_steps_pack_id_changed_at on public.area_steps (pack_id, changed_at);

create trigger note_change before insert or update on public.area_steps
  for each row execute function public.note_change();
create trigger refuse_row_of_deleted_pack before insert or update on public.area_steps
  for each row execute function public.refuse_row_of_deleted_pack();

-- Keeps the earliest record of the dog, area and step. A later new record
-- gets a deletion time, and an earlier new record gives the stored one a
-- deletion time.
create function public.keep_earliest_area_step() returns trigger
language plpgsql
set search_path = ''
as $$
declare
  stored public.area_steps;
begin
  if new.deleted_at is not null then
    return new;
  end if;
  select * into stored from public.area_steps
    where dog_id = new.dog_id and area = new.area and step = new.step and id <> new.id and deleted_at is null
    for update;
  if not found then
    return new;
  end if;
  if (stored.reached_at, stored.id) < (new.reached_at, new.id) then
    new.deleted_at := now();
  else
    update public.area_steps set deleted_at = now() where id = stored.id;
  end if;
  return new;
end;
$$;

revoke execute on function public.keep_earliest_area_step() from public, anon, authenticated;

create trigger keep_earliest before insert or update on public.area_steps
  for each row execute function public.keep_earliest_area_step();

alter table public.area_steps enable row level security;
revoke all on table public.area_steps from anon, authenticated;
grant select, insert, update on table public.area_steps to authenticated;

create policy "A member reads the area steps of their pack" on public.area_steps
  for select to authenticated
  using (pack_id = (select public.pack_of_caller()));
create policy "A member uploads an area step into their pack" on public.area_steps
  for insert to authenticated
  with check (pack_id = (select public.pack_of_caller()));
create policy "A member changes an area step of their pack" on public.area_steps
  for update to authenticated
  using (pack_id = (select public.pack_of_caller()))
  with check (pack_id = (select public.pack_of_caller()));

-- The steps move with the dogs, like the completed records.
create or replace function public.move_pack(old_pack uuid, new_pack uuid) returns void
language plpgsql
set search_path = ''
as $$
begin
  set constraints public.walk_dogs_walk_id_pack_id_fkey, public.walk_dogs_dog_id_pack_id_fkey,
    public.completed_areas_dog_id_pack_id_fkey, public.completed_streets_dog_id_pack_id_fkey,
    public.area_steps_dog_id_pack_id_fkey deferred;
  update public.dogs set pack_id = new_pack where pack_id = old_pack;
  update public.walks set pack_id = new_pack where pack_id = old_pack;
  update public.walk_dogs set pack_id = new_pack where pack_id = old_pack;
  update public.completed_areas set pack_id = new_pack where pack_id = old_pack;
  update public.completed_streets set pack_id = new_pack where pack_id = old_pack;
  update public.area_steps set pack_id = new_pack where pack_id = old_pack;
  set constraints public.walk_dogs_walk_id_pack_id_fkey, public.walk_dogs_dog_id_pack_id_fkey,
    public.completed_areas_dog_id_pack_id_fkey, public.completed_streets_dog_id_pack_id_fkey,
    public.area_steps_dog_id_pack_id_fkey immediate;
  update public.packs set deleted_at = now(), moved_into = new_pack where id = old_pack;
end;
$$;

-- The steps go with the pack of the only member, like the completed records.
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
