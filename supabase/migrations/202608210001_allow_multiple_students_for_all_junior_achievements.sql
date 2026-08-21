create or replace function public.award_junior_achievement_to_students(
  input_class_id uuid,
  input_achievement_type text,
  input_student_ids uuid[]
)
returns table (
  ranking_student_id uuid,
  ranking_student_name text,
  achievement_count integer,
  rank_position bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  recipient_count integer;
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

  if input_achievement_type not in (
    'quiet',
    'reading',
    'speaking',
    'try',
    'vocabulary',
    'dictation',
    'participation',
    'grammar'
  ) then
    raise exception 'Unknown junior achievement type'
      using errcode = '22023';
  end if;

  select count(distinct recipient_id)
  into recipient_count
  from unnest(coalesce(input_student_ids, array[]::uuid[]))
    as recipients(recipient_id);

  if recipient_count = 0 then
    raise exception 'Select at least one student'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from unnest(input_student_ids) as recipients(recipient_id)
    where not exists (
      select 1
      from public.students_language sl
      where sl.class_id = input_class_id
        and sl.student_id = recipient_id
    )
  ) then
    raise exception 'A selected student is not enrolled in this class'
      using errcode = '22023';
  end if;

  insert into public."juniorAchievements" as achievements (
    student_id,
    class_id,
    achievement_type,
    count
  )
  select
    recipients.student_id,
    input_class_id,
    input_achievement_type,
    1
  from (
    select distinct recipient_id as student_id
    from unnest(input_student_ids) as selected_recipients(recipient_id)
  ) recipients
  on conflict (student_id, class_id, achievement_type)
  do update set
    count = achievements.count + 1,
    updated_at = now();

  return query
  with enrolled_students as (
    select distinct s.id, s.name
    from public.students_language sl
    join public.students s
      on s.id = sl.student_id
    where sl.class_id = input_class_id
  ),
  scores as (
    select
      student.id as student_id,
      student.name as student_name,
      coalesce(achievements.count, 0)::integer as achievement_count
    from enrolled_students student
    left join public."juniorAchievements" achievements
      on achievements.class_id = input_class_id
      and achievements.student_id = student.id
      and achievements.achievement_type = input_achievement_type
  )
  select
    scores.student_id,
    scores.student_name,
    scores.achievement_count,
    dense_rank() over (order by scores.achievement_count desc) as rank_position
  from scores
  order by scores.achievement_count desc, scores.student_name;
end;
$$;

grant execute on function public.award_junior_achievement_to_students(
  uuid,
  text,
  uuid[]
) to authenticated;
