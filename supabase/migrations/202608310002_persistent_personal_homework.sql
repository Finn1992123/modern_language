-- Personal homework remains visible until a teacher explicitly removes it.

alter table public.personal_homework
add column if not exists removed_at timestamptz,
add column if not exists removed_by_auth_user_id uuid
  references auth.users(id) on delete set null;

create index if not exists personal_homework_active_class_idx
on public.personal_homework(class_id, for_date, created_at desc)
where removed_at is null;

create index if not exists personal_homework_active_student_idx
on public.personal_homework(student_id, class_id, for_date, created_at desc)
where removed_at is null;

create or replace function public.remove_teacher_personal_homework(
  input_personal_homework_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  homework_class_id uuid;
begin
  select personal.class_id
  into homework_class_id
  from public.personal_homework personal
  where personal.id = input_personal_homework_id
    and personal.removed_at is null;

  if homework_class_id is null then
    raise exception 'Personal homework was not found' using errcode = '22023';
  end if;

  if not public.teacher_can_access_class(homework_class_id) then
    raise exception 'Teacher cannot access this class' using errcode = '42501';
  end if;

  update public.personal_homework
  set
    removed_at = now(),
    removed_by_auth_user_id = auth.uid()
  where id = input_personal_homework_id;
end;
$$;

revoke all on function public.remove_teacher_personal_homework(uuid)
from public;
grant execute on function public.remove_teacher_personal_homework(uuid)
to authenticated;

create or replace function public.get_teacher_personal_homework_rows(
  input_class_id uuid,
  input_from_date date default current_date
)
returns table (
  personal_homework_id uuid,
  created_at timestamptz,
  for_date date,
  homework text,
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
  select
    personal.id,
    personal.created_at,
    personal.for_date,
    personal.homework,
    student.id,
    student.name
  from public.personal_homework personal
  join public.students student on student.id = personal.student_id
  where personal.class_id = input_class_id
    and personal.removed_at is null
  order by personal.for_date, personal.created_at desc;
end;
$$;

create or replace function public.get_teacher_upcoming_homework_rows(
  input_class_id uuid,
  input_from_date date default current_date
)
returns table (
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

create or replace function public.get_student_personal_homework_rows(
  input_student_id uuid,
  input_class_id uuid,
  input_from_date date default current_date
)
returns table (
  personal_homework_id uuid,
  created_at timestamptz,
  for_date date,
  homework text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.students student
    join public.students_language enrollment
      on enrollment.student_id = student.id
    join public.user_access access on access.user_id = student.user_id
    where student.id = input_student_id
      and enrollment.class_id = input_class_id
      and access.auth_user_id = auth.uid()
  ) then
    raise exception 'Student or class access denied' using errcode = '42501';
  end if;

  return query
  select personal.id, personal.created_at, personal.for_date, personal.homework
  from public.personal_homework personal
  where personal.student_id = input_student_id
    and personal.class_id = input_class_id
    and personal.removed_at is null
  order by personal.for_date, personal.created_at desc;
end;
$$;
