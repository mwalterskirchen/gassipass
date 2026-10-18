-- The weekly goals (#144). The server keeps one set for each dog and week,
-- keeps the earliest finish of each goal, refuses a second swap, lets only
-- the members of the pack read and write the sets, and moves and deletes
-- the sets with the pack. Run with `supabase test db`.
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

-- Uploads a set of the dog for the week, as the phone does: an upsert on
-- the ID with every column.
create function pg_temp.upload(
  set_id uuid, pack uuid, dog uuid, week date, kinds text[], targets double precision[],
  finished timestamptz[], swapped integer
) returns void language sql as $$
  insert into public.weekly_goals (
    id, pack_id, dog_id, week_start,
    goal1_kind, goal1_target, goal1_area, goal1_street, goal1_ring, goal1_finished_at,
    goal2_kind, goal2_target, goal2_area, goal2_street, goal2_ring, goal2_finished_at,
    goal3_kind, goal3_target, goal3_area, goal3_street, goal3_ring, goal3_finished_at,
    swapped_slot)
  values (
    set_id, pack, dog, week,
    kinds[1], targets[1], null, null, null, finished[1],
    kinds[2], targets[2], null, null, null, finished[2],
    kinds[3], targets[3], null, null, null, finished[3],
    swapped)
  on conflict (id) do update set
    goal1_kind = excluded.goal1_kind, goal1_target = excluded.goal1_target,
    goal1_finished_at = excluded.goal1_finished_at,
    goal2_kind = excluded.goal2_kind, goal2_target = excluded.goal2_target,
    goal2_finished_at = excluded.goal2_finished_at,
    goal3_kind = excluded.goal3_kind, goal3_target = excluded.goal3_target,
    goal3_finished_at = excluded.goal3_finished_at,
    swapped_slot = excluded.swapped_slot;
$$;

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
select pg_temp.upload(
  'c7000000-0000-0000-0000-000000000001', 'cccccccc-cccc-cccc-cccc-cccccccccccc',
  'c0000000-0000-0000-0000-000000000001', '2026-10-19',
  array['distance', 'street', 'step'], array[1000, null, null]::double precision[],
  array[null, null, null]::timestamptz[], null);

-- One set for each dog and week

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select lives_ok(
  $$ select pg_temp.upload(
       'a7000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
       'a0000000-0000-0000-0000-000000000001', '2026-10-19',
       array['distance', 'new_length', 'new_area'], array[5000, 1000, null]::double precision[],
       array[null, null, null]::timestamptz[], null) $$,
  'A member uploads the set of a dog of their pack'
);
select throws_ok(
  $$ select pg_temp.upload(
       'a7000000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
       'a0000000-0000-0000-0000-000000000001', '2026-10-19',
       array['refresh', 'new_length', 'new_area'], array[1000, 1000, null]::double precision[],
       array[null, null, null]::timestamptz[], null) $$,
  '23505', null,
  'Another phone cannot upload a second set for the same dog and week'
);
select lives_ok(
  $$ select pg_temp.upload(
       'a7000000-0000-0000-0000-000000000003', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
       'a0000000-0000-0000-0000-000000000001', '2026-10-26',
       array['distance', 'new_length', 'new_area'], array[5000, 1000, null]::double precision[],
       array[null, null, null]::timestamptz[], null) $$,
  'The next week has a set of its own'
);
select throws_ok(
  $$ select pg_temp.upload(
       'a7000000-0000-0000-0000-000000000004', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
       'a0000000-0000-0000-0000-000000000001', '2026-10-21',
       array['distance', 'new_length', 'new_area'], array[5000, 1000, null]::double precision[],
       array[null, null, null]::timestamptz[], null) $$,
  '23514', null,
  'A week starts on a Monday'
);
select throws_ok(
  $$ select pg_temp.upload(
       'a7000000-0000-0000-0000-000000000004', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
       'a0000000-0000-0000-0000-000000000001', '2026-11-02',
       array['distance', 'climb', 'new_area'], array[5000, 1000, null]::double precision[],
       array[null, null, null]::timestamptz[], null) $$,
  '23514', null,
  'A goal has one of the six kinds'
);

-- The earliest finish of each goal stays

select pg_temp.upload(
  'a7000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'a0000000-0000-0000-0000-000000000001', '2026-10-19',
  array['distance', 'new_length', 'new_area'], array[5000, 1000, null]::double precision[],
  array['2026-10-21 18:00+02', null, null]::timestamptz[], null);
select pg_temp.upload(
  'a7000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'a0000000-0000-0000-0000-000000000001', '2026-10-19',
  array['distance', 'new_length', 'new_area'], array[5000, 1000, null]::double precision[],
  array['2026-10-20 18:00+02', '2026-10-22 09:00+02', null]::timestamptz[], null);
select pg_temp.upload(
  'a7000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'a0000000-0000-0000-0000-000000000001', '2026-10-19',
  array['distance', 'new_length', 'new_area'], array[5000, 1000, null]::double precision[],
  array['2026-10-23 18:00+02', null, null]::timestamptz[], null);
select results_eq(
  $$ select goal1_finished_at, goal2_finished_at, goal3_finished_at from public.weekly_goals
     where id = 'a7000000-0000-0000-0000-000000000001' $$,
  $$ values ('2026-10-20 18:00+02'::timestamptz, '2026-10-22 09:00+02'::timestamptz, null::timestamptz) $$,
  'Each goal keeps the earliest time at which it was finished, also after a deleted walk'
);

-- One swap for each set

select lives_ok(
  $$ select pg_temp.upload(
       'a7000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
       'a0000000-0000-0000-0000-000000000001', '2026-10-19',
       array['distance', 'new_length', 'distance'], array[5000, 1000, 15000]::double precision[],
       array['2026-10-20 18:00+02', '2026-10-22 09:00+02', null]::timestamptz[], 3) $$,
  'A member swaps one goal'
);
select results_eq(
  $$ select goal3_kind, goal3_target, swapped_slot from public.weekly_goals
     where id = 'a7000000-0000-0000-0000-000000000001' $$,
  $$ values ('distance', 15000::double precision, 3) $$,
  'The set keeps the swapped goal and its slot'
);
select throws_ok(
  $$ select pg_temp.upload(
       'a7000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
       'a0000000-0000-0000-0000-000000000001', '2026-10-19',
       array['refresh', 'new_length', 'distance'], array[1000, 1000, 15000]::double precision[],
       array[null, '2026-10-22 09:00+02', null]::timestamptz[], 1) $$,
  '23514', null,
  'A second swap is refused'
);
select throws_ok(
  $$ select pg_temp.upload(
       'a7000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
       'a0000000-0000-0000-0000-000000000001', '2026-10-19',
       array['distance', 'new_length', 'new_area'], array[5000, 1000, null]::double precision[],
       array['2026-10-20 18:00+02', '2026-10-22 09:00+02', null]::timestamptz[], null) $$,
  '23514', null,
  'A phone that has not seen the swap cannot undo it'
);
select throws_ok(
  $$ select pg_temp.upload(
       'a7000000-0000-0000-0000-000000000003', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
       'a0000000-0000-0000-0000-000000000001', '2026-10-26',
       array['refresh', 'refresh', 'new_area'], array[1000, 1000, null]::double precision[],
       array[null, null, null]::timestamptz[], 1) $$,
  '23514', null,
  'A swap changes only its own slot'
);
select lives_ok(
  $$ select pg_temp.upload(
       'a7000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
       'a0000000-0000-0000-0000-000000000001', '2026-10-19',
       array['distance', 'new_length', 'distance'], array[5000, 1000, 15000]::double precision[],
       array[null, null, '2026-10-24 12:00+02']::timestamptz[], 3) $$,
  'A finish uploads after the swap'
);
select results_eq(
  $$ select goal1_finished_at, goal2_finished_at, goal3_finished_at from public.weekly_goals
     where id = 'a7000000-0000-0000-0000-000000000001' $$,
  $$ values ('2026-10-20 18:00+02'::timestamptz, '2026-10-22 09:00+02'::timestamptz,
             '2026-10-24 12:00+02'::timestamptz) $$,
  'The finishes before the swap stay'
);

-- Row-level security

select throws_ok(
  $$ select pg_temp.upload(
       'a7000000-0000-0000-0000-000000000005', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
       'b0000000-0000-0000-0000-000000000001', '2026-10-19',
       array['distance', 'new_length', 'new_area'], array[5000, 1000, null]::double precision[],
       array[null, null, null]::timestamptz[], null) $$,
  '42501', null,
  'A member cannot upload a set into another pack'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is_empty(
  $$ select * from public.weekly_goals $$,
  'A member of another pack cannot read the sets'
);
update public.weekly_goals set goal1_finished_at = '2026-01-01';

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select count(*) from public.weekly_goals where goal1_finished_at = '2026-01-01'), 0::bigint,
  'A member of another pack cannot change the sets'
);

-- The sets of a dog that moves into another pack move with it

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select lives_ok(
  $$ select pg_temp.upload(
       'b7000000-0000-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
       'b0000000-0000-0000-0000-000000000001', '2026-10-19',
       array['distance', 'new_length', 'new_area'], array[5000, 1000, null]::double precision[],
       array[null, null, null]::timestamptz[], null) $$,
  'The only member of a pack uploads a set'
);
select is(
  public.join_pack((select token from tokens where name = 'anna')), 'joined',
  'The only member joins another pack with their dog'
);
select results_eq(
  $$ select id, pack_id from public.weekly_goals where dog_id = 'b0000000-0000-0000-0000-000000000001' $$,
  $$ values ('b7000000-0000-0000-0000-000000000001'::uuid, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid) $$,
  'The set of the dog moves into the new pack'
);

-- The sets go with the account of the only member of a pack

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select lives_ok(
  $$ select public.delete_account() $$,
  'The only member of a pack deletes their account'
);
reset role;
select is_empty(
  $$ select * from public.weekly_goals where pack_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc' $$,
  'The sets of the pack are deleted with it'
);

select * from finish();
rollback;
