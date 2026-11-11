-- The home base of the pack and the ring stamps (#142). Only the members of
-- the pack read and change the home base, and the last write wins. The earliest ring stamp of each dog, ring and centre wins,
-- only the members of the pack read and write the stamps, and the stamps
-- move and go with the pack. Run with `supabase test db`.
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
insert into public.completed_rings
  (id, pack_id, dog_id, ring, radius_m, centre_latitude, centre_longitude, completed_at) values
  ('c6000000-0000-0000-0000-000000000001', 'cccccccc-cccc-cccc-cccc-cccccccccccc',
   'c0000000-0000-0000-0000-000000000001', 1, 250, 47.4, 8.4, '2026-10-01 08:10+02');

-- The home base

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select home_latitude from public.packs where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), null,
  'A new pack has no home base'
);
select lives_ok(
  $$ update public.packs set home_latitude = 47.4, home_longitude = 8.4, home_set_at = '2026-10-02 09:00+02'
     where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' $$,
  'A member sets the home base of their pack'
);
select results_eq(
  $$ select home_latitude, home_longitude, home_set_at from public.packs $$,
  $$ values (47.4::double precision, 8.4::double precision, '2026-10-02 09:00+02'::timestamptz) $$,
  'The pack keeps the home base'
);
update public.packs set name = 'Bellos Rudel' where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
select results_eq(
  $$ select name, home_latitude, home_longitude, home_set_at from public.packs $$,
  $$ values ('Bellos Rudel', 47.4::double precision, 8.4::double precision, '2026-10-02 09:00+02'::timestamptz) $$,
  'A new name keeps the home base'
);
update public.packs set home_latitude = 47.41, home_longitude = 8.39, home_set_at = '2026-10-01 09:00+02'
  where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
