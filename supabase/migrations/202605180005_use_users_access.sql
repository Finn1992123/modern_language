create table if not exists public.user_access (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),

  user_id uuid not null references public.users(id) on delete cascade,
  auth_user_id uuid not null references auth.users(id) on delete cascade,

  access_role text not null default 'parent'
    check (access_role in ('parent', 'student', 'mother', 'father', 'guardian')),

  unique (user_id, auth_user_id)
);

create index if not exists user_access_auth_user_id_idx
on public.user_access(auth_user_id);

create index if not exists user_access_user_id_idx
on public.user_access(user_id);

alter table public.user_access enable row level security;

drop policy if exists "Users can view their own access"
on public.user_access;

create policy "Users can view their own access"
on public.user_access
for select
to authenticated
using (auth_user_id = auth.uid());

do $$
begin
  if to_regclass('public.user_auth_connections') is not null then
    execute '
      insert into public.user_access (user_id, auth_user_id)
      select user_id, auth_user_id
      from public.user_auth_connections
      on conflict (user_id, auth_user_id) do nothing
    ';
  end if;

  if to_regclass('public.users_access') is not null then
    execute '
      insert into public.user_access (user_id, auth_user_id, access_role)
      select user_id, auth_user_id, access_role
      from public.users_access
      on conflict (user_id, auth_user_id) do nothing
    ';
  end if;
end;
$$;

create or replace function public.link_user_by_connect_code(input_connect_code text)
returns public.users
language plpgsql
security definer
set search_path = public
as $$
declare
  linked_user public.users;
  normalized_connect_code text;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  normalized_connect_code := upper(trim(input_connect_code));

  if normalized_connect_code = '' then
    raise exception 'connect code is required';
  end if;

  select *
  into linked_user
  from public.users
  where upper(connect_code) = normalized_connect_code
  limit 1;

  if linked_user.id is null then
    raise exception 'connect code not found';
  end if;

  insert into public.user_access (
    user_id,
    auth_user_id,
    access_role
  )
  values (
    linked_user.id,
    auth.uid(),
    'parent'
  )
  on conflict (user_id, auth_user_id) do nothing;

  return linked_user;
end;
$$;

create or replace function public.current_linked_user()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  linked_user jsonb;
begin
  if auth.uid() is null then
    return null;
  end if;

  select to_jsonb(users.*)
  into linked_user
  from public.users
  inner join public.user_access
    on user_access.user_id = users.id
  where user_access.auth_user_id = auth.uid()
  order by user_access.created_at
  limit 1;

  return linked_user;
end;
$$;

grant execute on function public.link_user_by_connect_code(text) to authenticated;
grant execute on function public.current_linked_user() to authenticated;

drop policy if exists "Users can read accessible users"
on public.users;

create policy "Users can read accessible users"
on public.users
for select
to authenticated
using (
  exists (
    select 1
    from public.user_access
    where user_access.user_id = users.id
      and user_access.auth_user_id = auth.uid()
  )
);

drop policy if exists "Users can read accessible students"
on public.students;

create policy "Users can read accessible students"
on public.students
for select
to authenticated
using (
  exists (
    select 1
    from public.user_access
    where user_access.user_id = students.user_id
      and user_access.auth_user_id = auth.uid()
  )
);
