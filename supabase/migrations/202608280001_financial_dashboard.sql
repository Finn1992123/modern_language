-- Headteacher-only financial dashboard and expense tracking.
-- The existing payment booleans represent one academic year (September-August)
-- and intentionally do not provide historical payment data.

create or replace function public.current_user_is_headteacher()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_access ua
    join public.users u on u.id = ua.user_id
    where ua.auth_user_id = auth.uid()
      and lower(trim(coalesce(u.role, ''))) = 'headteacher'
  );
$$;

revoke all on function public.current_user_is_headteacher() from public, anon;
grant execute on function public.current_user_is_headteacher() to authenticated;

create or replace function public.current_headteacher_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select u.id
  from public.user_access ua
  join public.users u on u.id = ua.user_id
  where ua.auth_user_id = auth.uid()
    and lower(trim(coalesce(u.role, ''))) = 'headteacher'
  order by ua.created_at
  limit 1;
$$;

revoke all on function public.current_headteacher_id() from public, anon;
grant execute on function public.current_headteacher_id() to authenticated;

-- Replace the existing teacher-wide functions with headteacher-only versions
-- and exclude staff from financial rows.
drop function if exists public.get_teacher_payment_rows();

create function public.get_teacher_payment_rows()
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
    coalesce(p.september, false),
    coalesce(p.october, false),
    coalesce(p.november, false),
    coalesce(p.december, false),
    coalesce(p.january, false),
    coalesce(p.february, false),
    coalesce(p.march, false),
    coalesce(p.april, false),
    coalesce(p.may, false),
    coalesce(p.june, false),
    coalesce(p.july, false),
    coalesce(p.august, false)
  from public.payments p
  join public.users u on u.id = p.user_id
  where public.current_user_is_headteacher()
    and lower(trim(coalesce(u.role, ''))) in ('parent', 'student')
    and coalesce(u.payment, 0) > 0
  order by lower(p.user_name), p.user_name;
$$;

revoke all on function public.get_teacher_payment_rows() from public, anon;
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
  normalized_month text := lower(trim(coalesce(input_month, '')));
begin
  if not public.current_user_is_headteacher() then
    raise exception 'Only a headteacher can update payments';
  end if;

  if normalized_month not in (
    'september', 'october', 'november', 'december', 'january', 'february',
    'march', 'april', 'may', 'june', 'july', 'august'
  ) then
    raise exception 'Invalid payment month';
  end if;

  if not exists (
    select 1
    from public.users u
    where u.id = input_user_id
      and lower(trim(coalesce(u.role, ''))) in ('parent', 'student')
      and coalesce(u.payment, 0) > 0
  ) then
    raise exception 'Invalid payment account';
  end if;

  -- The identifier comes from the fixed allow-list above, never directly from
  -- unchecked user input.
  execute format(
    'update public.payments set %I = $1 where user_id = $2',
    normalized_month
  ) using coalesce(input_paid, false), input_user_id;
end;
$$;

revoke all on function public.update_teacher_payment_month(uuid, text, boolean)
from public, anon;
grant execute on function public.update_teacher_payment_month(uuid, text, boolean)
to authenticated;

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  expense_date date not null,
  amount numeric(12, 2) not null check (amount > 0),
  category text not null check (
    char_length(trim(category)) between 1 and 80
  ),
  description text check (
    description is null or char_length(trim(description)) <= 1000
  ),
  created_by uuid not null references public.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists expenses_date_idx
on public.expenses(expense_date desc);

create index if not exists expenses_created_by_idx
on public.expenses(created_by);

alter table public.expenses enable row level security;

drop policy if exists "Headteachers can read expenses" on public.expenses;
create policy "Headteachers can read expenses"
on public.expenses for select to authenticated
using (public.current_user_is_headteacher());

drop policy if exists "Headteachers can insert expenses" on public.expenses;
create policy "Headteachers can insert expenses"
on public.expenses for insert to authenticated
with check (
  public.current_user_is_headteacher()
  and created_by = public.current_headteacher_id()
);

drop policy if exists "Headteachers can update expenses" on public.expenses;
create policy "Headteachers can update expenses"
on public.expenses for update to authenticated
using (public.current_user_is_headteacher())
with check (
  public.current_user_is_headteacher()
  and created_by = public.current_headteacher_id()
);

drop policy if exists "Headteachers can delete expenses" on public.expenses;
create policy "Headteachers can delete expenses"
on public.expenses for delete to authenticated
using (public.current_user_is_headteacher());

revoke all on table public.expenses from public, anon, authenticated;

