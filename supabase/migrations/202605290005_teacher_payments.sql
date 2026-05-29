create or replace function public.current_user_is_teacher()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_access ua
    join public.users u
      on u.id = ua.user_id
    where ua.auth_user_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('teacher', 'headteacher')
  );
$$;

grant execute on function public.current_user_is_teacher() to authenticated;

drop function if exists public.get_teacher_payment_rows();

create or replace function public.get_teacher_payment_rows()
returns table (
  user_id uuid,
  user_name text,
  payment numeric,
  september boolean,
  october boolean,
  november boolean,
  december boolean,
  january boolean,
  february boolean,
  march boolean,
  april boolean,
  may boolean,
  june boolean,
  july boolean,
  august boolean
)
language sql
security definer
set search_path = public
as $$
  select
    p.user_id,
    p.user_name,
    u.payment,
    coalesce(p.september, false) as september,
    coalesce(p.october, false) as october,
    coalesce(p.november, false) as november,
    coalesce(p.december, false) as december,
    coalesce(p.january, false) as january,
    coalesce(p.february, false) as february,
    coalesce(p.march, false) as march,
    coalesce(p.april, false) as april,
    coalesce(p.may, false) as may,
    coalesce(p.june, false) as june,
    coalesce(p.july, false) as july,
    coalesce(p.august, false) as august
  from public.payments p
  left join public.users u
    on u.id = p.user_id
  where public.current_user_is_teacher()
  order by lower(p.user_name), p.user_name;
$$;

grant execute on function public.get_teacher_payment_rows() to authenticated;

create or replace function public.update_teacher_payment_month(
  input_user_id uuid,
  input_month text,
  input_paid boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_month text;
begin
  if not public.current_user_is_teacher() then
    raise exception 'not allowed';
  end if;

  normalized_month := lower(trim(input_month));

  if normalized_month not in (
    'september',
    'october',
    'november',
    'december',
    'january',
    'february',
    'march',
    'april',
    'may',
    'june',
    'july',
    'august'
  ) then
    raise exception 'invalid month';
  end if;

  execute format(
    'update public.payments set %I = $1 where user_id = $2',
    normalized_month
  )
  using coalesce(input_paid, false), input_user_id;
end;
$$;

grant execute on function public.update_teacher_payment_month(uuid, text, boolean)
to authenticated;
