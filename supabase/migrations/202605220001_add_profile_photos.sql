alter table public.users
add column if not exists profile_pic text;

alter table public.students
add column if not exists profile_pic text;

insert into storage.buckets (id, name, public)
values ('profile-pictures', 'profile-pictures', true)
on conflict (id) do update
set public = excluded.public;

drop policy if exists "Anyone can read profile pictures"
on storage.objects;

create policy "Anyone can read profile pictures"
on storage.objects
for select
to public
using (bucket_id = 'profile-pictures');

drop policy if exists "Users can upload profile pictures"
on storage.objects;

create policy "Users can upload profile pictures"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'profile-pictures'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Users can update profile pictures"
on storage.objects;

create policy "Users can update profile pictures"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'profile-pictures'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'profile-pictures'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Users can delete profile pictures"
on storage.objects;

create policy "Users can delete profile pictures"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'profile-pictures'
  and (storage.foldername(name))[1] = auth.uid()::text
);

grant update (profile_pic) on public.users to authenticated;
grant update (profile_pic) on public.students to authenticated;

drop policy if exists "Users can update accessible user profile pictures"
on public.users;

create policy "Users can update accessible user profile pictures"
on public.users
for update
to authenticated
using (
  exists (
    select 1
    from public.user_access
    where user_access.user_id = users.id
      and user_access.auth_user_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.user_access
    where user_access.user_id = users.id
      and user_access.auth_user_id = auth.uid()
  )
);

drop policy if exists "Users can update accessible student profile pictures"
on public.students;

create policy "Users can update accessible student profile pictures"
on public.students
for update
to authenticated
using (
  exists (
    select 1
    from public.user_access
    where user_access.user_id = students.user_id
      and user_access.auth_user_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.user_access
    where user_access.user_id = students.user_id
      and user_access.auth_user_id = auth.uid()
  )
);
