-- The dogs, walks and completed records of a pack on the server (#101), with
-- the row-level security that limits each member to the rows of their pack.
-- Run with `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Anna has a pack. Ben has a pack of his own.
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'anna@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'ben@example.com');

-- Acts as the account with the ID, like a request with its access token.
create function pg_temp.act_as(account uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', account, 'role', 'authenticated')::text, true);
$$;

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
update public.members set name = 'Anna';
select public.create_pack('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Annas Rudel', now());
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select public.create_pack('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Bens Rudel', now());

-- Dogs

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select lives_ok(
  $$ insert into public.dogs (id, pack_id, name, photo_path)
     values ('d0000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Bello',
             'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/d0000000-0000-0000-0000-000000000001.jpg') $$,
  'A member uploads a dog into their pack'
);
select lives_ok(
  $$ insert into public.dogs (id, pack_id, name, retired_at, retirement_reason)
     values ('d0000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Bello',
             '2026-10-01 08:00+02', 'Old age')
     on conflict (id) do update set name = excluded.name, photo_path = excluded.photo_path,
       retired_at = excluded.retired_at, retirement_reason = excluded.retirement_reason,
       deleted_at = excluded.deleted_at $$,
  'A member uploads the same dog again, retired'
);
select results_eq(
  $$ select name, photo_path, retired_at, retirement_reason from public.dogs $$,
  $$ values ('Bello', null::text, '2026-10-01 08:00+02'::timestamptz, 'Old age') $$,
  'The last upload of a dog wins for the whole row'
);
select throws_ok(
  $$ insert into public.dogs (id, pack_id, name)
     values ('d0000000-0000-0000-0000-000000000002', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Rex') $$,
  '42501', null,
  'A member cannot upload a dog into another pack'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is_empty(
  $$ select * from public.dogs $$,
  'A member of another pack cannot read the dog'
);
select throws_ok(
  $$ insert into public.dogs (id, pack_id, name)
     values ('d0000000-0000-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Rex')
     on conflict (id) do update set name = excluded.name, pack_id = excluded.pack_id $$,
  '42501', null,
  'A member of another pack cannot take over the dog by its ID'
);

-- Walks

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select lives_ok(
  $$ insert into public.walks (id, pack_id, started_at, ended_at, track_path, distance_metres, distance_version,
                               device_id, member_name)
     values ('e0000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             '2026-10-01 08:00+02', '2026-10-01 09:00+02',
             'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/e0000000-0000-0000-0000-000000000001', 2500, 3, 'phone', 'Nina'),
            ('e0000000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             '2026-10-02 08:00+02', '2026-10-02 09:00+02', null, 0, 3, '', '') $$,
  'A member uploads walks into their pack'
);
select results_eq(
  $$ select id, member_name from public.walks order by started_at $$,
  $$ values ('e0000000-0000-0000-0000-000000000001'::uuid, 'Nina'),
            ('e0000000-0000-0000-0000-000000000002'::uuid, 'Anna') $$,
  'A walk with an empty member name gets the name of the member who uploads it'
);
-- Cara is a member of Anna's pack. The join is #104, so the test puts her
-- into the pack directly.
reset role;
insert into auth.users (id, email) values ('33333333-3333-3333-3333-333333333333', 'cara@example.com');
update public.members set pack_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', joined_at = now(), name = 'Cara'
  where account_id = '33333333-3333-3333-3333-333333333333';
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select lives_ok(
  $$ insert into public.walks (id, pack_id, started_at, ended_at)
     values ('e0000000-0000-0000-0000-000000000003', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             '2026-10-02 10:00+02', '2026-10-02 11:00+02') $$,
  'A member who is not the pack owner uploads a walk with an empty member name'
);
select results_eq(
  $$ select member_name from public.walks where id = 'e0000000-0000-0000-0000-000000000003' $$,
  $$ values ('Cara') $$,
  'A walk of another member with an empty member name gets the name of that member'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select lives_ok(
  $$ update public.walks set deleted_at = '2026-10-03 08:00+02' where id = 'e0000000-0000-0000-0000-000000000002' $$,
  'A member deletes a walk'
);
select results_eq(
  $$ select deleted_at from public.walks where id = 'e0000000-0000-0000-0000-000000000002' $$,
  $$ values ('2026-10-03 08:00+02'::timestamptz) $$,
  'A deleted walk stays with its deletion time'
);
select lives_ok(
  $$ insert into public.walk_dogs (id, pack_id, walk_id, dog_id)
     values ('f0000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'e0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001') $$,
  'A member uploads a dog of a walk'
);
select lives_ok(
  $$ update public.walk_dogs set deleted_at = now() where id = 'f0000000-0000-0000-0000-000000000001' $$,
  'A dog leaves a walk'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select lives_ok(
  $$ insert into public.dogs (id, pack_id, name)
     values ('d0000000-0000-0000-0000-000000000002', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Rex') $$,
  'A member of another pack uploads their own dog'
);
select is_empty(
  $$ select * from public.walks $$,
  'A member of another pack reads no walk'
);
select is_empty(
  $$ select * from public.walk_dogs $$,
  'A member of another pack reads no dog of a walk'
);
select throws_ok(
  $$ insert into public.walk_dogs (id, pack_id, walk_id, dog_id)
     values ('f0000000-0000-0000-0000-000000000002', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
             'e0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002') $$,
  '23503', null,
  'A dog cannot join a walk of another pack'
);

-- Completed records

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select lives_ok(
  $$ insert into public.completed_areas (id, pack_id, dog_id, area, completed_at)
     values ('c0000000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'd0000000-0000-0000-0000-000000000001', 243, '2026-10-05 08:00+02') $$,
  'A member uploads a completed record of an area'
);
-- A second phone completed the same area earlier, before the records of the
-- first phone reached it.
select lives_ok(
  $$ insert into public.completed_areas (id, pack_id, dog_id, area, completed_at)
     values ('c0000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'd0000000-0000-0000-0000-000000000001', 243, '2026-10-04 08:00+02') $$,
  'A member uploads an earlier record of the same dog and area'
);
-- A third phone completed it later still.
select lives_ok(
  $$ insert into public.completed_areas (id, pack_id, dog_id, area, completed_at)
     values ('c0000000-0000-0000-0000-000000000003', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'd0000000-0000-0000-0000-000000000001', 243, '2026-10-06 08:00+02') $$,
  'A member uploads a later record of the same dog and area'
);
select results_eq(
  $$ select id, completed_at from public.completed_areas where deleted_at is null $$,
  $$ values ('c0000000-0000-0000-0000-000000000001'::uuid, '2026-10-04 08:00+02'::timestamptz) $$,
  'Only the earliest record of a dog and area stays'
);
select is(
  (select count(*) from public.completed_areas where deleted_at is not null), 2::bigint,
  'The later records stay with a deletion time'
);
select lives_ok(
  $$ insert into public.completed_areas (id, pack_id, dog_id, area, completed_at)
     values ('c0000000-0000-0000-0000-000000000003', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'd0000000-0000-0000-0000-000000000001', 243, '2026-10-06 08:00+02')
     on conflict (id) do update set completed_at = excluded.completed_at, deleted_at = excluded.deleted_at $$,
  'The phone of the later record uploads it again'
);
select results_eq(
  $$ select id from public.completed_areas where deleted_at is null $$,
  $$ values ('c0000000-0000-0000-0000-000000000001'::uuid) $$,
  'The earliest record still wins'
);
-- Two records with the same date: the smaller ID wins, as on the phones.
select lives_ok(
  $$ insert into public.completed_streets (id, pack_id, dog_id, area, street, completed_at)
     values ('c1000000-0000-0000-0000-00000000000b', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'd0000000-0000-0000-0000-000000000001', 243, 'Zürcherstrasse', '2026-10-05 08:00+02'),
            ('c1000000-0000-0000-0000-00000000000a', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'd0000000-0000-0000-0000-000000000001', 243, 'Zürcherstrasse', '2026-10-05 08:00+02'),
            ('c1000000-0000-0000-0000-00000000000c', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             'd0000000-0000-0000-0000-000000000001', 243, 'Bahnhofstrasse', '2026-10-06 08:00+02') $$,
  'A member uploads completed records of streets'
);
select results_eq(
  $$ select id from public.completed_streets where deleted_at is null order by street $$,
  $$ values ('c1000000-0000-0000-0000-00000000000c'::uuid), ('c1000000-0000-0000-0000-00000000000a'::uuid) $$,
  'One record stays for each dog and street, and the smaller ID wins a tie'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is_empty(
  $$ select * from public.completed_areas $$,
  'A member of another pack reads no completed record'
);
select throws_ok(
  $$ insert into public.completed_areas (id, pack_id, dog_id, area, completed_at)
     values ('c0000000-0000-0000-0000-000000000009', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
             'd0000000-0000-0000-0000-000000000001', 250, now()) $$,
  '23503', null,
  'A completed record cannot name a dog of another pack'
);

-- GPS tracks and dog photos in Storage

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select lives_ok(
  $$ insert into storage.objects (bucket_id, name)
     values ('tracks', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/e0000000-0000-0000-0000-000000000001'),
            ('dog-photos', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/d0000000-0000-0000-0000-000000000001.jpg') $$,
  'A member uploads a GPS track and a dog photo into the folder of their pack'
);
select lives_ok(
  $$ update storage.objects set metadata = '{}'
     where name = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/e0000000-0000-0000-0000-000000000001' $$,
  'A member replaces a GPS track of their pack'
);
select throws_ok(
  $$ insert into storage.objects (bucket_id, name)
     values ('tracks', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/e0000000-0000-0000-0000-000000000009') $$,
  '42501', null,
  'A member cannot upload into the folder of another pack'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is_empty(
  $$ select * from storage.objects where bucket_id in ('tracks', 'dog-photos') $$,
  'A member of another pack reads no GPS track and no dog photo'
);
-- The Storage API allows a delete like this. A delete by SQL alone fails.
select set_config('storage.allow_delete_query', 'true', true);
select is_empty(
  $$ delete from storage.objects where bucket_id = 'dog-photos' returning name $$,
  'A member of another pack cannot delete a dog photo'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select results_eq(
  $$ delete from storage.objects where bucket_id = 'dog-photos' returning name $$,
  $$ values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/d0000000-0000-0000-0000-000000000001.jpg') $$,
  'A member deletes a dog photo of their pack'
);

select * from finish();
rollback;
