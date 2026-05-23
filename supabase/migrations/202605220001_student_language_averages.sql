create or replace function public.get_student_language_averages(input_student_id uuid)
returns table (
  language text,
  average_grade numeric
)
language sql
security definer
set search_path = public
as $$
  select
    c.language,
    round(avg(grades.grade_value)::numeric, 2) as average_grade
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
  group by c.language;
$$;

grant execute on function public.get_student_language_averages(uuid) to authenticated;
