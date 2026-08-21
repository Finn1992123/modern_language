create or replace function public.get_teacher_achievement_students(
  input_class_id uuid
)
returns table (
  student_id uuid,
  student_name text,
  profile_pic text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.teacher_can_access_class(input_class_id) then
    raise exception 'Teacher cannot access this class'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.classes c
    where c.id = input_class_id
      and upper(trim(c.name)) ~ '^(JA|JB|SA|SB)'
  ) then
    raise exception 'Junior achievements are not available for this class'
      using errcode = '22023';
  end if;

  return query
  select distinct
    s.id as student_id,
    s.name as student_name,
    s.profile_pic
  from public.students_language sl
  join public.students s
    on s.id = sl.student_id
  where sl.class_id = input_class_id
  order by s.name;
end;
$$;

grant execute on function public.get_teacher_achievement_students(uuid)
to authenticated;
