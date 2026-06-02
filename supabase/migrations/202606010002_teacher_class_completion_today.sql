create or replace function public.get_teacher_class_completion_today(
  input_local_date date
)
returns table (
  class_id uuid,
  is_completed boolean
)
language sql
security definer
set search_path = public
as $$
  select
    c.id as class_id,
    (
      exists (
        select 1
        from public.curriculum cur
        where cur.class_id = c.id
          and (cur.created_at at time zone 'Europe/Athens')::date = input_local_date
      )
      and exists (
        select 1
        from public.students_language sl_any
        where sl_any.class_id = c.id
      )
      and not exists (
        select 1
        from public.students_language sl
        where sl.class_id = c.id
          and not (
            exists (
              select 1
              from public.absences a
              where a.student_language_id = sl.id
                and (a.created_at at time zone 'Europe/Athens')::date = input_local_date
            )
            or exists (
              select 1
              from public.students_grades sg
              where sg.student_language_id = sl.id
                and (sg.created_at at time zone 'Europe/Athens')::date = input_local_date
            )
          )
      )
    ) as is_completed
  from public.classes c
  join public.user_access ua
    on ua.user_id = c.teacher_in_charge
  join public.users u
    on u.id = c.teacher_in_charge
  where ua.auth_user_id = auth.uid()
    and lower(coalesce(u.role, '')) in ('teacher', 'headteacher')
  order by c.language, c.days_hours;
$$;

grant execute on function public.get_teacher_class_completion_today(date)
to authenticated;
