alter table public.users
add column if not exists connect_code text;

alter table public.users
add column if not exists auth_user_id uuid references auth.users(id) on delete set null;

create unique index if not exists users_connect_code_key
on public.users(upper(connect_code))
where connect_code is not null;

create unique index if not exists users_auth_user_id_key
on public.users(auth_user_id)
where auth_user_id is not null;

create table if not exists public.user_auth_connections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_id, auth_user_id)
);

create index if not exists user_auth_connections_auth_user_id_idx
on public.user_auth_connections(auth_user_id);

alter table public.user_auth_connections enable row level security;

drop policy if exists "Users can view their own auth connections"
on public.user_auth_connections;

create policy "Users can view their own auth connections"
on public.user_auth_connections
for select
to authenticated
using (auth_user_id = auth.uid());

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

  update public.users
  set auth_user_id = auth.uid()
  where id = linked_user.id
    and auth_user_id is null;

  insert into public.user_auth_connections (user_id, auth_user_id)
  values (linked_user.id, auth.uid())
  on conflict (user_id, auth_user_id) do nothing;

  return linked_user;
end;
$$;

grant execute on function public.link_user_by_connect_code(text) to authenticated;
