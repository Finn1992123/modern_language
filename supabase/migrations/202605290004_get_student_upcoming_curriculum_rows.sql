create or replace function public.get_student_upcoming_curriculum_rows(
  input_student_id uuid,
  input_class_id uuid,
  input_from_date date default current_date
)
returns table (
  created_at timestamptz,
  for_date date,
  in_class text,
  homework text
)
language sql
security definer
set search_path = public
as $$
  select
    c.created_at,
    c.for_date,
    c.in_class,
    c.homework
  from public.curriculum c
  where c.class_id = input_class_id
    and c.for_date >= coalesce(input_from_date, current_date)
    and c.homework is not null
    and btrim(c.homework) <> ''
    and exists (
      select 1
      from public.students s
      join public.students_language sl
        on sl.student_id = s.id
      join public.user_access ua
        on ua.user_id = s.user_id
      where s.id = input_student_id
        and sl.class_id = input_class_id
        and ua.auth_user_id = auth.uid()
    )
  order by c.for_date asc, c.created_at desc;
$$;

grant execute on function public.get_student_upcoming_curriculum_rows(uuid, uuid, date) to authenticated;
