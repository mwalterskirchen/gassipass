-- The invitation to a pack and the join (#104). The server checks every
-- rule: only the pack owner invites, an invitation works once and expires
-- after 7 days, and a person is a member of at most one pack (ADR 0005).
-- Run with `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Anna has a pack. Dora has a pack with Eva. Ben and Carl have no pack.
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'anna@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'ben@example.com'),
  ('33333333-3333-3333-3333-333333333333', 'carl@example.com'),
  ('44444444-4444-4444-4444-444444444444', 'dora@example.com'),
  ('55555555-5555-5555-5555-555555555555', 'eva@example.com');

-- Acts as the account with the ID, like a request with its access token.
create function pg_temp.act_as(account uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', account, 'role', 'authenticated')::text, true);
$$;

-- The tokens of the tests, which only the test reads.
create temporary table tokens (name text primary key, token text not null);
grant all on tokens to authenticated;

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
update public.members set name = 'Anna';
select public.create_pack('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Annas Rudel', now());
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
update public.members set name = 'Ben';
select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select public.create_pack('dddddddd-dddd-dddd-dddd-dddddddddddd', 'Doras Rudel', now());

-- The invitation

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into tokens values ('first', public.create_invitation());
select matches(
  (select token from tokens where name = 'first'),
  '^[A-Za-z0-9_-]{43}$',
  'The pack owner gets a token for the link'
);
insert into tokens values ('second', public.create_invitation());
select isnt(
  (select token from tokens where name = 'first'),
  (select token from tokens where name = 'second'),
  'Each invitation has its own token'
);
select throws_ok(
  $$ select * from public.invitations $$,
  '42501', null,
  'A member cannot read the invitations'
);

select results_eq(
  $$ select state from public.check_invitation((select token from tokens where name = 'first')) $$,
  $$ values ('member') $$,
  'The pack owner who opens their own invitation is a member already'
);
select results_eq(
  $$ select public.join_pack((select token from tokens where name = 'first')) $$,
  $$ values ('member') $$,
  'The pack owner who joins with their own invitation joins nothing'
);

-- The join

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select results_eq(
  $$ select state, pack_id, pack_name, pack_owner_name
     from public.check_invitation((select token from tokens where name = 'first')) $$,
  $$ values ('open', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, 'Annas Rudel', 'Anna') $$,
  'A person in no pack sees the pack and its pack owner before the join'
);
select is_empty(
  $$ select * from public.packs $$,
  'A person who has only opened the invitation cannot read the pack'
);
select results_eq(
  $$ select public.join_pack((select token from tokens where name = 'first')) $$,
  $$ values ('joined') $$,
  'A person in no pack joins'
);
select results_eq(
  $$ select pack_id, joined_at is not null from public.members $$,
  $$ values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, true) $$,
  'The person who joined is a member of the pack'
);
select results_eq(
  $$ select name from public.packs $$,
  $$ values ('Annas Rudel') $$,
  'The new member reads the pack'
);
select results_eq(
  $$ select name, is_pack_owner, is_caller from public.pack_members() $$,
  $$ values ('Anna', true, false), ('Ben', false, true) $$,
  'A member sees the members of the pack, the pack owner first'
);
select throws_ok(
  $$ select public.create_invitation() $$,
  '42501', null,
  'A member who is not the pack owner cannot invite'
);
select results_eq(
  $$ select state from public.check_invitation((select token from tokens where name = 'first')) $$,
  $$ values ('member') $$,
  'The new member who opens the invitation again is a member already'
);

-- A used invitation

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select results_eq(
  $$ select state from public.check_invitation((select token from tokens where name = 'first')) $$,
  $$ values ('used') $$,
  'A used invitation shows that it is used'
);
select results_eq(
  $$ select public.join_pack((select token from tokens where name = 'first')) $$,
  $$ values ('used') $$,
  'A used invitation joins nobody'
);
select results_eq(
  $$ select pack_id from public.members $$,
  $$ values (null::uuid) $$,
  'The person with a used invitation is in no pack'
);
select is_empty(
  $$ select * from public.pack_members() $$,
  'A person in no pack sees no members'
);

-- An expired invitation

reset role;
update public.invitations set expires_at = now() - interval '1 second'
  where token_hash = extensions.digest((select token from tokens where name = 'second'), 'sha256');
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select results_eq(
  $$ select state from public.check_invitation((select token from tokens where name = 'second')) $$,
  $$ values ('expired') $$,
  'An expired invitation shows that it has expired'
);
select results_eq(
  $$ select public.join_pack((select token from tokens where name = 'second')) $$,
  $$ values ('expired') $$,
  'An expired invitation joins nobody'
);
reset role;
select results_eq(
  $$ select expires_at - created_at from public.invitations
     where token_hash = extensions.digest((select token from tokens where name = 'first'), 'sha256') $$,
  $$ values (interval '7 days') $$,
  'An invitation expires 7 days after the pack owner made it'
);

-- A member of a pack with other members

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
insert into tokens values ('dora', public.create_invitation());
select pg_temp.act_as('55555555-5555-5555-5555-555555555555');
select public.join_pack((select token from tokens where name = 'dora'));
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into tokens values ('third', public.create_invitation());
select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select results_eq(
  $$ select state from public.check_invitation((select token from tokens where name = 'third')) $$,
  $$ values ('in_other_pack') $$,
  'A member of another pack sees that they cannot join'
);
select results_eq(
  $$ select public.join_pack((select token from tokens where name = 'third')) $$,
  $$ values ('in_other_pack') $$,
  'A member of another pack does not join'
);
select results_eq(
  $$ select pack_id from public.members $$,
  $$ values ('dddddddd-dddd-dddd-dddd-dddddddddddd'::uuid) $$,
  'The member of another pack stays in their pack'
);
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select results_eq(
  $$ select public.join_pack((select token from tokens where name = 'third')) $$,
  $$ values ('joined') $$,
  'An invitation that a member of another pack opened still works'
);

-- An unknown token, and a person without an account

select results_eq(
  $$ select state, pack_id from public.check_invitation('not-a-token') $$,
  $$ values ('unknown', null::uuid) $$,
  'An unknown token shows that the invitation does not exist'
);
select results_eq(
  $$ select public.join_pack('not-a-token') $$,
  $$ values ('unknown') $$,
  'An unknown token joins nobody'
);
set local role anon;
select throws_ok(
  $$ select * from public.check_invitation((select token from tokens where name = 'third')) $$,
  '42501', null,
  'A person without an account cannot open an invitation'
);

select * from finish();
rollback;
