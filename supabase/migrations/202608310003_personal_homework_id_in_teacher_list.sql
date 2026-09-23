-- Include the personal homework id in the combined teacher homework list so
-- teachers can remove personal rows directly from "Τα καθήκοντα".

drop function if exists public.get_teacher_upcoming_homework_rows(uuid, date);

create function public.get_teacher_upcoming_homework_rows(
  input_class_id uuid,
  input_from_date date default current_date
)
returns table (
  personal_homework_id uuid,
  created_at timestamptz,
  for_date date,
  in_class text,
  homework text,
  is_personal boolean,
  student_id uuid,
  student_name text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.teacher_can_access_class(input_class_id) then
    raise exception 'Teacher cannot access this class' using errcode = '42501';
  end if;

  return query
  select combined.*
  from (
    select
      null::uuid as personal_homework_id,
      curriculum.created_at,
      curriculum.for_date,
      curriculum.in_class,
      curriculum.homework,
      false as is_personal,
      null::uuid as student_id,
      null::text as student_name
    from public.curriculum curriculum
    where curriculum.class_id = input_class_id
      and curriculum.for_date >= coalesce(input_from_date, current_date)

    union all

    select
      personal.id,
      personal.created_at,
      personal.for_date,
      null::text,
      personal.homework,
      true,
      student.id,
      student.name
    from public.personal_homework personal
    join public.students student on student.id = personal.student_id
    where personal.class_id = input_class_id
      and personal.removed_at is null
  ) combined
  order by combined.for_date, combined.created_at desc;
end;
$$;

revoke all on function public.get_teacher_upcoming_homework_rows(uuid, date)
from public;
grant execute on function public.get_teacher_upcoming_homework_rows(uuid, date)
to authenticated;
