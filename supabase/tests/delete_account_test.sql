-- A person deletes their account (#107). The walks that the person recorded
-- stay with the dogs. When the pack owner deletes their account, the member
-- who joined first becomes the pack owner. When the only member deletes
-- their account, the pack and everything in it is deleted. Run with
-- `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Anna has a pack with Bello. Ben joined it first, Carl after him. Dora has
-- a pack with Luna. Eva was the only member of a pack with Rex, and brought
-- Rex into the pack of Dora. Gina joined the pack of Dora and left it. Fred
-- has no pack.
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'anna@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'ben@example.com'),
  ('33333333-3333-3333-3333-333333333333', 'carl@example.com'),
  ('44444444-4444-4444-4444-444444444444', 'dora@example.com'),
  ('55555555-5555-5555-5555-555555555555', 'eva@example.com'),
  ('66666666-6666-6666-6666-666666666666', 'fred@example.com'),
  ('77777777-7777-7777-7777-777777777777', 'gina@example.com');

-- Acts as the account with the ID, like a request with its access token.
create function pg_temp.act_as(account uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', account, 'role', 'authenticated')::text, true);
$$;

-- Deletes the files in the folder like the Storage API, with the row-level
-- security of the calling person.
create function pg_temp.delete_files_in(folder text) returns void language sql as $$
  select set_config('storage.allow_delete_query', 'true', true);
  delete from storage.objects where bucket_id in ('tracks', 'dog-photos') and (storage.foldername(name))[1] = folder;
  select set_config('storage.allow_delete_query', 'false', true);
$$;

create temporary table tokens (name text primary key, token text not null);
grant all on tokens to authenticated;

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select public.create_pack('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Annas Rudel', now());
update public.members set name = 'Anna' where account_id = '11111111-1111-1111-1111-111111111111';
insert into public.dogs (id, pack_id, name) values
  ('a0000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Bello');
insert into public.walks (id, pack_id, started_at, ended_at, member_name) values
  ('a1000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '2026-10-01 08:00+02', '2026-10-01 09:00+02', 'Anna');
insert into public.walk_dogs (id, pack_id, walk_id, dog_id) values
  ('a2000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'a1000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001');
insert into tokens values ('anna-ben', public.create_invitation());
insert into tokens values ('anna-carl', public.create_invitation());
insert into tokens values ('anna-open', public.create_invitation());

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
update public.members set name = 'Ben' where account_id = '22222222-2222-2222-2222-222222222222';
select public.join_pack((select token from tokens where name = 'anna-ben'));
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
update public.members set name = 'Carl' where account_id = '33333333-3333-3333-3333-333333333333';
select public.join_pack((select token from tokens where name = 'anna-carl'));

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select public.create_pack('dddddddd-dddd-dddd-dddd-dddddddddddd', 'Doras Rudel', now());
insert into public.dogs (id, pack_id, name, photo_path) values
  ('d0000000-0000-0000-0000-000000000001', 'dddddddd-dddd-dddd-dddd-dddddddddddd', 'Luna',
   'dddddddd-dddd-dddd-dddd-dddddddddddd/d0000000-0000-0000-0000-000000000001.jpg');
insert into public.walks (id, pack_id, started_at, ended_at, track_path, member_name) values
  ('d1000000-0000-0000-0000-000000000001', 'dddddddd-dddd-dddd-dddd-dddddddddddd',
   '2026-10-01 08:00+02', '2026-10-01 09:00+02',
   'dddddddd-dddd-dddd-dddd-dddddddddddd/d1000000-0000-0000-0000-000000000001', 'Dora');
insert into public.walk_dogs (id, pack_id, walk_id, dog_id) values
  ('d2000000-0000-0000-0000-000000000001', 'dddddddd-dddd-dddd-dddd-dddddddddddd',
   'd1000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001');
insert into public.completed_areas (id, pack_id, dog_id, area, completed_at) values
  ('d3000000-0000-0000-0000-000000000001', 'dddddddd-dddd-dddd-dddd-dddddddddddd',
   'd0000000-0000-0000-0000-000000000001', 243, '2026-10-01 09:00+02');
insert into public.completed_streets (id, pack_id, dog_id, area, street, completed_at) values
  ('d4000000-0000-0000-0000-000000000001', 'dddddddd-dddd-dddd-dddd-dddddddddddd',
   'd0000000-0000-0000-0000-000000000001', 243, 'Zürcherstrasse', '2026-10-01 09:00+02');
insert into storage.objects (bucket_id, name) values
  ('tracks', 'dddddddd-dddd-dddd-dddd-dddddddddddd/d1000000-0000-0000-0000-000000000001'),
  ('dog-photos', 'dddddddd-dddd-dddd-dddd-dddddddddddd/d0000000-0000-0000-0000-000000000001.jpg');
insert into tokens values ('dora', public.create_invitation());
insert into tokens values ('dora-open', public.create_invitation());

select pg_temp.act_as('55555555-5555-5555-5555-555555555555');
select public.create_pack('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'Evas Rudel', now());
insert into public.dogs (id, pack_id, name) values
  ('e0000000-0000-0000-0000-000000000001', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'Rex');
insert into storage.objects (bucket_id, name) values
  ('tracks', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee/e1000000-0000-0000-0000-000000000001');
select public.join_pack((select token from tokens where name = 'dora'));
select pg_temp.act_as('77777777-7777-7777-7777-777777777777');
select public.join_pack((select token from tokens where name = 'dora-open'));
select public.leave_pack();

-- Nobody without an account

reset role;
select set_config('request.jwt.claims', '', true);
select throws_ok(
  $$ select public.delete_account() $$,
  '42501', null,
  'Only a signed-in person deletes their account'
);

-- The pack owner of a pack with other members

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is_empty(
  $$ select public.packs_deleted_with_account() $$,
  'The account of a member of a pack with other members deletes no files'
);
select lives_ok(
  $$ select public.delete_account() $$,
  'The pack owner deletes their account'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select results_eq(
  $$ select name, is_pack_owner from public.pack_members() $$,
  $$ values ('Ben', true), ('Carl', false) $$,
  'The member who joined first is the pack owner, and the person is no member any more'
);
select results_eq(
  $$ select walks.member_name, walk_dogs.dog_id from public.walks
       join public.walk_dogs on walk_dogs.walk_id = walks.id $$,
  $$ values ('Anna', 'a0000000-0000-0000-0000-000000000001'::uuid) $$,
  'The walks that the person recorded stay with the dogs'
);
select results_eq(
  $$ select state from public.check_invitation((select token from tokens where name = 'anna-open')) $$,
  $$ values ('member') $$,
  'The invitations of the person still lead into the pack'
);
select lives_ok(
  $$ insert into tokens values ('ben', public.create_invitation()) $$,
  'The new pack owner invites'
);

reset role;
select is_empty(
  $$ select from auth.users where id = '11111111-1111-1111-1111-111111111111' $$,
  'The account is deleted'
);
select is_empty(
  $$ select from public.members where account_id = '11111111-1111-1111-1111-111111111111' $$,
  'The member row is deleted'
);

-- A member who is not the pack owner

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select public.delete_account();
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select results_eq(
  $$ select name, is_pack_owner from public.pack_members() $$,
  $$ values ('Ben', true) $$,
  'The account of a member leaves the pack owner as it is'
);

-- A member who brought their dogs from a pack of their own

select pg_temp.act_as('55555555-5555-5555-5555-555555555555');
select lives_ok(
  $$ select public.delete_account() $$,
  'A member deletes their account, also when their old pack moved into the pack'
);
select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select results_eq(
  $$ select name from public.dogs order by name $$,
  $$ values ('Luna'), ('Rex') $$,
  'The dogs that the member brought stay in the pack'
);
select results_eq(
  $$ select name from storage.objects where bucket_id = 'tracks' order by name $$,
  $$ values ('dddddddd-dddd-dddd-dddd-dddddddddddd/d1000000-0000-0000-0000-000000000001'),
            ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee/e1000000-0000-0000-0000-000000000001') $$,
  'The members still read the GPS tracks in the folder of the old pack'
);

-- The only member of a pack

select results_eq(
  $$ select public.packs_deleted_with_account() order by 1 $$,
  $$ values ('dddddddd-dddd-dddd-dddd-dddddddddddd'::uuid), ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'::uuid) $$,
  'The account of the only member deletes the files of the pack, and of each pack that moved into it'
);
select throws_ok(
  $$ select public.delete_account() $$,
  'P0001', 'The files of the pack must be deleted first.',
  'The account of the only member waits until the files of the pack are deleted'
);
select pg_temp.delete_files_in('dddddddd-dddd-dddd-dddd-dddddddddddd');
select pg_temp.delete_files_in('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee');
select is_empty(
  $$ select from storage.objects where bucket_id in ('tracks', 'dog-photos') $$,
  'The only member deletes the files of the pack, and of each pack that moved into it'
);
select lives_ok(
  $$ select public.delete_account() $$,
  'The only member deletes their account'
);

reset role;
select is_empty(
  $$ select from public.packs where id in ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee') $$,
  'The pack is deleted, with each pack that moved into it'
);
select is_empty(
  $$ select from public.dogs where pack_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
     union all select from public.walks where pack_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
     union all select from public.walk_dogs where pack_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
     union all select from public.completed_areas where pack_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
     union all select from public.completed_streets where pack_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd' $$,
  'The dogs, the walks and the completed records of the pack are deleted'
);
select is_empty(
  $$ select from public.departures where pack_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd' $$,
  'The departures from the pack are deleted'
);
select is_empty(
  $$ select from public.invitations
     where pack_id in ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee') $$,
  'The invitations of the pack are deleted'
);
select is_empty(
  $$ select from auth.users where id = '44444444-4444-4444-4444-444444444444' $$,
  'The account of the only member is deleted'
);
select results_eq(
  $$ select name from public.packs where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and deleted_at is null $$,
  $$ values ('Annas Rudel') $$,
  'The other packs stay'
);

-- A person without a pack

select pg_temp.act_as('66666666-6666-6666-6666-666666666666');
select is_empty(
  $$ select public.packs_deleted_with_account() $$,
  'The account of a person without a pack deletes no files'
);
select public.delete_account();
reset role;
select is_empty(
  $$ select from auth.users where id = '66666666-6666-6666-6666-666666666666' $$,
  'A person without a pack deletes their account'
);

select * from finish();
rollback;
