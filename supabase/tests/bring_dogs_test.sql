-- A person who is the only member of their pack joins another pack, and
-- brings their dogs, with their walks and completed records (ADR 0005,
-- #105). Their old pack disappears. Run with `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Anna has a pack with Bello. Ben is the only member of his pack, with Luna
-- and the retired dog Rex. Dora has a pack with Eva. Carl has no pack.
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

create temporary table tokens (name text primary key, token text not null);
grant all on tokens to authenticated;

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select public.create_pack('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Annas Rudel', now());
insert into public.dogs (id, pack_id, name) values
  ('a0000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Bello');
insert into tokens values ('anna', public.create_invitation());
insert into tokens values ('anna-2', public.create_invitation());

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select public.create_pack('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Bens Rudel', now());
insert into public.dogs (id, pack_id, name, photo_path, retired_at) values
  ('b0000000-0000-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Luna',
   'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/b0000000-0000-0000-0000-000000000001', null),
  ('b0000000-0000-0000-0000-000000000002', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Rex', null, '2026-09-01');
insert into public.walks (id, pack_id, started_at, ended_at, track_path, member_name, deleted_at) values
  ('b1000000-0000-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   '2026-10-01 08:00+02', '2026-10-01 09:00+02',
   'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/b1000000-0000-0000-0000-000000000001', 'Ben', null),
  ('b1000000-0000-0000-0000-000000000002', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   '2026-10-02 08:00+02', '2026-10-02 09:00+02', null, 'Ben', '2026-10-03');
insert into public.walk_dogs (id, pack_id, walk_id, dog_id) values
  ('b2000000-0000-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   'b1000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001'),
  ('b2000000-0000-0000-0000-000000000002', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   'b1000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000002');
insert into public.completed_areas (id, pack_id, dog_id, area, completed_at) values
  ('b3000000-0000-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   'b0000000-0000-0000-0000-000000000001', 243, '2026-10-01 09:00+02');
insert into public.completed_streets (id, pack_id, dog_id, area, street, completed_at) values
  ('b4000000-0000-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   'b0000000-0000-0000-0000-000000000001', 243, 'Zürcherstrasse', '2026-10-01 09:00+02');
insert into storage.objects (bucket_id, name) values
  ('tracks', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/b1000000-0000-0000-0000-000000000001'),
  ('dog-photos', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/b0000000-0000-0000-0000-000000000001.jpg');
insert into tokens values ('ben', public.create_invitation());

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select public.create_pack('dddddddd-dddd-dddd-dddd-dddddddddddd', 'Doras Rudel', now());
insert into storage.objects (bucket_id, name) values
  ('tracks', 'dddddddd-dddd-dddd-dddd-dddddddddddd/d1000000-0000-0000-0000-000000000001');
insert into tokens values ('dora', public.create_invitation());
select pg_temp.act_as('55555555-5555-5555-5555-555555555555');
select public.join_pack((select token from tokens where name = 'dora'));

-- The rows changed long ago, so that the test sees the time of the move.
-- The replica role stops the trigger that sets the time of the change.
reset role;
set local session_replication_role = replica;
update public.dogs set changed_at = '2026-01-01';
update public.walks set changed_at = '2026-01-01';
set local session_replication_role = origin;

-- The invitation

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select results_eq(
  $$ select state, pack_name from public.check_invitation((select token from tokens where name = 'anna')) $$,
  $$ values ('open', 'Annas Rudel') $$,
  'The only member of a pack can join another pack'
);
select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select results_eq(
  $$ select public.join_pack((select token from tokens where name = 'anna')) $$,
  $$ values ('in_other_pack') $$,
  'A member of a pack with other members cannot join another pack'
);

-- The join

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select results_eq(
  $$ select public.join_pack((select token from tokens where name = 'anna')) $$,
  $$ values ('joined') $$,
  'The only member of a pack joins'
);
select results_eq(
  $$ select pack_id from public.members $$,
  $$ values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid) $$,
  'The person who joined is a member of the new pack'
);
select results_eq(
  $$ select name, pack_id, changed_at = now() from public.dogs order by name $$,
  $$ values ('Bello', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, false),
            ('Luna', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, true),
            ('Rex', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, true) $$,
  'The dogs come along, also a retired dog, with the time of the move as their change'
);
select results_eq(
  $$ select id, pack_id, changed_at = now(), deleted_at is not null from public.walks order by started_at $$,
  $$ values ('b1000000-0000-0000-0000-000000000001'::uuid, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, true, false),
            ('b1000000-0000-0000-0000-000000000002'::uuid, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, true, true) $$,
  'The walks come along, also a deleted walk'
);
select results_eq(
  $$ select photo_path from public.dogs where name = 'Luna'
     union all select track_path from public.walks where track_path is not null $$,
  $$ values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/b0000000-0000-0000-0000-000000000001'),
            ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/b1000000-0000-0000-0000-000000000001') $$,
  'The photos and the GPS tracks stay in the folder of the old pack'
);
select results_eq(
  $$ select name from storage.objects where bucket_id in ('tracks', 'dog-photos') order by name $$,
  $$ values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/b0000000-0000-0000-0000-000000000001.jpg'),
            ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/b1000000-0000-0000-0000-000000000001') $$,
  'The person who joined reads the files in the folder of the old pack'
);
select results_eq(
  $$ select id, pack_id from public.walk_dogs order by id $$,
  $$ values ('b2000000-0000-0000-0000-000000000001'::uuid, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid),
            ('b2000000-0000-0000-0000-000000000002'::uuid, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid) $$,
  'The dogs of the walks come along'
);
select results_eq(
  $$ select id, pack_id from public.completed_areas
     union all select id, pack_id from public.completed_streets $$,
  $$ values ('b3000000-0000-0000-0000-000000000001'::uuid, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid),
            ('b4000000-0000-0000-0000-000000000001'::uuid, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid) $$,
  'The completed records come along'
);
select results_eq(
  $$ select name from public.packs $$,
  $$ values ('Annas Rudel') $$,
  'The person who joined reads only the new pack'
);
select results_eq(
  $$ select public.has_moved_into_pack_of_caller('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb') $$,
  $$ values (true) $$,
  'The other phones of the person learn that the old pack moved into their pack'
);
select throws_ok(
  $$ insert into public.dogs (id, pack_id, name) values
       ('b0000000-0000-0000-0000-000000000003', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Max') $$,
  '23503', null,
  'A phone that still has the old pack cannot upload into it'
);

-- The pack owner

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select results_eq(
  $$ select name from public.dogs order by name $$,
  $$ values ('Bello'), ('Luna'), ('Rex') $$,
  'The pack owner reads the dogs that came along'
);
select results_eq(
  $$ select count(*)::integer from public.walks $$,
  $$ values (2) $$,
  'The pack owner reads the walks that came along'
);
select results_eq(
  $$ select name from storage.objects where bucket_id in ('tracks', 'dog-photos') order by name $$,
  $$ values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/b0000000-0000-0000-0000-000000000001.jpg'),
            ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/b1000000-0000-0000-0000-000000000001') $$,
  'The pack owner reads the files in the folder of the old pack'
);
select throws_ok(
  $$ insert into storage.objects (bucket_id, name)
     values ('tracks', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/b1000000-0000-0000-0000-000000000009') $$,
  '42501', null,
  'Nobody uploads into the folder of the old pack'
);

-- The old pack

reset role;
select results_eq(
  $$ select deleted_at is not null, moved_into from public.packs where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' $$,
  $$ values (true, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid) $$,
  'The old pack disappears, and keeps the pack that it moved into'
);
select throws_ok(
  $$ insert into public.dogs (id, pack_id, name) values
       ('b0000000-0000-0000-0000-000000000004', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Max') $$,
  '23503', null,
  'No row goes into a pack that has disappeared, also not from an upload that started before the move'
);
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select results_eq(
  $$ select state from public.check_invitation((select token from tokens where name = 'ben')) $$,
  $$ values ('unknown') $$,
  'An invitation to the old pack no longer exists'
);
select results_eq(
  $$ select public.has_moved_into_pack_of_caller('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb') $$,
  $$ values (false) $$,
  'A person outside the new pack does not learn where the old pack went'
);
select is_empty(
  $$ select name from storage.objects where bucket_id in ('tracks', 'dog-photos') $$,
  'A person in no pack reads no file of the old pack'
);
select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select results_eq(
  $$ select name from storage.objects where bucket_id in ('tracks', 'dog-photos') $$,
  $$ values ('dddddddd-dddd-dddd-dddd-dddddddddddd/d1000000-0000-0000-0000-000000000001') $$,
  'A member of another pack reads only the files of their pack'
);

-- Two completed records for the same dog and area

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into public.completed_areas (id, pack_id, dog_id, area, completed_at) values
  ('b3000000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'b0000000-0000-0000-0000-000000000001', 243, '2026-10-05 09:00+02');
select results_eq(
  $$ select id from public.completed_areas where deleted_at is null $$,
  $$ values ('b3000000-0000-0000-0000-000000000001'::uuid) $$,
  'A later record from a second phone meets the record that came along, and the earliest stays'
);
insert into public.completed_streets (id, pack_id, dog_id, area, street, completed_at) values
  ('b4000000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'b0000000-0000-0000-0000-000000000001', 243, 'Zürcherstrasse', '2026-09-30 09:00+02');
select results_eq(
  $$ select id from public.completed_streets where deleted_at is null $$,
  $$ values ('b4000000-0000-0000-0000-000000000002'::uuid) $$,
  'An earlier record from a second phone meets the record that came along, and the earliest stays'
);

-- A person in no pack who joins brings nothing

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select results_eq(
  $$ select public.join_pack((select token from tokens where name = 'anna-2')) $$,
  $$ values ('joined') $$,
  'A person in no pack joins as before'
);
select results_eq(
  $$ select count(*)::integer from public.dogs $$,
  $$ values (3) $$,
  'A person in no pack brings no dogs'
);

select * from finish();
rollback;
