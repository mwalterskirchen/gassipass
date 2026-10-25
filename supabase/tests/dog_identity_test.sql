-- The identity page of the passport (#158): the date of birth and the issue
-- date of a dog. A new dog gets the time of its upload as issue date, and a
-- dog from before the issue dates gets the start of its first walk, or the
-- time of the migration when it has no walk. Run with `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Anna has a pack with Bello, Luna and Rex. Ben had a pack with Max, which
-- has disappeared.
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'anna@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'ben@example.com');

-- Acts as the account with the ID, like a request with its access token.
create function pg_temp.act_as(account uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', account, 'role', 'authenticated')::text, true);
$$;

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select public.create_pack('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Bens Rudel', now());
insert into public.dogs (id, pack_id, name, added_at) values
  ('b0000000-0000-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Max', null);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select public.create_pack('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Annas Rudel', now());

-- The date of birth and the issue date

select lives_ok(
  $$ insert into public.dogs (id, pack_id, name, born_on, added_at) values
       ('a0000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Bello',
        '2019-05-17', '2026-10-25 08:00+02') $$,
  'A member uploads a dog with its date of birth and its issue date'
);
select results_eq(
  $$ select born_on, added_at from public.dogs where id = 'a0000000-0000-0000-0000-000000000001' $$,
  $$ values ('2019-05-17'::date, '2026-10-25 08:00+02'::timestamptz) $$,
  'The dog keeps its date of birth and its issue date'
);
select lives_ok(
  $$ insert into public.dogs (id, pack_id, name) values
       ('a0000000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Luna') $$,
  'A phone without the issue dates uploads a dog without them'
);
select results_eq(
  $$ select born_on, added_at = now() from public.dogs where id = 'a0000000-0000-0000-0000-000000000002' $$,
  $$ values (null::date, true) $$,
  'The dog has no date of birth, and the time of its upload as issue date'
);

-- The issue dates of the dogs from before them

reset role;
update public.packs set deleted_at = now() where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
insert into public.dogs (id, pack_id, name, added_at) values
  ('a0000000-0000-0000-0000-000000000003', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Rex', null);
update public.dogs set added_at = null where pack_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
insert into public.walks (id, pack_id, started_at, ended_at, deleted_at) values
  ('a1000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '2026-03-02 09:00+01', '2026-03-02 10:00+01', null),
  ('a1000000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '2026-02-01 09:00+01', '2026-02-01 10:00+01', null),
  ('a1000000-0000-0000-0000-000000000003', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '2026-01-01 09:00+01', '2026-01-01 10:00+01', '2026-01-02 09:00+01');
insert into public.walk_dogs (id, pack_id, walk_id, dog_id, deleted_at) values
  -- Bello walked on 2 March and 1 February, and a deleted walk on 1 January.
  ('a2000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'a1000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', null),
  ('a2000000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'a1000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', null),
  ('a2000000-0000-0000-0000-000000000003', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'a1000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', null),
  -- Luna was taken off the walk of 1 February, and walked on 2 March.
  ('a2000000-0000-0000-0000-000000000004', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'a1000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000002', '2026-02-02 09:00+01'),
  ('a2000000-0000-0000-0000-000000000005', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'a1000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002', null);

select public.fill_missing_issue_dates();

select results_eq(
  $$ select name, added_at from public.dogs where pack_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and name <> 'Rex' order by name $$,
  $$ values ('Bello', '2026-02-01 09:00+01'::timestamptz), ('Luna', '2026-03-02 09:00+01'::timestamptz) $$,
  'A dog gets the start of its first walk, without deleted walks and dogs taken off a walk'
);
select is(
  (select added_at from public.dogs where id = 'a0000000-0000-0000-0000-000000000003'), now(),
  'A dog without a walk gets the time of the migration'
);
select is(
  (select added_at from public.dogs where id = 'b0000000-0000-0000-0000-000000000001'), null,
  'A dog of a pack that has disappeared keeps no issue date, because nobody sees it'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select throws_ok(
  $$ select public.fill_missing_issue_dates() $$,
  '42501', null,
  'A member cannot fill the issue dates'
);

select * from finish();
rollback;
