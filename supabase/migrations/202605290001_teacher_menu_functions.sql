drop function if exists public.get_teacher_classes();

create or replace function public.get_teacher_classes()
returns table (
  id uuid,
  name text,
  language text,
  days_hours text
)
language sql
security definer
set search_path = public
as $$
  select
    c.id,
    c.name,
    c.language,
    c.days_hours
  from public.classes c
  join public.user_access ua
    on ua.user_id = c.teacher_in_charge
  join public.users u
    on u.id = c.teacher_in_charge
  where ua.auth_user_id = auth.uid()
    and lower(coalesce(u.role, '')) in ('teacher', 'headteacher')
  order by c.language, c.days_hours;
$$;

grant execute on function public.get_teacher_classes() to authenticated;

create or replace function public.get_teacher_class_students(input_class_id uuid)
returns table (
  student_language_id uuid,
  student_id uuid,
  student_name text
)
language sql
security definer
set search_path = public
as $$
  select
    sl.id as student_language_id,
    s.id as student_id,
    s.name as student_name
  from public.students_language sl
  join public.students s
    on s.id = sl.student_id
  where sl.class_id = input_class_id
    and exists (
      select 1
      from public.classes c
      join public.user_access ua
        on ua.user_id = c.teacher_in_charge
      join public.users u
        on u.id = c.teacher_in_charge
      where c.id = input_class_id
        and ua.auth_user_id = auth.uid()
        and lower(coalesce(u.role, '')) in ('teacher', 'headteacher')
    )
  order by s.name;
$$;

grant execute on function public.get_teacher_class_students(uuid) to authenticated;

create or replace function public.get_teacher_student_grade_averages(
  input_student_language_id uuid
)
returns table (
  reading numeric,
  vocabulary numeric,
  grammar numeric,
  writing numeric,
  listening numeric,
  speaking numeric,
  homework numeric,
  effort numeric
)
language sql
security definer
set search_path = public
as $$
  select
    round(avg(sg.reading)::numeric, 2) as reading,
    round(avg(sg.vocabulary)::numeric, 2) as vocabulary,
    round(avg(sg.grammar)::numeric, 2) as grammar,
    round(avg(sg.writing)::numeric, 2) as writing,
    round(avg(sg.listening)::numeric, 2) as listening,
    round(avg(sg.speaking)::numeric, 2) as speaking,
    round(avg(sg.homework)::numeric, 2) as homework,
    round(avg(sg.effort)::numeric, 2) as effort
  from public.students_grades sg
  where sg.student_language_id = input_student_language_id
    and exists (
      select 1
      from public.students_language sl
      join public.classes c
        on c.id = sl.class_id
      join public.user_access ua
        on ua.user_id = c.teacher_in_charge
      join public.users u
        on u.id = c.teacher_in_charge
      where sl.id = input_student_language_id
        and ua.auth_user_id = auth.uid()
        and lower(coalesce(u.role, '')) in ('teacher', 'headteacher')
    );
$$;

grant execute on function public.get_teacher_student_grade_averages(uuid) to authenticated;

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

create or replace function public.insert_teacher_curriculum(
  input_class_id uuid,
  input_for_date date,
  input_in_class text,
  input_homework text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.classes c
    join public.user_access ua
      on ua.user_id = c.teacher_in_charge
    join public.users u
      on u.id = c.teacher_in_charge
    where c.id = input_class_id
      and ua.auth_user_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('teacher', 'headteacher')
  ) then
    raise exception 'not allowed';
  end if;

  insert into public.curriculum (
    class_id,
    for_date,
    in_class,
    homework
  )
  values (
    input_class_id,
    input_for_date,
    nullif(trim(input_in_class), ''),
    nullif(trim(input_homework), '')
  );
end;
$$;

grant execute on function public.insert_teacher_curriculum(uuid, date, text, text)
to authenticated;

create or replace function public.insert_teacher_absence(
  input_student_language_id uuid,
  input_student_id uuid,
  input_student_name text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.students_language sl
    join public.classes c
      on c.id = sl.class_id
    join public.user_access ua
      on ua.user_id = c.teacher_in_charge
    join public.users u
      on u.id = c.teacher_in_charge
    where sl.id = input_student_language_id
      and sl.student_id = input_student_id
      and ua.auth_user_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('teacher', 'headteacher')
  ) then
    raise exception 'not allowed';
  end if;

  insert into public.absences (
    student_language_id,
    student_id,
    student_name
  )
  values (
    input_student_language_id,
    input_student_id,
    nullif(trim(input_student_name), '')
  );
end;
$$;

grant execute on function public.insert_teacher_absence(uuid, uuid, text)
to authenticated;

create or replace function public.insert_teacher_student_grades(
  input_student_language_id uuid,
  input_student_id uuid,
  input_student_name text,
  input_reading numeric,
  input_vocabulary numeric,
  input_grammar numeric,
  input_writing numeric,
  input_listening numeric,
  input_speaking numeric,
  input_homework numeric,
  input_effort numeric,
  input_comments text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.students_language sl
    join public.classes c
      on c.id = sl.class_id
    join public.user_access ua
      on ua.user_id = c.teacher_in_charge
    join public.users u
      on u.id = c.teacher_in_charge
    where sl.id = input_student_language_id
      and sl.student_id = input_student_id
      and ua.auth_user_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('teacher', 'headteacher')
  ) then
    raise exception 'not allowed';
  end if;

  insert into public.students_grades (
    student_language_id,
    student_id,
    student_name,
    reading,
    vocabulary,
    grammar,
    writing,
    listening,
    speaking,
    homework,
    effort,
    comments
  )
  values (
    input_student_language_id,
    input_student_id,
    nullif(trim(input_student_name), ''),
    case
      when input_reading is null then null
      else least(greatest(input_reading, 0), 100)
    end,
    case
      when input_vocabulary is null then null
      else least(greatest(input_vocabulary, 0), 100)
    end,
    case
      when input_grammar is null then null
      else least(greatest(input_grammar, 0), 100)
    end,
    case
      when input_writing is null then null
      else least(greatest(input_writing, 0), 100)
    end,
    case
      when input_listening is null then null
      else least(greatest(input_listening, 0), 100)
    end,
    case
      when input_speaking is null then null
      else least(greatest(input_speaking, 0), 100)
    end,
    case
      when input_homework is null then null
      else least(greatest(input_homework, 0), 100)
    end,
    case
      when input_effort is null then null
      else least(greatest(input_effort, 0), 100)
    end,
    nullif(trim(input_comments), '')
  );
end;
$$;

grant execute on function public.insert_teacher_student_grades(
  uuid,
  uuid,
  text,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  text
) to authenticated;
