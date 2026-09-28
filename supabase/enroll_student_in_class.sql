-- Run AFTER 202609280001_multiple_student_classes.sql in the SQL Editor.
-- Fill in the student and class UUIDs below (never create a duplicate student).
-- Run once per class. Existing enrollments in other classes stay untouched.
-- Re-running for the same pair updates only names, language and this schedule.
begin;

do $$
declare
  target_student_id uuid := null; -- Required: existing public.students.id
  target_class_id uuid := null; -- Required: existing public.classes.id
  attendance_schedule text := null; -- e.g. 'Monday 17:00-18:00'; NULL uses class schedule
begin
  if target_student_id is null or target_class_id is null then
    raise exception 'Fill in target_student_id and target_class_id before running.';
  end if;

  if not exists (select 1 from public.students where id = target_student_id) then
    raise exception 'Student % does not exist', target_student_id;
  end if;
  if not exists (select 1 from public.classes where id = target_class_id) then
    raise exception 'Class % does not exist', target_class_id;
  end if;

  insert into public.students_language (
    student_id, parent_name, student_name, language, class_id, days_hours
  )
  select s.id, concat_ws(' ', u.name, u.surname), s.name, c.language, c.id,
    nullif(btrim(attendance_schedule), '')
  from public.students s
  join public.users u on u.id = s.user_id
  cross join public.classes c
  where s.id = target_student_id and c.id = target_class_id
  on conflict (student_id, class_id) do update
  set parent_name = excluded.parent_name,
      student_name = excluded.student_name,
      language = excluded.language,
      days_hours = excluded.days_hours;

  if not found then
    raise exception 'Student % has no parent account', target_student_id;
  end if;
end;
$$;

commit;
