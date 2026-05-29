create or replace function public.teacher_can_access_class(input_class_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.classes c
    join public.user_access ua
      on ua.user_id = c.teacher_in_charge
    join public.users u
      on u.id = c.teacher_in_charge
    where c.id = input_class_id
      and ua.auth_user_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('teacher', 'headteacher')
  );
$$;

grant execute on function public.teacher_can_access_class(uuid) to authenticated;

create or replace function public.get_teacher_curriculum_completed_today(
  input_class_id uuid,
  input_local_date date
)
returns boolean
language sql
security definer
set search_path = public
as $$
  select public.teacher_can_access_class(input_class_id)
    and exists (
      select 1
      from public.curriculum c
      where c.class_id = input_class_id
        and (c.created_at at time zone 'Europe/Athens')::date = input_local_date
    );
$$;

grant execute on function public.get_teacher_curriculum_completed_today(uuid, date)
to authenticated;

create or replace function public.get_teacher_student_completion_today(
  input_class_id uuid,
  input_local_date date
)
returns table (
  student_language_id uuid,
  completion_message text
)
language sql
security definer
set search_path = public
as $$
  select
    sl.id as student_language_id,
    case
      when exists (
        select 1
        from public.absences a
        where a.student_language_id = sl.id
          and (a.created_at at time zone 'Europe/Athens')::date = input_local_date
      ) then 'Η απουσία καταχωρήθηκε'
      when exists (
        select 1
        from public.students_grades sg
        where sg.student_language_id = sl.id
          and (sg.created_at at time zone 'Europe/Athens')::date = input_local_date
      ) then 'Οι βαθμοί καταχωρήθηκαν'
      else null
    end as completion_message
  from public.students_language sl
  where sl.class_id = input_class_id
    and public.teacher_can_access_class(input_class_id)
    and (
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
    );
$$;

grant execute on function public.get_teacher_student_completion_today(uuid, date)
to authenticated;
