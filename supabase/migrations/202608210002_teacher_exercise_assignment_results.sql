create or replace function public.get_teacher_exercise_assignments_overview(
  input_class_id uuid
)
returns table (
  assignment_id uuid,
  assignment_title text,
  activity_type text,
  created_at timestamptz,
  due_at timestamptz,
  assignment_status text,
  student_count integer,
  started_count integer,
  completed_count integer
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

  return query
  with enrolled_students as (
    select distinct sl.student_id
    from public.students_language sl
    where sl.class_id = input_class_id
  ),
  assignment_totals as (
    select
      assignment.id,
      count(distinct student.student_id)::integer as total_students,
      count(distinct student.student_id) filter (
        where attempt.student_id is not null
      )::integer as students_started,
      count(distinct student.student_id) filter (
        where attempt.passed
      )::integer as students_completed
    from public.exercise_assignments assignment
    join public.exercise_assignment_classes assignment_class
      on assignment_class.assignment_id = assignment.id
      and assignment_class.class_id = input_class_id
    cross join enrolled_students student
    left join public.exercise_assignment_attempts attempt
      on attempt.assignment_id = assignment.id
      and attempt.class_id = input_class_id
      and attempt.student_id = student.student_id
    group by assignment.id
  )
  select
    assignment.id,
    assignment.title,
    assignment.activity_type,
    assignment.created_at,
    assignment.due_at,
    assignment.status,
    coalesce(totals.total_students, 0),
    coalesce(totals.students_started, 0),
    coalesce(totals.students_completed, 0)
  from public.exercise_assignments assignment
  join public.exercise_assignment_classes assignment_class
    on assignment_class.assignment_id = assignment.id
    and assignment_class.class_id = input_class_id
  left join assignment_totals totals
    on totals.id = assignment.id
  order by assignment.created_at desc;
end;
$$;

revoke all on function public.get_teacher_exercise_assignments_overview(uuid)
from public;
grant execute on function public.get_teacher_exercise_assignments_overview(uuid)
to authenticated;

create or replace function public.get_teacher_exercise_assignment_results(
  input_assignment_id uuid,
  input_class_id uuid
)
returns table (
  result_student_id uuid,
  student_name text,
  profile_pic text,
  result_status text,
  attempt_count integer,
  progress_value integer,
  target_value integer,
  best_score numeric,
  completed_at timestamptz,
  last_attempt_at timestamptz
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
    from public.exercise_assignment_classes assignment_class
    where assignment_class.assignment_id = input_assignment_id
      and assignment_class.class_id = input_class_id
  ) then
    raise exception 'Assignment is not available for this class'
      using errcode = '22023';
  end if;

  return query
  with enrolled_students as (
    select distinct student.id, student.name, student.profile_pic
    from public.students_language sl
    join public.students student
      on student.id = sl.student_id
    where sl.class_id = input_class_id
  ),
  attempt_totals as (
    select
      attempt.student_id,
      count(*)::integer as attempts,
      bool_or(attempt.passed) as has_completed,
      bool_or(attempt.status = 'in_progress') as has_active_attempt,
      max(attempt.progress_value)::integer as best_progress,
      max(attempt.target_value)::integer as target,
      max(attempt.score_percentage) as score,
      max(attempt.finished_at) filter (where attempt.passed) as finished_at,
      max(attempt.started_at) as latest_attempt_at
    from public.exercise_assignment_attempts attempt
    where attempt.assignment_id = input_assignment_id
      and attempt.class_id = input_class_id
    group by attempt.student_id
  )
  select
    student.id,
    student.name,
    student.profile_pic,
    case
      when coalesce(attempt.has_completed, false) then 'completed'
      when coalesce(attempt.has_active_attempt, false) then 'in_progress'
      when coalesce(attempt.attempts, 0) > 0 then 'retry'
      else 'not_started'
    end,
    coalesce(attempt.attempts, 0),
    coalesce(attempt.best_progress, 0),
    coalesce(attempt.target, 1),
    attempt.score,
    attempt.finished_at,
    attempt.latest_attempt_at
  from enrolled_students student
  left join attempt_totals attempt
    on attempt.student_id = student.id
  order by student.name;
end;
$$;

revoke all on function public.get_teacher_exercise_assignment_results(uuid, uuid)
from public;
grant execute on function public.get_teacher_exercise_assignment_results(uuid, uuid)
to authenticated;
