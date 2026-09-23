-- Free-text homework assigned by a teacher to one student.

create table if not exists public.personal_homework (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  created_by_auth_user_id uuid not null
    references auth.users(id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  for_date date not null,
  homework text not null check (length(trim(homework)) > 0)
);

create index if not exists personal_homework_class_date_idx
on public.personal_homework(class_id, for_date, created_at desc);

create index if not exists personal_homework_student_date_idx
on public.personal_homework(student_id, class_id, for_date, created_at desc);

alter table public.personal_homework enable row level security;
revoke all on table public.personal_homework from public;

create or replace function public.create_teacher_personal_homework(
  input_class_id uuid,
  input_student_id uuid,
  input_for_date date,
  input_homework text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_personal_homework_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  if not public.teacher_can_access_class(input_class_id) then
    raise exception 'Teacher cannot access this class' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.students_language enrollment
    where enrollment.class_id = input_class_id
      and enrollment.student_id = input_student_id
  ) then
    raise exception 'Student is not enrolled in this class'
      using errcode = '22023';
  end if;

  if input_for_date is null then
    raise exception 'Homework date is required' using errcode = '22023';
  end if;

  if nullif(trim(input_homework), '') is null then
    raise exception 'Homework text is required' using errcode = '22023';
  end if;

  insert into public.personal_homework (
    created_by_auth_user_id,
    class_id,
    student_id,
    for_date,
    homework
  ) values (
    auth.uid(),
    input_class_id,
    input_student_id,
    input_for_date,
    trim(input_homework)
  )
  returning id into new_personal_homework_id;

  return new_personal_homework_id;
end;
$$;

revoke all on function public.create_teacher_personal_homework(
  uuid, uuid, date, text
) from public;
grant execute on function public.create_teacher_personal_homework(
  uuid, uuid, date, text
) to authenticated;

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
    and personal.for_date >= coalesce(input_from_date, current_date)
  order by personal.for_date, personal.created_at desc;
end;
$$;

revoke all on function public.get_teacher_personal_homework_rows(uuid, date)
from public;
grant execute on function public.get_teacher_personal_homework_rows(uuid, date)
to authenticated;

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
      and personal.for_date >= coalesce(input_from_date, current_date)
  ) combined
  order by combined.for_date, combined.created_at desc;
end;
$$;

revoke all on function public.get_teacher_upcoming_homework_rows(uuid, date)
from public;
grant execute on function public.get_teacher_upcoming_homework_rows(uuid, date)
to authenticated;

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
    and personal.for_date >= coalesce(input_from_date, current_date)
  order by personal.for_date, personal.created_at desc;
end;
$$;

revoke all on function public.get_student_personal_homework_rows(
  uuid, uuid, date
) from public;
grant execute on function public.get_student_personal_homework_rows(
  uuid, uuid, date
) to authenticated;
