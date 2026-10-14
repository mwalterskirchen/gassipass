-- The members of a pack read the files of each pack that moved into it
-- (#105).
--
-- When the only member of a pack joins another pack, their GPS tracks and
-- photos stay in the folder of the old pack, because SQL cannot move a
-- file. The moved rows keep their paths, and the members of the new pack
-- read the files there. A phone that changes such a row uploads its file
-- into the folder of the new pack.

create or replace function public.move_pack(old_pack uuid, new_pack uuid) returns void
language plpgsql
set search_path = ''
as $$
begin
  set constraints public.walk_dogs_walk_id_pack_id_fkey, public.walk_dogs_dog_id_pack_id_fkey,
    public.completed_areas_dog_id_pack_id_fkey, public.completed_streets_dog_id_pack_id_fkey deferred;
  update public.dogs set pack_id = new_pack where pack_id = old_pack;
  update public.walks set pack_id = new_pack where pack_id = old_pack;
  update public.walk_dogs set pack_id = new_pack where pack_id = old_pack;
  update public.completed_areas set pack_id = new_pack where pack_id = old_pack;
  update public.completed_streets set pack_id = new_pack where pack_id = old_pack;
  set constraints public.walk_dogs_walk_id_pack_id_fkey, public.walk_dogs_dog_id_pack_id_fkey,
    public.completed_areas_dog_id_pack_id_fkey, public.completed_streets_dog_id_pack_id_fkey immediate;
  update public.packs set deleted_at = now(), moved_into = new_pack where id = old_pack;
end;
$$;

-- Whether the calling person reads the files in the folder: the folder of
-- their pack, or of a pack that moved into it. It reads the packs as the
-- definer, because a member cannot read a pack that has disappeared.
create function public.can_read_files_in(folder text) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select folder = (select public.pack_of_caller())::text
    or exists (
      select from public.packs
      where packs.id::text = folder and packs.moved_into = (select public.pack_of_caller())
    );
$$;

revoke execute on function public.can_read_files_in(text) from public, anon;
grant execute on function public.can_read_files_in(text) to authenticated;

drop policy "A member reads the files of their pack" on storage.objects;
create policy "A member reads the files of their pack" on storage.objects
  for select to authenticated
  using (bucket_id in ('tracks', 'dog-photos')
    and public.can_read_files_in((storage.foldername(name))[1]));
