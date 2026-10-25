-- The identity page of the passport (#158): the date of birth and the issue
-- date of a dog.
--
-- The date of birth is optional, and any member of the pack sets it. The
-- issue date is the time when a member added the dog to the app, and the
-- phone that adds the dog sets it. A phone from before the issue dates
-- uploads a new dog without it, so the dog gets the time of its upload.

alter table public.dogs
  add column born_on date,
  add column added_at timestamptz default now();

-- Gives each dog without an issue date the start of its first walk, or the
-- time of the call when it has no walk. Each such dog changes, so that the
-- phones download it again. The migration calls it once.
create function public.fill_missing_issue_dates() returns void
language sql
set search_path = ''
as $$
  update public.dogs
  set added_at = coalesce(
    (select min(walks.started_at)
       from public.walk_dogs
       join public.walks on walks.id = walk_dogs.walk_id
       where walk_dogs.dog_id = dogs.id
         and walk_dogs.deleted_at is null
         and walks.deleted_at is null),
    now())
  where added_at is null;
$$;

revoke execute on function public.fill_missing_issue_dates() from public, anon, authenticated;

select public.fill_missing_issue_dates();
