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
      'children_names', (
        select coalesce(jsonb_agg(trim(s.name) order by lower(trim(s.name)), s.id), '[]'::jsonb)
        from public.students s
        where s.user_id = eligible.id
          and nullif(trim(s.name), '') is not null
      ),
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
