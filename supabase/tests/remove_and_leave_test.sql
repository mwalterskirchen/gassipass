-- The pack owner removes a member, and a member leaves the pack (#106). Only
-- the pack owner removes, and the pack owner can neither leave nor remove
-- themselves. The person who is out of the pack cannot read or write it any
-- more, and their walks stay with the dogs.
-- Run with `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Anna has a pack with Ben and Carl. Dora has a pack of her own.
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'anna@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'ben@example.com'),
  ('33333333-3333-3333-3333-333333333333', 'carl@example.com'),
  ('44444444-4444-4444-4444-444444444444', 'dora@example.com');

-- Acts as the account with the ID, like a request with its access token.
create function pg_temp.act_as(account uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', account, 'role', 'authenticated')::text, true);
$$;

create temporary table tokens (name text primary key, token text not null);
grant all on tokens to authenticated;

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
update public.members set name = 'Anna';
select public.create_pack('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Annas Rudel', now());
insert into public.dogs (id, pack_id, name)
  values ('d0000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Bello');
insert into tokens values ('ben', public.create_invitation()), ('carl', public.create_invitation());

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
update public.members set name = 'Ben';
select public.join_pack((select token from tokens where name = 'ben'));
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
update public.members set name = 'Carl';
select public.join_pack((select token from tokens where name = 'carl'));

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select public.create_pack('dddddddd-dddd-dddd-dddd-dddddddddddd', 'Doras Rudel', now());

-- Each member gets the ID of each member, so that the pack owner can remove
-- one.

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select results_eq(
  $$ select id, name, is_pack_owner from public.pack_members() $$,
  $$ values ('11111111-1111-1111-1111-111111111111'::uuid, 'Anna', true),
            ('22222222-2222-2222-2222-222222222222'::uuid, 'Ben', false),
            ('33333333-3333-3333-3333-333333333333'::uuid, 'Carl', false) $$,
  'The members of the pack come with their IDs'
);

-- The leave

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select throws_ok(
  $$ select public.leave_pack() $$,
  '42501', null,
  'The pack owner cannot leave the pack'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
-- Ben records a walk with Bello before he leaves.
insert into public.walks (id, pack_id, started_at, ended_at)
  values ('e0000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', now() - interval '1 hour', now());
insert into public.walk_dogs (id, pack_id, walk_id, dog_id)
  values ('f0000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
          'e0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001');
select lives_ok(
  $$ select public.leave_pack() $$,
  'A member who is not the pack owner leaves the pack'
);
select results_eq(
  $$ select name, pack_id from public.members $$,
  $$ values ('Ben', null::uuid) $$,
  'The member who left is in no pack'
);
select is_empty($$ select * from public.packs $$, 'The member who left cannot read the pack');
select is_empty($$ select * from public.dogs $$, 'The member who left cannot read the dogs of the pack');
select is_empty($$ select * from public.walks $$, 'The member who left cannot read the walks of the pack');
select is_empty($$ select * from public.pack_members() $$, 'The member who left sees no members');
select throws_ok(
  $$ insert into public.dogs (id, pack_id, name)
     values ('d0000000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Rex') $$,
  '42501', null,
  'The member who left cannot write into the pack'
);
select results_eq(
  $$ select public.has_left_pack('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') $$,
  $$ values (true) $$,
  'The phones of the member who left learn that the person left the pack'
);
select results_eq(
  $$ select public.has_left_pack('dddddddd-dddd-dddd-dddd-dddddddddddd') $$,
  $$ values (false) $$,
  'A person has not left a pack that they were never in'
);
select lives_ok(
  $$ select public.leave_pack() $$,
  'A second leave after a lost answer changes nothing'
);
select results_eq(
  $$ select pack_id from public.members $$,
  $$ values (null::uuid) $$,
  'The member who left twice is still in no pack'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select results_eq(
  $$ select walks.member_name, walk_dogs.dog_id from public.walks
     join public.walk_dogs on walk_dogs.walk_id = walks.id $$,
  $$ values ('Ben', 'd0000000-0000-0000-0000-000000000001'::uuid) $$,
  'The walk of the member who left stays with the dog, with his name'
);
select results_eq(
  $$ select name from public.pack_members() $$,
  $$ values ('Anna'), ('Carl') $$,
  'The member who left is no member any more'
);
select results_eq(
  $$ select public.has_left_pack('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') $$,
  $$ values (false) $$,
  'A member of the pack has not left it'
);

-- The removal

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
insert into storage.objects (bucket_id, name)
  values ('tracks', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/e0000000-0000-0000-0000-000000000002');
select throws_ok(
  $$ select public.remove_member('22222222-2222-2222-2222-222222222222') $$,
  '42501', null,
  'A member who is not the pack owner cannot remove a member'
);
select throws_ok(
  $$ select public.remove_member('11111111-1111-1111-1111-111111111111') $$,
  '42501', null,
  'A member cannot remove the pack owner'
);

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select throws_ok(
  $$ select public.remove_member('33333333-3333-3333-3333-333333333333') $$,
  'P0002', null,
  'The pack owner of another pack cannot remove a member'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select throws_ok(
  $$ select public.remove_member('11111111-1111-1111-1111-111111111111') $$,
  '42501', null,
  'The pack owner cannot remove themselves'
);
select lives_ok(
  $$ select public.remove_member('33333333-3333-3333-3333-333333333333') $$,
  'The pack owner removes a member'
);
select results_eq(
  $$ select name from public.pack_members() $$,
  $$ values ('Anna') $$,
  'The removed member is no member any more'
);
select lives_ok(
  $$ select public.remove_member('33333333-3333-3333-3333-333333333333') $$,
  'A second removal after a lost answer changes nothing'
);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select results_eq(
  $$ select pack_id from public.members $$,
  $$ values (null::uuid) $$,
  'The removed member is in no pack'
);
select is_empty($$ select * from public.packs $$, 'The removed member cannot read the pack');
select is_empty($$ select * from public.dogs $$, 'The removed member cannot read the dogs of the pack');
select is_empty($$ select * from storage.objects $$, 'The removed member cannot read the files of the pack');
select throws_ok(
  $$ insert into storage.objects (bucket_id, name)
     values ('tracks', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/e0000000-0000-0000-0000-000000000003') $$,
  '42501', null,
  'The removed member cannot upload a file into the pack'
);
select results_eq(
  $$ select public.has_left_pack('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') $$,
  $$ values (true) $$,
  'The phones of the removed member learn that the person is out of the pack'
);

-- A person who is out of the pack can join it again with a new invitation.

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into tokens values ('carl again', public.create_invitation());
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select results_eq(
  $$ select public.join_pack((select token from tokens where name = 'carl again')) $$,
  $$ values ('joined') $$,
  'The removed member joins again with a new invitation'
);
select results_eq(
  $$ select public.has_left_pack('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') $$,
  $$ values (false) $$,
  'A person who joined the pack again is in it'
);

select * from finish();
rollback;