select results_eq(
  $$ select home_latitude, home_longitude from public.packs $$,
  $$ values (47.41::double precision, 8.39::double precision) $$,
  'The last write of the home base wins'
);
select throws_ok(
  $$ update public.packs set home_latitude = null where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' $$,
  '23514', null,
  'A home base has both coordinates and its time, or none'
);
select throws_ok(
  $$ update public.packs set home_latitude = 91, home_set_at = now() where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' $$,
  '23514', null,
  'A home base lies on the earth'
);
select throws_ok(
  $$ update public.packs set pack_owner_id = '22222222-2222-2222-2222-222222222222'
     where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' $$,
  '42501', null,
  'The grant still covers only the name and the home base'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is_empty(
  $$ select home_latitude from public.packs where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' $$,
  'A member of another pack cannot read the home base'
);
update public.packs set home_latitude = 46, home_longitude = 7, home_set_at = '2026-12-01'
  where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select results_eq(
  $$ select home_latitude from public.packs $$,
  $$ values (47.41::double precision) $$,
  'A member of another pack cannot change the home base'
);

-- The earliest ring stamp wins

select lives_ok(
  $$ insert into public.completed_rings
       (id, pack_id, dog_id, ring, radius_m, centre_latitude, centre_longitude, completed_at)
     values ('a6000000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'a0000000-0000-0000-0000-000000000001', 1, 250, 47.4, 8.4, '2026-10-02 09:00+02') $$,
  'A member uploads a ring stamp of a dog of their pack'
);
select lives_ok(
  $$ insert into public.completed_rings
       (id, pack_id, dog_id, ring, radius_m, centre_latitude, centre_longitude, completed_at)
     values ('a6000000-0000-0000-0000-000000000003', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'a0000000-0000-0000-0000-000000000001', 1, 250, 47.4, 8.4, '2026-10-01 09:00+02'),
            ('a6000000-0000-0000-0000-000000000004', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'a0000000-0000-0000-0000-000000000001', 1, 250, 47.4, 8.4, '2026-10-03 09:00+02') $$,
  'Two other phones upload an earlier and a later stamp of the same ring'
);
select results_eq(
  $$ select id, completed_at from public.completed_rings where deleted_at is null $$,
  $$ values ('a6000000-0000-0000-0000-000000000003'::uuid, '2026-10-01 09:00+02'::timestamptz) $$,
  'Only the earliest stamp of the dog, ring and centre stays'
);
select is(
  (select count(*) from public.completed_rings where deleted_at is not null), 2::bigint,
  'The other stamps stay with a deletion time'
);
select lives_ok(
  $$ insert into public.completed_rings
       (id, pack_id, dog_id, ring, radius_m, centre_latitude, centre_longitude, completed_at)
     values ('a6000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'a0000000-0000-0000-0000-000000000001', 1, 250, 47.4, 8.4, '2026-10-01 09:00+02') $$,
  'A stamp with the same date and a smaller ID uploads'
);
select results_eq(
  $$ select id from public.completed_rings where deleted_at is null $$,
  $$ values ('a6000000-0000-0000-0000-000000000001'::uuid) $$,
  'Of two stamps with the same date, the one with the smaller ID wins'
);
select lives_ok(
  $$ insert into public.completed_rings
       (id, pack_id, dog_id, ring, radius_m, centre_latitude, centre_longitude, completed_at)
     values ('a6000000-0000-0000-0000-000000000005', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'a0000000-0000-0000-0000-000000000001', 2, 350, 47.4, 8.4, '2026-10-04 09:00+02'),
            ('a6000000-0000-0000-0000-000000000006', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'a0000000-0000-0000-0000-000000000001', 1, 250, 47.41, 8.39, '2026-10-05 09:00+02') $$,
  'Another ring and the same ring around another home base have stamps of their own'
);
select is(
  (select count(*) from public.completed_rings where deleted_at is null), 3::bigint,
  'Each dog, ring and centre has one stamp'
);
select throws_ok(
  $$ insert into public.completed_rings
       (id, pack_id, dog_id, ring, radius_m, centre_latitude, centre_longitude, completed_at)
     values ('a6000000-0000-0000-0000-000000000007', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'a0000000-0000-0000-0000-000000000001', 0, 250, 47.4, 8.4, '2026-10-05 09:00+02') $$,
  '23514', null,
  'The rings start at ring 1'
);

-- Row-level security

select throws_ok(
  $$ insert into public.completed_rings
       (id, pack_id, dog_id, ring, radius_m, centre_latitude, centre_longitude, completed_at)
     values ('a6000000-0000-0000-0000-000000000008', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
             'b0000000-0000-0000-0000-000000000001', 1, 250, 47.4, 8.4, '2026-10-01 09:00+02') $$,
  '42501', null,
  'A member cannot upload a ring stamp into another pack'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is_empty(
  $$ select * from public.completed_rings $$,
  'A member of another pack cannot read the ring stamps'
);
update public.completed_rings set completed_at = '2026-01-01';

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select count(*) from public.completed_rings where completed_at = '2026-01-01'), 0::bigint,
  'A member of another pack cannot change the ring stamps'
);

-- A ring stamp of a dog that moves into another pack moves with it

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select lives_ok(
  $$ insert into public.completed_rings
       (id, pack_id, dog_id, ring, radius_m, centre_latitude, centre_longitude, completed_at)
     values ('b6000000-0000-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
             'b0000000-0000-0000-0000-000000000001', 3, 500, 47.3, 8.5, '2026-10-01 09:00+02') $$,
  'The only member of a pack uploads a ring stamp'
);
select is(
  public.join_pack((select token from tokens where name = 'anna')), 'joined',
  'The only member joins another pack with their dog'
);
select results_eq(
  $$ select id, pack_id from public.completed_rings where dog_id = 'b0000000-0000-0000-0000-000000000001' $$,
  $$ values ('b6000000-0000-0000-0000-000000000001'::uuid, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid) $$,
  'The ring stamp of the dog moves into the new pack'
);
select throws_ok(
  $$ insert into public.completed_rings
       (id, pack_id, dog_id, ring, radius_m, centre_latitude, centre_longitude, completed_at)
     values ('b6000000-0000-0000-0000-000000000002', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
             'b0000000-0000-0000-0000-000000000001', 4, 700, 47.3, 8.5, '2026-10-01 09:00+02') $$,
  null, null,
  'A ring stamp cannot upload into the pack that disappeared'
);

-- The ring stamps go with the account of the only member of a pack

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select lives_ok(
  $$ select public.delete_account() $$,
  'The only member of a pack deletes their account'
);
reset role;
select is_empty(
  $$ select * from public.completed_rings where pack_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc' $$,
  'The ring stamps of the pack are deleted with it'
);

select * from finish();
rollback;
