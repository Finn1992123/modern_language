drop function if exists public.get_student_language_averages(uuid);

create or replace function public.get_student_language_averages(input_student_id uuid)
returns table (
  class_id uuid,
  language text,
  days_hours text,
  reading numeric,
  vocabulary numeric,
  grammar numeric,
  writing numeric,
  listening numeric,
  speaking numeric,
  homework numeric,
  effort numeric,
  overall numeric
)
language sql
security definer
set search_path = public
as $$
  select
    c.id as class_id,
    c.language,
    c.days_hours,
    round(avg(sg.reading)::numeric, 2) as reading,
    round(avg(sg.vocabulary)::numeric, 2) as vocabulary,
    round(avg(sg.grammar)::numeric, 2) as grammar,
    round(avg(sg.writing)::numeric, 2) as writing,
    round(avg(sg.listening)::numeric, 2) as listening,
    round(avg(sg.speaking)::numeric, 2) as speaking,
    round(avg(sg.homework)::numeric, 2) as homework,
    round(avg(sg.effort)::numeric, 2) as effort,
    round(avg(grades.grade_value)::numeric, 2) as overall
  from public.students_grades sg
  join public.students_language sl
    on sl.id = sg.student_language_id
  join public.classes c
    on c.id = sl.class_id
  join public.students s
    on s.id = sg.student_id
  cross join lateral (
    values
      (sg.reading),
      (sg.vocabulary),
      (sg.grammar),
      (sg.writing),
      (sg.listening),
      (sg.speaking),
      (sg.homework),
      (sg.effort)
  ) as grades(grade_value)
  where sg.student_id = input_student_id
    and grades.grade_value is not null
    and exists (
      select 1
      from public.user_access ua
      where ua.user_id = s.user_id
        and ua.auth_user_id = auth.uid()
    )
  group by c.id, c.language, c.days_hours
  order by c.language;
$$;

grant execute on function public.get_student_language_averages(uuid) to authenticated;
