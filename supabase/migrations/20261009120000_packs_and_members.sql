-- The pack and the member on the server (ADR 0006, #100).
--
-- A person is a member of at most one pack (ADR 0005), so each account has
-- one member row, which keeps the name of the person and their pack. A person
-- with an account and no pack has a member row without a pack.
--
-- The phones write only what a member may change: the name of the member and
-- the name of the pack. A change of membership goes through a function, so
-- that the server checks the rules.

-- Sets the time of the last change to the time on the server. The last write
-- wins by this time, and a download asks for the rows that changed since.
create function public.note_change() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.changed_at := now();
  return new;
end;
$$;

-- A group of members and the dogs that they walk together. The phone that
-- makes the pack also makes its ID, which is the same on every phone.
create table public.packs (
  id uuid primary key,
  -- The name that a member gave the pack, or empty for the default name.
  name text not null default '' check (char_length(name) <= 100),
  -- The member who made the pack.
  pack_owner_id uuid not null references auth.users (id),
  created_at timestamptz not null default now(),
  changed_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- One row for each account.
create table public.members (
  account_id uuid primary key references auth.users (id) on delete cascade,
  -- The pack of the person, or null for a person in no pack.
  pack_id uuid references public.packs (id),
  -- The name of the member, which Sign in with Apple fills in.
  name text not null default '' check (char_length(name) <= 100),
  -- The time when the person joined their pack, or null.
  joined_at timestamptz,
  changed_at timestamptz not null default now()
);

create index members_pack_id on public.members (pack_id);

create trigger note_change before insert or update on public.packs
  for each row execute function public.note_change();
create trigger note_change before insert or update on public.members
  for each row execute function public.note_change();

-- Each new account gets its member row.
create function public.add_member_for_new_account() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.members (account_id) values (new.id);
  return new;
end;
$$;

create trigger add_member after insert on auth.users
  for each row execute function public.add_member_for_new_account();

-- The accounts from before this migration get their member row too.
insert into public.members (account_id) select id from auth.users;

-- Row-level security: a person reads and writes only their own member row
-- and their own pack.
alter table public.packs enable row level security;
alter table public.members enable row level security;

revoke all on table public.packs, public.members from anon, authenticated;
grant select, update (name) on table public.members to authenticated;
grant select, update (name) on table public.packs to authenticated;

create policy "A person reads their own member row" on public.members
  for select to authenticated
  using (account_id = (select auth.uid()));

create policy "A person changes their own member row" on public.members
  for update to authenticated
  using (account_id = (select auth.uid()))
  with check (account_id = (select auth.uid()));

create policy "A member reads their pack" on public.packs
  for select to authenticated
  using (id = (select pack_id from public.members where account_id = (select auth.uid())));

create policy "A member changes their pack" on public.packs
  for update to authenticated
  using (id = (select pack_id from public.members where account_id = (select auth.uid())))
  with check (id = (select pack_id from public.members where account_id = (select auth.uid())));

revoke execute on function public.note_change(), public.add_member_for_new_account() from public, anon, authenticated;

-- Makes the pack of the phone on the server, with the calling person as its
-- pack owner and member. A person who is already a member of this pack
-- changes nothing, so the phone can call it again after a lost answer. A
-- person in another pack cannot make a pack (ADR 0005).
create function public.create_pack(pack_id uuid, pack_name text, pack_created_at timestamptz)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  current_pack uuid;
begin
  if caller is null then
    raise exception 'Only a signed-in person can make a pack.' using errcode = '42501';
  end if;
  select members.pack_id into current_pack from public.members where account_id = caller for update;
  if not found then
    raise exception 'The account has no member row.' using errcode = 'P0002';
  end if;
  if current_pack = create_pack.pack_id then
    return;
  end if;
  if current_pack is not null then
    raise exception 'The person is already a member of a pack.' using errcode = 'P0001';
  end if;
  insert into public.packs (id, name, pack_owner_id, created_at)
    values (create_pack.pack_id, pack_name, caller, pack_created_at);
  update public.members set pack_id = create_pack.pack_id, joined_at = now() where account_id = caller;
end;
$$;

revoke execute on function public.create_pack(uuid, text, timestamptz) from public, anon;
grant execute on function public.create_pack(uuid, text, timestamptz) to authenticated;
