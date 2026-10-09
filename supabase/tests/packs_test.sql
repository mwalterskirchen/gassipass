-- The pack and the member on the server (#100), with the row-level security
-- that limits each person to their own pack and their own member row.
-- Run with `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

-- Two accounts, as Sign in with Apple makes them.
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'anna@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'ben@example.com');

-- Acts as the account with the ID, like a request with its access token.
create function pg_temp.act_as(account uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', account, 'role', 'authenticated')::text, true);
$$;

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select results_eq(
  $$ select name, pack_id from public.members $$,
  $$ values ('', null::uuid) $$,
  'A new account has a member row with an empty name and no pack'
);

select lives_ok(
  $$ select public.create_pack('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Bellos Rudel', '2026-10-01 08:00+02') $$,
  'A person in no pack makes their pack'
);
select results_eq(
  $$ select id, name, owner_id, created_at from public.packs $$,
  $$ values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, 'Bellos Rudel',
             '11111111-1111-1111-1111-111111111111'::uuid, '2026-10-01 08:00+02'::timestamptz) $$,
  'The person who makes the pack is its pack owner'
);
select results_eq(
  $$ select pack_id, joined_at is not null from public.members $$,
  $$ values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, true) $$,
  'The person who makes the pack is its member'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is_empty(
  $$ select * from public.packs $$,
  'A second account cannot read the pack'
);

select is_empty(
  $$ update public.packs set name = 'Bens Rudel' returning id $$,
  'A second account cannot rename the pack'
);
select results_eq(
  $$ select account_id from public.members $$,
  $$ values ('22222222-2222-2222-2222-222222222222'::uuid) $$,
  'A second account reads only its own member row'
);
select throws_ok(
  $$ select public.create_pack('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Bens Rudel', now()) $$,
  '23505', null,
  'A second account cannot take over the pack by its ID'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select lives_ok(
  $$ update public.members set name = 'Anna' $$,
  'A member changes their name'
);
select lives_ok(
  $$ update public.packs set name = 'Annas Rudel' $$,
  'A member renames their pack'
);
select throws_ok(
  $$ update public.members set pack_id = null $$,
  '42501', null,
  'A member cannot leave their pack by a write to their member row'
);
select throws_ok(
  $$ update public.packs set owner_id = '22222222-2222-2222-2222-222222222222' $$,
  '42501', null,
  'A member cannot give the pack another pack owner'
);
select throws_ok(
  $$ select public.create_pack('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Zweites Rudel', now()) $$,
  'P0001', 'The person is already a member of a pack.',
  'A member of a pack cannot make a second pack'
);

set local role anon;
select throws_ok(
  $$ select * from public.packs $$,
  '42501', null,
  'A person without an account reads no pack'
);

reset role;
select results_eq(
  $$ select p.name, m.name from public.packs p join public.members m on m.pack_id = p.id
     where p.id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' $$,
  $$ values ('Annas Rudel', 'Anna') $$,
  'Only the changes of the pack owner reached the pack'
);

select * from finish();
rollback;
