-- The rule of the other members, the index of the moved packs, and the
-- photo path that a dog keeps (#130). Run with `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Anna has a pack with Bello, whose photo is in Storage. Ben joins the pack
-- of Anna. Carl has no pack.
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
insert into storage.objects (bucket_id, name) values
  ('dog-photos', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/a0000000-0000-0000-0000-000000000001-old.jpg');
insert into public.dogs (id, pack_id, name, photo_path) values
  ('a0000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Bello',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/a0000000-0000-0000-0000-000000000001-old.jpg');
insert into tokens values ('anna', public.create_invitation());

-- The other members

reset role;
select is(
  public.has_other_members('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111'),
  false,
  'The only member of a pack has no other members'
);
select is(
  public.has_other_members(null, '33333333-3333-3333-3333-333333333333'),
  false,
  'A person in no pack has no other members'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select public.join_pack((select token from tokens where name = 'anna'));

reset role;
select is(
  public.has_other_members('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111'),
  true,
  'The pack owner has another member after a join'
);
select is(
  public.has_other_members('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222'),
  true,
  'The member who joined has another member'
);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select throws_ok(
  $$ select public.has_other_members('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333') $$,
  '42501', null,
  'A person cannot ask whether a pack has other members'
);

-- The index of the moved packs

reset role;
select has_index('public', 'packs', 'packs_moved_into', 'The moved packs have an index');

-- The photo path of a dog

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
update public.dogs set name = 'Bello B',
  photo_path = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/a0000000-0000-0000-0000-000000000001-gone.jpg'
  where id = 'a0000000-0000-0000-0000-000000000001';
select results_eq(
  $$ select name, photo_path from public.dogs where id = 'a0000000-0000-0000-0000-000000000001' $$,
  $$ values ('Bello B', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/a0000000-0000-0000-0000-000000000001-old.jpg') $$,
  'An update with a photo path that Storage does not have keeps the old path, and its other changes count'
);

insert into storage.objects (bucket_id, name) values
  ('dog-photos', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/a0000000-0000-0000-0000-000000000001-new.jpg');
update public.dogs
  set photo_path = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/a0000000-0000-0000-0000-000000000001-new.jpg'
  where id = 'a0000000-0000-0000-0000-000000000001';
select is(
  (select photo_path from public.dogs where id = 'a0000000-0000-0000-0000-000000000001'),
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/a0000000-0000-0000-0000-000000000001-new.jpg',
  'An update with a photo path that Storage has takes the new path'
);

update public.dogs set photo_path = null where id = 'a0000000-0000-0000-0000-000000000001';
select is(
  (select photo_path from public.dogs where id = 'a0000000-0000-0000-0000-000000000001'),
  null,
  'An update removes the photo'
);

update public.dogs
  set photo_path = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/a0000000-0000-0000-0000-000000000001-gone.jpg'
  where id = 'a0000000-0000-0000-0000-000000000001';
select is(
  (select photo_path from public.dogs where id = 'a0000000-0000-0000-0000-000000000001'),
  null,
  'A removed photo stays removed when an update names a path that Storage does not have'
);

select * from finish();
rollback;
