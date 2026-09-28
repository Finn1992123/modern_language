-- Additive API for a single student card per language. Released class-based
-- RPCs remain unchanged. Apply after 202609280001_multiple_student_classes.sql.
begin;

create or replace function public.get_student_language_enrollments(input_student_id uuid)
returns table (enrollment_id uuid, class_id uuid, class_name text, language text, days_hours text)
language sql stable security definer set search_path = public
as $$
  select sl.id, c.id, c.name, lower(btrim(c.language)),
    coalesce(nullif(btrim(sl.days_hours), ''), c.days_hours)
  from public.students_language sl
  join public.students s on s.id = sl.student_id
  join public.classes c on c.id = sl.class_id
  where s.id = input_student_id
    and exists (select 1 from public.user_access ua
      where ua.user_id = s.user_id and ua.auth_user_id = auth.uid());
$$;

create or replace function public.get_student_language_summaries(input_student_id uuid)
returns table (
  language text, classes jsonb,
  reading numeric, vocabulary numeric, grammar numeric, writing numeric,
  listening numeric, speaking numeric, homework numeric, effort numeric, overall numeric
)
language sql stable security definer set search_path = public
as $$
  with enrollments as (
    select * from public.get_student_language_enrollments(input_student_id)
  ), class_groups as (
    select e.language, jsonb_agg(jsonb_build_object(
      'class_id', e.class_id, 'class_name', e.class_name, 'days_hours', e.days_hours
    ) order by e.class_name, e.class_id) as classes
    from enrollments e group by e.language
  ), averages as (
    -- Average actual marks, not averages of classes with different row counts.
    select e.language,
      round(avg(sg.reading)::numeric, 2) as reading, round(avg(sg.vocabulary)::numeric, 2) as vocabulary,
      round(avg(sg.grammar)::numeric, 2) as grammar, round(avg(sg.writing)::numeric, 2) as writing,
      round(avg(sg.listening)::numeric, 2) as listening, round(avg(sg.speaking)::numeric, 2) as speaking,
      round(avg(sg.homework)::numeric, 2) as homework, round(avg(sg.effort)::numeric, 2) as effort,
      round(avg(mark.value)::numeric, 2) as overall
    from enrollments e
    left join public.students_grades sg
      on sg.student_language_id = e.enrollment_id and sg.student_id = input_student_id
    cross join lateral (values (sg.reading), (sg.vocabulary), (sg.grammar),
      (sg.writing), (sg.listening), (sg.speaking), (sg.homework), (sg.effort)) mark(value)
    group by e.language
  )
  select g.language, g.classes, a.reading, a.vocabulary, a.grammar, a.writing,
    a.listening, a.speaking, a.homework, a.effort, a.overall
  from class_groups g join averages a on a.language = g.language
  order by g.language;
$$;

create or replace function public.get_student_language_grade_rows(
  input_student_id uuid, input_language text,
  input_limit integer default 10, input_offset integer default 0
)
returns table (
  created_at timestamptz, reading numeric, vocabulary numeric, grammar numeric,
  writing numeric, listening numeric, speaking numeric, homework numeric,
  effort numeric, comments text, class_name text
)
language sql stable security definer set search_path = public
as $$
  select sg.created_at, sg.reading, sg.vocabulary, sg.grammar, sg.writing,
    sg.listening, sg.speaking, sg.homework, sg.effort, sg.comments, e.class_name
  from public.get_student_language_enrollments(input_student_id) e
  join public.students_grades sg
    on sg.student_language_id = e.enrollment_id and sg.student_id = input_student_id
  where e.language = lower(btrim(input_language))
  -- Tie-break on the complete row (including its ID when present in the schema).
  order by sg.created_at desc, e.class_id, to_jsonb(sg)::text
  limit greatest(1, least(coalesce(input_limit, 10), 50))
  offset greatest(0, coalesce(input_offset, 0));
$$;

create or replace function public.get_student_language_curriculum_rows(
  input_student_id uuid, input_language text,
  input_limit integer default 10, input_offset integer default 0
)
returns table (created_at timestamptz, for_date date, in_class text, homework text, class_name text)
language sql stable security definer set search_path = public
as $$
  select c.created_at, c.for_date, c.in_class, c.homework, e.class_name
  from public.get_student_language_enrollments(input_student_id) e
  join public.curriculum c on c.class_id = e.class_id
  where e.language = lower(btrim(input_language))
  order by c.created_at desc, c.for_date desc, e.class_id, to_jsonb(c)::text
  limit greatest(1, least(coalesce(input_limit, 10), 50))
  offset greatest(0, coalesce(input_offset, 0));
$$;

create or replace function public.get_student_language_upcoming_curriculum_rows(
  input_student_id uuid, input_language text, input_from_date date default current_date
)
returns table (created_at timestamptz, for_date date, in_class text, homework text, class_name text)
language sql stable security definer set search_path = public
as $$
  select c.created_at, c.for_date, c.in_class, c.homework, e.class_name
  from public.get_student_language_enrollments(input_student_id) e
  join public.curriculum c on c.class_id = e.class_id
  where e.language = lower(btrim(input_language))
    and c.for_date >= coalesce(input_from_date, current_date)
    and nullif(btrim(c.homework), '') is not null
  order by c.for_date, c.created_at desc, e.class_id, to_jsonb(c)::text;
$$;

create or replace function public.get_student_language_personal_homework_rows(
  input_student_id uuid, input_language text, input_from_date date default current_date
)
returns table (
  personal_homework_id uuid, created_at timestamptz, for_date date,
  homework text, class_name text
)
language sql stable security definer set search_path = public
as $$
  select p.id, p.created_at, p.for_date, p.homework, e.class_name
  from public.get_student_language_enrollments(input_student_id) e
  join public.personal_homework p on p.class_id = e.class_id
  where e.language = lower(btrim(input_language))
    and p.student_id = input_student_id and p.removed_at is null
  -- Preserve persistent personal homework, including past due dates.
  order by p.for_date, p.created_at desc, p.id;
$$;

revoke all on function public.get_student_language_enrollments(uuid) from public;
revoke all on function public.get_student_language_summaries(uuid) from public;
revoke all on function public.get_student_language_grade_rows(uuid, text, integer, integer) from public;
revoke all on function public.get_student_language_curriculum_rows(uuid, text, integer, integer) from public;
revoke all on function public.get_student_language_upcoming_curriculum_rows(uuid, text, date) from public;
revoke all on function public.get_student_language_personal_homework_rows(uuid, text, date) from public;

grant execute on function public.get_student_language_enrollments(uuid) to authenticated;
grant execute on function public.get_student_language_summaries(uuid) to authenticated;
grant execute on function public.get_student_language_grade_rows(uuid, text, integer, integer) to authenticated;
grant execute on function public.get_student_language_curriculum_rows(uuid, text, integer, integer) to authenticated;
grant execute on function public.get_student_language_upcoming_curriculum_rows(uuid, text, date) to authenticated;
grant execute on function public.get_student_language_personal_homework_rows(uuid, text, date) to authenticated;

commit;
