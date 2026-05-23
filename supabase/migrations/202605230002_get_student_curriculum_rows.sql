drop function if exists public.get_student_curriculum_rows(uuid, uuid, integer, integer);

create or replace function public.get_student_curriculum_rows(
  input_student_id uuid,
  input_class_id uuid,
  input_limit integer default 10,
  input_offset integer default 0
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
  order by c.for_date desc, c.created_at desc
  limit greatest(1, least(coalesce(input_limit, 10), 50))
  offset greatest(0, coalesce(input_offset, 0));
$$;

grant execute on function public.get_student_curriculum_rows(uuid, uuid, integer, integer) to authenticated;
