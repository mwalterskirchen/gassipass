-- The weekly goals (#144, ADR 0007).
--
-- Every Monday each dog gets three weekly goals. The first phone of the pack
-- that opens the app in the week makes the set and uploads it, and every
-- other phone uses that set. So the table keeps one set for each dog and
-- week: a second set with another ID breaks the unique key, and the phone
-- that uploaded it then downloads the set of the first phone. The week
-- starts on Monday at midnight in Europe/Zurich, and the set keeps that
-- Monday.
--
-- A set has three slots: the easy, the middle and the hard goal. Each slot
-- has a kind, a target for the kinds with a length (metres) or for the step
-- of an area (the step in percent, 100 for the full stamp), and an area, a
-- street or a ring where the kind needs one. A goal keeps the time at which
-- the dog first finished it, and the earliest time wins, so a finished goal
-- stays finished when a walk is deleted later. The progress itself is not
-- stored, because it comes from the walks (ADR 0002).
--
-- A member can swap one goal of each set. The set records the swapped slot,
-- and refuses a second swap. A phone that has not seen the swap cannot undo
-- it either, so its upload is refused, and it downloads the set.

create table public.weekly_goals (
  id uuid primary key,
  pack_id uuid not null references public.packs (id),
  dog_id uuid not null,
  -- The Monday on which the week starts.
  week_start date not null check (extract(isodow from week_start) = 1),
  goal1_kind text not null,
  goal1_target double precision,
  goal1_area integer,
  goal1_street text,
  goal1_ring integer,
  goal1_finished_at timestamptz,
  goal2_kind text not null,
  goal2_target double precision,
  goal2_area integer,
  goal2_street text,
  goal2_ring integer,
  goal2_finished_at timestamptz,
  goal3_kind text not null,
  goal3_target double precision,
  goal3_area integer,
  goal3_street text,
  goal3_ring integer,
  goal3_finished_at timestamptz,
  -- The slot whose goal a member swapped, from 1, or null.
  swapped_slot integer check (swapped_slot between 1 and 3),
  changed_at timestamptz not null default now(),
  deleted_at timestamptz,
  foreign key (dog_id, pack_id) references public.dogs (id, pack_id) deferrable initially immediate,
  check (goal1_kind in ('new_length', 'street', 'new_area', 'refresh', 'distance', 'step')),
  check (goal2_kind in ('new_length', 'street', 'new_area', 'refresh', 'distance', 'step')),
  check (goal3_kind in ('new_length', 'street', 'new_area', 'refresh', 'distance', 'step')),
  check (goal1_kind not in ('new_length', 'refresh', 'distance') or goal1_target > 0),
  check (goal2_kind not in ('new_length', 'refresh', 'distance') or goal2_target > 0),
  check (goal3_kind not in ('new_length', 'refresh', 'distance') or goal3_target > 0)
);

create unique index weekly_goals_one_per_dog_and_week
  on public.weekly_goals (dog_id, week_start)
  where deleted_at is null;
create index weekly_goals_pack_id_changed_at on public.weekly_goals (pack_id, changed_at);

create trigger note_change before insert or update on public.weekly_goals
  for each row execute function public.note_change();
create trigger refuse_row_of_deleted_pack before insert or update on public.weekly_goals
  for each row execute function public.refuse_row_of_deleted_pack();

-- Keeps the dog and the week of a set, allows one swap, and keeps the
-- earliest finish of each goal. A swapped goal starts without a finish.
create function public.keep_weekly_goals() returns trigger
language plpgsql
set search_path = ''
as $$
declare
  changed integer[] := '{}';
begin
  if new.dog_id <> old.dog_id or new.week_start <> old.week_start then
    raise exception 'A set of weekly goals keeps its dog and its week.' using errcode = '23514';
  end if;
  if (new.goal1_kind, new.goal1_target, new.goal1_area, new.goal1_street, new.goal1_ring)
     is distinct from (old.goal1_kind, old.goal1_target, old.goal1_area, old.goal1_street, old.goal1_ring) then
    changed := changed || 1;
  end if;
  if (new.goal2_kind, new.goal2_target, new.goal2_area, new.goal2_street, new.goal2_ring)
     is distinct from (old.goal2_kind, old.goal2_target, old.goal2_area, old.goal2_street, old.goal2_ring) then
    changed := changed || 2;
  end if;
  if (new.goal3_kind, new.goal3_target, new.goal3_area, new.goal3_street, new.goal3_ring)
     is distinct from (old.goal3_kind, old.goal3_target, old.goal3_area, old.goal3_street, old.goal3_ring) then
    changed := changed || 3;
  end if;
  if not (
    (cardinality(changed) = 0 and new.swapped_slot is not distinct from old.swapped_slot)
    or (old.swapped_slot is null and new.swapped_slot is not null and changed <@ array[new.swapped_slot])
  ) then
    raise exception 'A set of weekly goals has one swap only.' using errcode = '23514';
  end if;
  if old.swapped_slot is not null or new.swapped_slot is distinct from 1 then
    new.goal1_finished_at := least(old.goal1_finished_at, new.goal1_finished_at);
  end if;
  if old.swapped_slot is not null or new.swapped_slot is distinct from 2 then
    new.goal2_finished_at := least(old.goal2_finished_at, new.goal2_finished_at);
  end if;
  if old.swapped_slot is not null or new.swapped_slot is distinct from 3 then
    new.goal3_finished_at := least(old.goal3_finished_at, new.goal3_finished_at);
  end if;
  return new;
end;
$$;

revoke execute on function public.keep_weekly_goals() from public, anon, authenticated;

create trigger keep_weekly_goals before update on public.weekly_goals
  for each row execute function public.keep_weekly_goals();

alter table public.weekly_goals enable row level security;
revoke all on table public.weekly_goals from anon, authenticated;
grant select, insert, update on table public.weekly_goals to authenticated;

create policy "A member reads the weekly goals of their pack" on public.weekly_goals
  for select to authenticated
  using (pack_id = (select public.pack_of_caller()));
create policy "A member uploads weekly goals into their pack" on public.weekly_goals
  for insert to authenticated
  with check (pack_id = (select public.pack_of_caller()));
create policy "A member changes the weekly goals of their pack" on public.weekly_goals
  for update to authenticated
  using (pack_id = (select public.pack_of_caller()))
  with check (pack_id = (select public.pack_of_caller()));

-- The weekly goals move with the dogs, like the completed records.
create or replace function public.move_pack(old_pack uuid, new_pack uuid) returns void
language plpgsql
set search_path = ''
as $$
begin
  set constraints public.walk_dogs_walk_id_pack_id_fkey, public.walk_dogs_dog_id_pack_id_fkey,
    public.completed_areas_dog_id_pack_id_fkey, public.completed_streets_dog_id_pack_id_fkey,
    public.area_steps_dog_id_pack_id_fkey, public.completed_rings_dog_id_pack_id_fkey,
    public.weekly_goals_dog_id_pack_id_fkey deferred;
  update public.dogs set pack_id = new_pack where pack_id = old_pack;
  update public.walks set pack_id = new_pack where pack_id = old_pack;
  update public.walk_dogs set pack_id = new_pack where pack_id = old_pack;
  update public.completed_areas set pack_id = new_pack where pack_id = old_pack;
  update public.completed_streets set pack_id = new_pack where pack_id = old_pack;
  update public.area_steps set pack_id = new_pack where pack_id = old_pack;
  update public.completed_rings set pack_id = new_pack where pack_id = old_pack;
  update public.weekly_goals set pack_id = new_pack where pack_id = old_pack;
  set constraints public.walk_dogs_walk_id_pack_id_fkey, public.walk_dogs_dog_id_pack_id_fkey,
    public.completed_areas_dog_id_pack_id_fkey, public.completed_streets_dog_id_pack_id_fkey,
    public.area_steps_dog_id_pack_id_fkey, public.completed_rings_dog_id_pack_id_fkey,
    public.weekly_goals_dog_id_pack_id_fkey immediate;
  update public.packs set deleted_at = now(), moved_into = new_pack where id = old_pack;
end;
$$;

-- The weekly goals go with the pack of the only member, like the completed
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
      delete from public.weekly_goals where pack_id = any (deleted_packs);
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
