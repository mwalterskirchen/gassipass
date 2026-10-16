-- The steps of the area stamp (#141): the entry stamp and the steps at 25%,
-- 50% and 75%. The earliest record of each dog, area and step wins, only the
-- members of the pack read and write the records, and the records move and
-- go with the pack. Run with `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Anna has a pack with Bello. Ben is the only member of his pack, with Luna.
-- Carl is the only member of his pack, with Rex.
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'anna@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'ben@example.com'),
  ('33333333-3333-3333-3333-333333333333', 'carl@example.com');

-- Acts as the account with the ID, like a request with its access token.
create function pg_temp.act_as(account uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', account, 'role', 'authenticated')::text, true);
$$;

create temporary table tokens (name text primary key, token text not null);
grant all on tokens to authenticated;

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select public.create_pack('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Annas Rudel', now());
insert into public.dogs (id, pack_id, name) values
  ('a0000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Bello');
insert into tokens values ('anna', public.create_invitation());

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select public.create_pack('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Bens Rudel', now());
insert into public.dogs (id, pack_id, name) values
  ('b0000000-0000-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Luna');

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select public.create_pack('cccccccc-cccc-cccc-cccc-cccccccccccc', 'Carls Rudel', now());
insert into public.dogs (id, pack_id, name) values
  ('c0000000-0000-0000-0000-000000000001', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Rex');
insert into public.area_steps (id, pack_id, dog_id, area, step, reached_at) values
  ('c5000000-0000-0000-0000-000000000001', 'cccccccc-cccc-cccc-cccc-cccccccccccc',
   'c0000000-0000-0000-0000-000000000001', 243, 0, '2026-10-01 08:10+02');

-- The earliest record wins

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select lives_ok(
  $$ insert into public.area_steps (id, pack_id, dog_id, area, step, reached_at)
     values ('a5000000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'a0000000-0000-0000-0000-000000000001', 243, 25, '2026-10-02 09:00+02') $$,
  'A member uploads a step of a dog of their pack'
);
select lives_ok(
  $$ insert into public.area_steps (id, pack_id, dog_id, area, step, reached_at)
     values ('a5000000-0000-0000-0000-000000000003', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'a0000000-0000-0000-0000-000000000001', 243, 25, '2026-10-01 09:00+02') $$,
  'Another phone uploads an earlier record of the same step'
);
select lives_ok(
  $$ insert into public.area_steps (id, pack_id, dog_id, area, step, reached_at)
     values ('a5000000-0000-0000-0000-000000000004', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'a0000000-0000-0000-0000-000000000001', 243, 25, '2026-10-03 09:00+02') $$,
  'A third phone uploads a later record of the same step'
);
select results_eq(
  $$ select id, reached_at from public.area_steps where step = 25 and deleted_at is null $$,
  $$ values ('a5000000-0000-0000-0000-000000000003'::uuid, '2026-10-01 09:00+02'::timestamptz) $$,
  'Only the earliest record of the dog, area and step stays'
);
select is(
  (select count(*) from public.area_steps where step = 25 and deleted_at is not null), 2::bigint,
  'The other records stay with a deletion time'
);
select lives_ok(
  $$ insert into public.area_steps (id, pack_id, dog_id, area, step, reached_at)
     values ('a5000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'a0000000-0000-0000-0000-000000000001', 243, 25, '2026-10-01 09:00+02') $$,
  'A record with the same date and a smaller ID uploads'
);
select results_eq(
  $$ select id from public.area_steps where step = 25 and deleted_at is null $$,
  $$ values ('a5000000-0000-0000-0000-000000000001'::uuid) $$,
  'Of two records with the same date, the one with the smaller ID wins'
);
select lives_ok(
  $$ insert into public.area_steps (id, pack_id, dog_id, area, step, reached_at)
     values ('a5000000-0000-0000-0000-000000000005', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'a0000000-0000-0000-0000-000000000001', 243, 0, '2026-10-01 08:00+02'),
            ('a5000000-0000-0000-0000-000000000006', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'a0000000-0000-0000-0000-000000000001', 243, 50, '2026-10-04 09:00+02'),
            ('a5000000-0000-0000-0000-000000000007', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'a0000000-0000-0000-0000-000000000001', 242, 0, '2026-10-04 09:00+02') $$,
  'Other steps and other areas have records of their own'
);
select is(
  (select count(*) from public.area_steps where deleted_at is null), 4::bigint,
  'Each dog, area and step has one record'
);
select throws_ok(
  $$ insert into public.area_steps (id, pack_id, dog_id, area, step, reached_at)
     values ('a5000000-0000-0000-0000-000000000008', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'a0000000-0000-0000-0000-000000000001', 243, 95, '2026-10-05 09:00+02') $$,
  '23514', null,
  'The full stamp is a completed area, not a step'
);

-- Row-level security

select throws_ok(
  $$ insert into public.area_steps (id, pack_id, dog_id, area, step, reached_at)
     values ('a5000000-0000-0000-0000-000000000009', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
             'b0000000-0000-0000-0000-000000000001', 243, 0, '2026-10-01 09:00+02') $$,
  '42501', null,
  'A member cannot upload a step into another pack'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is_empty(
  $$ select * from public.area_steps $$,
  'A member of another pack cannot read the steps'
);
update public.area_steps set reached_at = '2026-01-01';

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select count(*) from public.area_steps where reached_at = '2026-01-01'), 0::bigint,
  'A member of another pack cannot change the steps'
);

-- A step of a dog that moves into another pack moves with it

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');

select lives_ok(
  $$ insert into public.area_steps (id, pack_id, dog_id, area, step, reached_at)
     values ('b5000000-0000-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
             'b0000000-0000-0000-0000-000000000001', 243, 75, '2026-10-01 09:00+02') $$,
  'The only member of a pack uploads a step'
);
select is(
  public.join_pack((select token from tokens where name = 'anna')), 'joined',
  'The only member joins another pack with their dog'
);
select results_eq(
  $$ select id, pack_id from public.area_steps where dog_id = 'b0000000-0000-0000-0000-000000000001' $$,
  $$ values ('b5000000-0000-0000-0000-000000000001'::uuid, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid) $$,
  'The step of the dog moves into the new pack'
);
select throws_ok(
  $$ insert into public.area_steps (id, pack_id, dog_id, area, step, reached_at)
     values ('b5000000-0000-0000-0000-000000000002', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
             'b0000000-0000-0000-0000-000000000001', 243, 50, '2026-10-01 09:00+02') $$,
  null, null,
  'A step cannot upload into the pack that disappeared'
);

-- The steps go with the account of the only member of a pack

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select lives_ok(
  $$ select public.delete_account() $$,
  'The only member of a pack deletes their account'
);
reset role;
select is_empty(
  $$ select * from public.area_steps where pack_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc' $$,
  'The steps of the pack are deleted with it'
);

select * from finish();
rollback;
