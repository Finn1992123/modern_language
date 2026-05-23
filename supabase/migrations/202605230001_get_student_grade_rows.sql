create or replace function public.get_student_grade_rows(
  input_student_id uuid,
  input_class_id uuid,
  input_limit integer default 10,
  input_offset integer default 0
)
returns table (
  created_at timestamptz,
  reading numeric,
  vocabulary numeric,
  grammar numeric,
  writing numeric,
  listening numeric,
  speaking numeric,
  homework numeric,
  effort numeric,
  comments text
)
language sql
security definer
set search_path = public
as $$
  select
    sg.created_at,
    sg.reading,
    sg.vocabulary,
    sg.grammar,
    sg.writing,
    sg.listening,
    sg.speaking,
    sg.homework,
    sg.effort,
    sg.comments
  from public.students_grades sg
  join public.students_language sl
    on sl.id = sg.student_language_id
  join public.students s
    on s.id = sg.student_id
  where sg.student_id = input_student_id
    and sl.class_id = input_class_id
    and exists (
      select 1
      from public.user_access ua
      where ua.user_id = s.user_id
        and ua.auth_user_id = auth.uid()
    )
  order by sg.created_at desc
  limit greatest(1, least(coalesce(input_limit, 10), 50))
  offset greatest(0, coalesce(input_offset, 0));
$$;

grant execute on function public.get_student_grade_rows(uuid, uuid, integer, integer) to authenticated;
