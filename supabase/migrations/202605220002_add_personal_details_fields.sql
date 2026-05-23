alter table public.users
add column if not exists surname text;

alter table public.users
add column if not exists email text;

alter table public.users
add column if not exists phone_number text;

alter table public.users
add column if not exists emergency_contact text;

alter table public.users
add column if not exists alternative_email text;

grant update (
  name,
  surname,
  email,
  phone_number,
  emergency_contact,
  alternative_email
) on public.users to authenticated;

drop policy if exists "Users can update accessible user details"
on public.users;

create policy "Users can update accessible user details"
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
