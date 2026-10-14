-- The pack owner removes a member, and a member leaves the pack (ADR 0005
-- and ADR 0006, #106).
--
-- Only the pack owner removes a member, and the pack owner can neither
-- leave the pack nor remove themselves. The person who is out of the pack
-- is in no pack, so row-level security keeps them out of the pack. The walks
-- that they recorded stay with the dogs, with their member name.
--
-- The server notes each departure, so that each phone of the person learns
-- that they are out of the pack, and deletes the data of the pack. A phone
-- whose pack the server does not know uploads it instead.

create table public.departures (
  account_id uuid not null references auth.users (id) on delete cascade,
  pack_id uuid not null references public.packs (id),
  -- The time of the last departure of the person from the pack.
  left_at timestamptz not null default now(),
  primary key (account_id, pack_id)
);

-- Row-level security without a policy: no phone reads or writes the table
-- directly.
alter table public.departures enable row level security;
revoke all on table public.departures from anon, authenticated;

-- Takes the person out of their pack, and notes the departure. The caller
-- holds the lock of the member row.
create function public.take_out_of_pack(person uuid) returns void
language sql
set search_path = ''
as $$
  insert into public.departures (account_id, pack_id)
    select account_id, pack_id from public.members where account_id = person and pack_id is not null
    on conflict (account_id, pack_id) do update set left_at = now();
  update public.members set pack_id = null, joined_at = null where account_id = person;
$$;

revoke execute on function public.take_out_of_pack(uuid) from public, anon, authenticated;

-- Takes the calling person out of their pack. The pack owner cannot leave.
-- A person in no pack changes nothing, so the phone can call it again after
-- a lost answer.
create function public.leave_pack() returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  pack uuid;
begin
  if caller is null then
    raise exception 'Only a signed-in person can leave a pack.' using errcode = '42501';
  end if;
  select members.pack_id into pack from public.members where account_id = caller for update;
  if not found then
    raise exception 'The account has no member row.' using errcode = 'P0002';
  end if;
  if pack is null then
    return;
  end if;
  perform from public.packs where id = pack and pack_owner_id = caller;
  if found then
    raise exception 'The pack owner cannot leave the pack.' using errcode = '42501';
  end if;
  perform public.take_out_of_pack(caller);
end;
$$;

-- Takes the member out of the pack of the calling person. Only the pack
-- owner removes a member, and not themselves. A member who has left the
-- pack already changes nothing, so the phone can call it again after a lost
-- answer.
create function public.remove_member(member_id uuid) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  pack uuid;
begin
  select packs.id into pack from public.members
    join public.packs on packs.id = members.pack_id and packs.deleted_at is null
    where members.account_id = caller and packs.pack_owner_id = caller;
  if not found then
    raise exception 'Only the pack owner removes a member.' using errcode = '42501';
  end if;
  if member_id = caller then
    raise exception 'The pack owner cannot remove themselves.' using errcode = '42501';
  end if;
  perform from public.members where account_id = member_id and members.pack_id = pack for update;
  if found then
    perform public.take_out_of_pack(member_id);
    return;
  end if;
  perform from public.departures where account_id = member_id and departures.pack_id = pack;
  if not found then
    raise exception 'The person is no member of the pack.' using errcode = 'P0002';
  end if;
end;
$$;

-- Whether the calling person has left the pack, or the pack owner removed
-- them, and they are not in it again.
create function public.has_left_pack(pack_id uuid) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select from public.departures
    where departures.account_id = (select auth.uid()) and departures.pack_id = has_left_pack.pack_id
  ) and has_left_pack.pack_id is distinct from (select public.pack_of_caller());
$$;

-- The members of the pack of the calling person, now with the ID of each
-- member, so that the pack owner can remove one.
drop function public.pack_members();
create function public.pack_members()
returns table (id uuid, name text, is_pack_owner boolean, is_caller boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select members.account_id, members.name, members.account_id = packs.pack_owner_id,
         members.account_id = (select auth.uid())
  from public.members
  join public.packs on packs.id = members.pack_id and packs.deleted_at is null
  where members.pack_id = (select public.pack_of_caller())
  order by members.account_id = packs.pack_owner_id desc, members.joined_at, members.account_id;
$$;

revoke execute on function public.leave_pack(), public.remove_member(uuid), public.has_left_pack(uuid),
  public.pack_members() from public, anon;
grant execute on function public.leave_pack(), public.remove_member(uuid), public.has_left_pack(uuid),
  public.pack_members() to authenticated;