create or replace function public.get_financial_expenses(
  input_academic_year integer,
  input_month integer
)
returns table (
  id uuid,
  expense_date date,
  amount numeric,
  category text,
  description text,
  created_by uuid,
  created_by_name text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_year integer;
  month_start date;
begin
  if not public.current_user_is_headteacher() then
    raise exception 'Only a headteacher can read expenses';
  end if;

  if input_month not between 1 and 12 then
    raise exception 'Invalid month';
  end if;

  selected_year := case when input_month >= 9
    then input_academic_year else input_academic_year + 1 end;
  month_start := make_date(selected_year, input_month, 1);

  return query
  select
    e.id,
    e.expense_date,
    e.amount,
    e.category,
    e.description,
    e.created_by,
    concat_ws(' ', u.name, u.surname),
    e.created_at,
    e.updated_at
  from public.expenses e
  join public.users u on u.id = e.created_by
  where e.expense_date >= month_start
    and e.expense_date < (month_start + interval '1 month')::date
  order by e.expense_date desc, e.created_at desc;
end;
$$;

revoke all on function public.get_financial_expenses(integer, integer)
from public, anon;
grant execute on function public.get_financial_expenses(integer, integer)
to authenticated;

create or replace function public.save_financial_expense(
  input_id uuid,
  input_expense_date date,
  input_amount numeric,
  input_category text,
  input_description text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  staff_id uuid := public.current_headteacher_id();
  saved_id uuid;
  normalized_category text := trim(coalesce(input_category, ''));
  normalized_description text := nullif(trim(coalesce(input_description, '')), '');
begin
  if staff_id is null then
    raise exception 'Only a headteacher can save expenses';
  end if;

  if input_expense_date is null then
    raise exception 'Expense date is required';
  end if;

  if input_amount is null or input_amount <= 0 then
    raise exception 'Expense amount must be positive';
  end if;

  if char_length(normalized_category) not between 1 and 80 then
    raise exception 'Expense category must contain 1 to 80 characters';
  end if;

  if normalized_description is not null
     and char_length(normalized_description) > 1000 then
    raise exception 'Expense description is too long';
  end if;

  if input_id is null then
    insert into public.expenses (
      expense_date, amount, category, description, created_by
    ) values (
      input_expense_date,
      round(input_amount, 2),
      normalized_category,
      normalized_description,
      staff_id
    ) returning id into saved_id;
  else
    update public.expenses
    set expense_date = input_expense_date,
        amount = round(input_amount, 2),
        category = normalized_category,
        description = normalized_description,
        updated_at = now()
    where id = input_id
    returning id into saved_id;

    if saved_id is null then
      raise exception 'Expense not found';
    end if;
  end if;

  return saved_id;
end;
$$;

revoke all on function public.save_financial_expense(uuid, date, numeric, text, text)
from public, anon;
grant execute on function public.save_financial_expense(uuid, date, numeric, text, text)
to authenticated;

create or replace function public.delete_financial_expense(input_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.current_user_is_headteacher() then
    raise exception 'Only a headteacher can delete expenses';
  end if;

  delete from public.expenses where id = input_id;
  if not found then
    raise exception 'Expense not found';
  end if;
end;
$$;

revoke all on function public.delete_financial_expense(uuid) from public, anon;
grant execute on function public.delete_financial_expense(uuid) to authenticated;

create or replace function public.get_financial_dashboard(
  input_academic_year integer,
  input_month integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  athens_today date := (now() at time zone 'Europe/Athens')::date;
  current_academic_year integer := case
    when extract(month from athens_today) >= 9
      then extract(year from athens_today)::integer
    else extract(year from athens_today)::integer - 1
  end;
  selected_calendar_year integer;
  selected_month_start date;
  selected_month_column text;
  result jsonb;
begin
  if not public.current_user_is_headteacher() then
    raise exception 'Only a headteacher can read financial data';
  end if;

  if input_academic_year <> current_academic_year then
    raise exception 'Payment history is only available for the current academic year';
  end if;

  if input_month not between 1 and 12 then
    raise exception 'Invalid month';
  end if;

  selected_calendar_year := case when input_month >= 9
    then input_academic_year else input_academic_year + 1 end;
  selected_month_start := make_date(selected_calendar_year, input_month, 1);
  selected_month_column := case input_month
    when 1 then 'january' when 2 then 'february' when 3 then 'march'
    when 4 then 'april' when 5 then 'may' when 6 then 'june'
    when 7 then 'july' when 8 then 'august' when 9 then 'september'
    when 10 then 'october' when 11 then 'november' when 12 then 'december'
  end;

  with eligible as (
    select
      u.id,
      coalesce(nullif(trim(p.user_name), ''), concat_ws(' ', u.name, u.surname)) as user_name,
      u.payment::numeric as payment,
      case selected_month_column
        when 'january' then coalesce(p.january, false)
        when 'february' then coalesce(p.february, false)
        when 'march' then coalesce(p.march, false)
        when 'april' then coalesce(p.april, false)
        when 'may' then coalesce(p.may, false)
        when 'june' then coalesce(p.june, false)
        when 'july' then coalesce(p.july, false)
        when 'august' then coalesce(p.august, false)
        when 'september' then coalesce(p.september, false)
        when 'october' then coalesce(p.october, false)
        when 'november' then coalesce(p.november, false)
        when 'december' then coalesce(p.december, false)
      end as selected_paid
    from public.users u
    left join public.payments p on p.user_id = u.id
    where lower(trim(coalesce(u.role, ''))) in ('parent', 'student')
      and coalesce(u.payment, 0) > 0
  ),
  totals as (
    select
      coalesce(sum(payment), 0)::numeric as expected,
      coalesce(sum(payment) filter (where selected_paid), 0)::numeric as received,
      count(*) filter (where not selected_paid)::integer as debtor_count
    from eligible
  ),
  debtors as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'user_id', id,
      'user_name', user_name,
      'payment', payment,
      'month', selected_month_column
    ) order by lower(user_name), user_name), '[]'::jsonb) as rows
    from eligible
    where not selected_paid
  ),
  academic_months as (
    select * from (values
      (9, 'september', 'Σεπτέμβριος'), (10, 'october', 'Οκτώβριος'),
      (11, 'november', 'Νοέμβριος'), (12, 'december', 'Δεκέμβριος'),
      (1, 'january', 'Ιανουάριος'), (2, 'february', 'Φεβρουάριος'),
      (3, 'march', 'Μάρτιος'), (4, 'april', 'Απρίλιος'),
      (5, 'may', 'Μάιος'), (6, 'june', 'Ιούνιος'),
      (7, 'july', 'Ιούλιος'), (8, 'august', 'Αύγουστος')
    ) as m(month_number, column_name, month_label)
  ),
  overdue_detail as (
    select
      u.id,
      coalesce(nullif(trim(p.user_name), ''), concat_ws(' ', u.name, u.surname)) as user_name,
      u.payment::numeric as payment,
      m.month_number,
      m.month_label,
      case when m.month_number >= 9 then input_academic_year
           else input_academic_year + 1 end as calendar_year
    from public.users u
    left join public.payments p on p.user_id = u.id
    cross join academic_months m
    where lower(trim(coalesce(u.role, ''))) in ('parent', 'student')
      and coalesce(u.payment, 0) > 0
      and make_date(
        case when m.month_number >= 9 then input_academic_year
             else input_academic_year + 1 end,
        m.month_number,
        1
      ) < date_trunc('month', athens_today)::date
      and not case m.column_name
        when 'january' then coalesce(p.january, false)
        when 'february' then coalesce(p.february, false)
        when 'march' then coalesce(p.march, false)
        when 'april' then coalesce(p.april, false)
        when 'may' then coalesce(p.may, false)
        when 'june' then coalesce(p.june, false)
        when 'july' then coalesce(p.july, false)
        when 'august' then coalesce(p.august, false)
        when 'september' then coalesce(p.september, false)
        when 'october' then coalesce(p.october, false)
        when 'november' then coalesce(p.november, false)
        when 'december' then coalesce(p.december, false)
      end
  ),
  repeated_debtors as (
    select coalesce(jsonb_agg(row_data order by lower(row_data->>'user_name')), '[]'::jsonb) as rows
    from (
      select jsonb_build_object(
        'user_id', id,
        'user_name', max(user_name),
        'unpaid_count', count(*)::integer,
        'unpaid_months', jsonb_agg(
          month_label || ' ' || calendar_year
          order by calendar_year, month_number
        ),
        'estimated_debt', max(payment) * count(*)
      ) as row_data
      from overdue_detail
      group by id
      having count(*) > 1
    ) grouped
  ),
  expense_total as (
    select coalesce(sum(e.amount), 0)::numeric as amount
    from public.expenses e
    where e.expense_date >= selected_month_start
      and e.expense_date < (selected_month_start + interval '1 month')::date
  )
  select jsonb_build_object(
    'academic_year', input_academic_year,
    'calendar_year', selected_calendar_year,
    'month', input_month,
    'month_column', selected_month_column,
    'expected', t.expected,
    'received', t.received,
    'outstanding', t.expected - t.received,
    'debtor_count', t.debtor_count,
    'expenses', x.amount,
    'net_profit', t.received - x.amount,
    'debtors', d.rows,
    'repeated_debtors', r.rows
  ) into result
  from totals t
  cross join debtors d
  cross join repeated_debtors r
  cross join expense_total x;

  return result;
end;
$$;

revoke all on function public.get_financial_dashboard(integer, integer)
from public, anon;
grant execute on function public.get_financial_dashboard(integer, integer)
to authenticated;
