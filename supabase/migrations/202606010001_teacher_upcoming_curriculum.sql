create or replace function public.get_teacher_upcoming_curriculum_rows(
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
    and public.teacher_can_access_class(input_class_id)
  order by c.for_date asc, c.created_at desc;
$$;

grant execute on function public.get_teacher_upcoming_curriculum_rows(uuid, date)
to authenticated;
