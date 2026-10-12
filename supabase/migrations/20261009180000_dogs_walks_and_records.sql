-- The dogs, the walks and the completed records of a pack on the server
-- (ADR 0006, #101).
--
-- Each phone uploads the rows that changed on it. The phone makes the ID of
-- each row, which is the same on every phone. An upload writes the whole
-- row, and the last write wins by the time on the server (`changed_at`). A
-- deleted row stays with its deletion time, so that the other phones learn
-- about the deletion. So the phones never delete a row.
--
-- Each row keeps the ID of its pack, so that row-level security and the
-- download of a pack need no join.

-- The pack of the calling person, or null for a person in no pack.
create function public.pack_of_caller() returns uuid
language sql
stable
set search_path = ''
as $$
  select pack_id from public.members where account_id = (select auth.uid());
$$;

revoke execute on function public.pack_of_caller() from public, anon;
grant execute on function public.pack_of_caller() to authenticated;

-- The dogs of the packs. The app never deletes a dog, it retires it.
create table public.dogs (
  id uuid primary key,
  pack_id uuid not null references public.packs (id),
  name text not null check (char_length(name) <= 100),
  -- The path of the photo in the Storage bucket "dog-photos", or null for a
  -- dog without a photo.
  photo_path text,
  -- The date when the dog became a retired dog, or null.
  retired_at timestamptz,
  retirement_reason text not null default '' check (char_length(retirement_reason) <= 1000),
  changed_at timestamptz not null default now(),
  deleted_at timestamptz,
  -- For the foreign keys that keep a walk and its dogs in the same pack.
  unique (id, pack_id)
);

create index dogs_pack_id_changed_at on public.dogs (pack_id, changed_at);

create trigger note_change before insert or update on public.dogs
  for each row execute function public.note_change();

alter table public.dogs enable row level security;
revoke all on table public.dogs from anon, authenticated;
grant select, insert, update on table public.dogs to authenticated;

create policy "A member reads the dogs of their pack" on public.dogs
  for select to authenticated
  using (pack_id = (select public.pack_of_caller()));
create policy "A member uploads a dog into their pack" on public.dogs
  for insert to authenticated
  with check (pack_id = (select public.pack_of_caller()));
create policy "A member changes a dog of their pack" on public.dogs
  for update to authenticated
  using (pack_id = (select public.pack_of_caller()))
  with check (pack_id = (select public.pack_of_caller()));

-- The ended walks of the packs. A walk that is still being recorded stays on
-- its phone until it ends.
create table public.walks (
  id uuid primary key,
  pack_id uuid not null references public.packs (id),
  started_at timestamptz not null,
  ended_at timestamptz not null,
  -- The path of the GPS track in the Storage bucket "tracks", or null for a
  -- walk without a track.
  track_path text,
  -- The distance of the walk, which the phone calculates from the track.
  distance_metres double precision not null default 0,
  -- The version of the rules that calculated the distance.
  distance_version integer not null default 0,
  -- The last time the member who recorded the walk answered that it had
  -- not ended yet.
  continued_at timestamptz,
  -- The device that recorded the walk.
  device_id text not null default '' check (char_length(device_id) <= 100),
  -- The name of the member who recorded the walk.
  member_name text not null default '' check (char_length(member_name) <= 100),
  changed_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (id, pack_id)
);

create index walks_pack_id_changed_at on public.walks (pack_id, changed_at);

create trigger note_change before insert or update on public.walks
  for each row execute function public.note_change();

-- A walk from before the accounts has an empty member name, which meant the
-- pack owner. It gets the name of the pack owner when it uploads. Only the
-- phone of the pack owner has such walks (ADR 0006), so a walk with an empty
-- name from another member keeps it.
create function public.name_walk_of_pack_owner() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.member_name = '' then
    new.member_name := coalesce(
      (select members.name from public.packs
         join public.members on members.account_id = packs.pack_owner_id
         where packs.id = new.pack_id and packs.pack_owner_id = (select auth.uid())),
      '');
  end if;
  return new;
end;
$$;

revoke execute on function public.name_walk_of_pack_owner() from public, anon, authenticated;

create trigger name_walk_of_pack_owner before insert or update on public.walks
  for each row execute function public.name_walk_of_pack_owner();

-- One dog that takes part in one walk. The dogs of a walk are rows of their
-- own, so that a change to the dogs does not overwrite the walk.
create table public.walk_dogs (
  id uuid primary key,
  pack_id uuid not null references public.packs (id),
  walk_id uuid not null,
  dog_id uuid not null,
  changed_at timestamptz not null default now(),
  deleted_at timestamptz,
  -- The walk and the dog are in the pack of the row.
  foreign key (walk_id, pack_id) references public.walks (id, pack_id),
  foreign key (dog_id, pack_id) references public.dogs (id, pack_id)
);

create index walk_dogs_pack_id_changed_at on public.walk_dogs (pack_id, changed_at);
create index walk_dogs_walk_id on public.walk_dogs (walk_id, pack_id);
create index walk_dogs_dog_id on public.walk_dogs (dog_id, pack_id);

create trigger note_change before insert or update on public.walk_dogs
  for each row execute function public.note_change();

alter table public.walks enable row level security;
alter table public.walk_dogs enable row level security;
revoke all on table public.walks, public.walk_dogs from anon, authenticated;
grant select, insert, update on table public.walks, public.walk_dogs to authenticated;

create policy "A member reads the walks of their pack" on public.walks
  for select to authenticated
  using (pack_id = (select public.pack_of_caller()));
create policy "A member uploads a walk into their pack" on public.walks
  for insert to authenticated
  with check (pack_id = (select public.pack_of_caller()));
create policy "A member changes a walk of their pack" on public.walks
  for update to authenticated
  using (pack_id = (select public.pack_of_caller()))
  with check (pack_id = (select public.pack_of_caller()));

create policy "A member reads the dogs of the walks of their pack" on public.walk_dogs
  for select to authenticated
  using (pack_id = (select public.pack_of_caller()));
create policy "A member uploads a dog of a walk into their pack" on public.walk_dogs
  for insert to authenticated
  with check (pack_id = (select public.pack_of_caller()));
create policy "A member changes a dog of a walk of their pack" on public.walk_dogs
  for update to authenticated
  using (pack_id = (select public.pack_of_caller()))
  with check (pack_id = (select public.pack_of_caller()));

-- The permanent records that a dog has completed an area or a street. Two
-- phones can each store a record for the same dog and area, or the same dog
-- and street, before the records of one phone reach the other. The server
-- keeps the rule of the phones: one record stays for each dog and area, or
-- each dog and street, and the earliest one wins. Of two records with the
-- same date, the one with the smaller ID wins, as on the phones. The other
-- records stay with a deletion time.
create table public.completed_areas (
  id uuid primary key,
  pack_id uuid not null references public.packs (id),
  dog_id uuid not null,
  -- The BFS number of the area.
  area integer not null,
  completed_at timestamptz not null,
  changed_at timestamptz not null default now(),
  deleted_at timestamptz,
  foreign key (dog_id, pack_id) references public.dogs (id, pack_id)
);

create unique index completed_areas_one_per_dog_and_area on public.completed_areas (dog_id, area)
  where deleted_at is null;
create index completed_areas_pack_id_changed_at on public.completed_areas (pack_id, changed_at);

create table public.completed_streets (
  id uuid primary key,
  pack_id uuid not null references public.packs (id),
  dog_id uuid not null,
  -- The BFS number of the area of the street.
  area integer not null,
  -- The official name of the street.
  street text not null check (char_length(street) <= 200),
  completed_at timestamptz not null,
  changed_at timestamptz not null default now(),
  deleted_at timestamptz,
  foreign key (dog_id, pack_id) references public.dogs (id, pack_id)
);

create unique index completed_streets_one_per_dog_and_street on public.completed_streets (dog_id, area, street)
  where deleted_at is null;
create index completed_streets_pack_id_changed_at on public.completed_streets (pack_id, changed_at);

create trigger note_change before insert or update on public.completed_areas
  for each row execute function public.note_change();
create trigger note_change before insert or update on public.completed_streets
  for each row execute function public.note_change();

-- Keeps the earliest record of the dog and area. A later new record gets a
-- deletion time, and an earlier new record gives the stored one a deletion
-- time.
create function public.keep_earliest_completed_area() returns trigger
language plpgsql
set search_path = ''
as $$
declare
  stored public.completed_areas;
begin
  if new.deleted_at is not null then
    return new;
  end if;
  select * into stored from public.completed_areas
    where dog_id = new.dog_id and area = new.area and id <> new.id and deleted_at is null
    for update;
  if not found then
    return new;
  end if;
  if (stored.completed_at, stored.id) < (new.completed_at, new.id) then
    new.deleted_at := now();
  else
    update public.completed_areas set deleted_at = now() where id = stored.id;
  end if;
  return new;
end;
$$;

-- The same rule for each dog and street.
create function public.keep_earliest_completed_street() returns trigger
language plpgsql
set search_path = ''
as $$
declare
  stored public.completed_streets;
begin
  if new.deleted_at is not null then
    return new;
  end if;
  select * into stored from public.completed_streets
    where dog_id = new.dog_id and area = new.area and street = new.street and id <> new.id
      and deleted_at is null
    for update;
  if not found then
    return new;
  end if;
  if (stored.completed_at, stored.id) < (new.completed_at, new.id) then
    new.deleted_at := now();
  else
    update public.completed_streets set deleted_at = now() where id = stored.id;
  end if;
  return new;
end;
$$;

revoke execute on function public.keep_earliest_completed_area(), public.keep_earliest_completed_street()
  from public, anon, authenticated;

create trigger keep_earliest before insert or update on public.completed_areas
  for each row execute function public.keep_earliest_completed_area();
create trigger keep_earliest before insert or update on public.completed_streets
  for each row execute function public.keep_earliest_completed_street();

alter table public.completed_areas enable row level security;
alter table public.completed_streets enable row level security;
revoke all on table public.completed_areas, public.completed_streets from anon, authenticated;
grant select, insert, update on table public.completed_areas, public.completed_streets to authenticated;

create policy "A member reads the completed areas of their pack" on public.completed_areas
  for select to authenticated
  using (pack_id = (select public.pack_of_caller()));
create policy "A member uploads a completed area into their pack" on public.completed_areas
  for insert to authenticated
  with check (pack_id = (select public.pack_of_caller()));
create policy "A member changes a completed area of their pack" on public.completed_areas
  for update to authenticated
  using (pack_id = (select public.pack_of_caller()))
  with check (pack_id = (select public.pack_of_caller()));

create policy "A member reads the completed streets of their pack" on public.completed_streets
  for select to authenticated
  using (pack_id = (select public.pack_of_caller()));
create policy "A member uploads a completed street into their pack" on public.completed_streets
  for insert to authenticated
  with check (pack_id = (select public.pack_of_caller()));
create policy "A member changes a completed street of their pack" on public.completed_streets
  for update to authenticated
  using (pack_id = (select public.pack_of_caller()))
  with check (pack_id = (select public.pack_of_caller()));

-- The GPS tracks and the dog photos, in Storage and not in the tables. Each
-- pack has a folder with its ID in each bucket: "<pack ID>/<walk ID>" for a
-- GPS track, and "<pack ID>/<dog ID>.jpg" for a photo.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('tracks', 'tracks', false, 20971520, array['application/octet-stream']),
  ('dog-photos', 'dog-photos', false, 2097152, array['image/jpeg']);

create policy "A member reads the files of their pack" on storage.objects
  for select to authenticated
  using (bucket_id in ('tracks', 'dog-photos')
    and (storage.foldername(name))[1] = (select public.pack_of_caller())::text);
create policy "A member uploads a file into their pack" on storage.objects
  for insert to authenticated
  with check (bucket_id in ('tracks', 'dog-photos')
    and (storage.foldername(name))[1] = (select public.pack_of_caller())::text);
create policy "A member replaces a file of their pack" on storage.objects
  for update to authenticated
  using (bucket_id in ('tracks', 'dog-photos')
    and (storage.foldername(name))[1] = (select public.pack_of_caller())::text)
  with check (bucket_id in ('tracks', 'dog-photos')
    and (storage.foldername(name))[1] = (select public.pack_of_caller())::text);

-- A member deletes the photo of a dog when they remove it on the phone.
create policy "A member deletes a file of their pack" on storage.objects
  for delete to authenticated
  using (bucket_id in ('tracks', 'dog-photos')
    and (storage.foldername(name))[1] = (select public.pack_of_caller())::text);
