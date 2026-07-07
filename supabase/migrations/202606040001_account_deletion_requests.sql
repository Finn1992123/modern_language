create table if not exists public.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  auth_user_id uuid not null references auth.users(id) on delete cascade,
  user_id uuid references public.users(id) on delete set null,
  reason text,
  status text not null default 'pending'
    check (status in ('pending', 'in_review', 'completed', 'rejected')),

  unique (auth_user_id, status)
);

create index if not exists account_deletion_requests_auth_user_id_idx
on public.account_deletion_requests(auth_user_id);

create index if not exists account_deletion_requests_user_id_idx
on public.account_deletion_requests(user_id);

alter table public.account_deletion_requests enable row level security;

drop policy if exists "Users can view their own deletion requests"
on public.account_deletion_requests;

create policy "Users can view their own deletion requests"
on public.account_deletion_requests
for select
to authenticated
using (auth_user_id = auth.uid());

create or replace function public.request_account_deletion(input_reason text default null)
returns public.account_deletion_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  linked_user_id uuid;
  request_row public.account_deletion_requests;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select user_access.user_id
  into linked_user_id
  from public.user_access
  where user_access.auth_user_id = auth.uid()
  order by user_access.created_at
  limit 1;

  insert into public.account_deletion_requests (
    auth_user_id,
    user_id,
    reason,
    status,
    updated_at
  )
  values (
    auth.uid(),
    linked_user_id,
    nullif(trim(input_reason), ''),
    'pending',
    now()
  )
  on conflict (auth_user_id, status)
  do update set
    user_id = excluded.user_id,
    reason = excluded.reason,
    updated_at = now()
  returning *
  into request_row;

  return request_row;
end;
$$;

grant execute on function public.request_account_deletion(text) to authenticated;
