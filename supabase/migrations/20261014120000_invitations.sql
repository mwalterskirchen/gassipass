-- The invitation to a pack and the join (ADR 0006, #104).
--
-- The pack owner makes an invitation, and the share sheet sends it as the
-- link https://gassipass.ch/invitation/<token>. The token is the secret of
-- the link. The server keeps only its hash, so the table does not give a
-- working link to anybody who reads it.
--
-- An invitation works once and expires after 7 days. A person is a member
-- of at most one pack (ADR 0005), so a person in another pack cannot join.
-- The phones reach the invitations only through the functions below, which
-- check every rule.

create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  pack_id uuid not null references public.packs (id),
  -- The SHA-256 hash of the token in the link.
  token_hash bytea not null unique,
  -- The pack owner who made the invitation.
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  -- The time of the join, or null for an invitation that nobody used.
  used_at timestamptz,
  used_by uuid references auth.users (id) on delete set null
);

create index invitations_pack_id on public.invitations (pack_id);

-- Row-level security without a policy: no phone reads or writes the table
-- directly.
alter table public.invitations enable row level security;
revoke all on table public.invitations from anon, authenticated;

-- Makes an invitation to the pack of the calling person, and returns its
-- token. Only the pack owner invites.
create function public.create_invitation() returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  pack uuid;
  token text;
begin
  select packs.id into pack from public.members
    join public.packs on packs.id = members.pack_id and packs.deleted_at is null
    where members.account_id = caller and packs.pack_owner_id = caller;
  if not found then
    raise exception 'Only the pack owner invites.' using errcode = '42501';
  end if;
  -- 32 random bytes in base64url, without the padding.
  token := translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/=', '-_');
  insert into public.invitations (pack_id, token_hash, created_by)
    values (pack, extensions.digest(token, 'sha256'), caller);
  return token;
end;
$$;

-- Whether the person can join with the invitation:
--   'open'          the person can join.
--   'member'        the person is a member of the pack already, for example
--                   the pack owner who opens their own invitation.
--   'used'          somebody joined with the invitation.
--   'expired'       the invitation is older than 7 days.
--   'in_other_pack' the person is a member of another pack (ADR 0005).
create function public.state_of_invitation(invitation public.invitations, person uuid) returns text
language sql
stable
set search_path = ''
as $$
  select case
    when members.pack_id = invitation.pack_id then 'member'
    when invitation.used_at is not null then 'used'
    when invitation.expires_at <= now() then 'expired'
    when members.pack_id is not null then 'in_other_pack'
    else 'open'
  end
  from public.members where members.account_id = person;
$$;

-- The invitation with the token, if its pack exists.
create function public.invitation_with_token(token text) returns public.invitations
language sql
stable
set search_path = ''
as $$
  select invitations.* from public.invitations
    join public.packs on packs.id = invitations.pack_id and packs.deleted_at is null
    where invitations.token_hash = extensions.digest(token, 'sha256');
$$;

revoke execute on function public.state_of_invitation(public.invitations, uuid),
  public.invitation_with_token(text) from public, anon, authenticated;

-- What the app shows before the join: whether the calling person can join
-- (see `state_of_invitation`), and the pack with the name of its pack
-- owner. An unknown token has the state 'unknown' and no pack.
create function public.check_invitation(token text)
returns table (state text, pack_id uuid, pack_name text, pack_owner_name text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  invitation public.invitations;
begin
  if caller is null then
    raise exception 'Only a signed-in person can open an invitation.' using errcode = '42501';
  end if;
  perform from public.members where account_id = caller;
  if not found then
    raise exception 'The account has no member row.' using errcode = 'P0002';
  end if;
  invitation := public.invitation_with_token(token);
  if invitation.id is null then
    return query select 'unknown', null::uuid, null::text, null::text;
    return;
  end if;
  return query
    select public.state_of_invitation(invitation, caller), packs.id, packs.name, coalesce(pack_owners.name, '')
    from public.packs
    left join public.members pack_owners on pack_owners.account_id = packs.pack_owner_id
    where packs.id = invitation.pack_id;
end;
$$;

-- Makes the calling person a member of the pack of the invitation, and uses
-- up the invitation. It returns 'joined', or the state of the invitation
-- that keeps the person out (see `state_of_invitation`), or 'unknown'.
create function public.join_pack(token text) returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  invitation public.invitations;
  state text;
begin
  if caller is null then
    raise exception 'Only a signed-in person can join a pack.' using errcode = '42501';
  end if;
  invitation := public.invitation_with_token(token);
  if invitation.id is null then
    return 'unknown';
  end if;
  -- The locks keep a second join with the same invitation, and a pack that
  -- the person makes at the same time, out until this join ends.
  select * into invitation from public.invitations where id = invitation.id for update;
  perform from public.members where account_id = caller for update;
  if not found then
    raise exception 'The account has no member row.' using errcode = 'P0002';
  end if;
  state := public.state_of_invitation(invitation, caller);
  if state <> 'open' then
    return state;
  end if;
  update public.invitations set used_at = now(), used_by = caller where id = invitation.id;
  update public.members set pack_id = invitation.pack_id, joined_at = now() where account_id = caller;
  return 'joined';
end;
$$;

-- The members of the pack of the calling person, the pack owner first and
-- then in the order of their join. A person in no pack gets no rows.
create function public.pack_members()
returns table (name text, is_pack_owner boolean, is_caller boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select members.name, members.account_id = packs.pack_owner_id,
         members.account_id = (select auth.uid())
  from public.members
  join public.packs on packs.id = members.pack_id and packs.deleted_at is null
  where members.pack_id = (select public.pack_of_caller())
  order by members.account_id = packs.pack_owner_id desc, members.joined_at, members.account_id;
$$;

revoke execute on function public.create_invitation(), public.check_invitation(text), public.join_pack(text),
  public.pack_members() from public, anon;
grant execute on function public.create_invitation(), public.check_invitation(text), public.join_pack(text),
  public.pack_members() to authenticated;
