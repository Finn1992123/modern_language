-- Personal vocabulary assignments: each student receives a snapshot of their
-- own active review words. Two successful personal assignments master a word.

alter table public.vocabulary_assignment_settings
add column if not exists personal_words boolean not null default false,
add column if not exists personal_word_limit integer
  check (personal_word_limit is null or personal_word_limit > 0);

alter table public.hangman_assignment_settings
add column if not exists personal_words boolean not null default false,
add column if not exists personal_word_limit integer
  check (personal_word_limit is null or personal_word_limit > 0);

create table if not exists public.exercise_assignment_personal_words (
  assignment_id uuid not null
    references public.exercise_assignments(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete cascade,
  vocabulary_word_id uuid not null
    references public.vocabulary_words(id) on delete cascade,
  position integer not null check (position > 0),
  created_at timestamptz not null default now(),
  primary key (assignment_id, student_id, vocabulary_word_id),
  unique (assignment_id, student_id, position)
);

create index if not exists exercise_assignment_personal_words_student_idx
on public.exercise_assignment_personal_words(student_id, class_id, assignment_id);

alter table public.exercise_assignment_personal_words enable row level security;
revoke all on table public.exercise_assignment_personal_words from public;

create table if not exists public.personal_vocabulary_assignment_successes (
  assignment_id uuid not null
    references public.exercise_assignments(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete cascade,
  vocabulary_word_id uuid not null
    references public.vocabulary_words(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (assignment_id, student_id, vocabulary_word_id)
);

alter table public.personal_vocabulary_assignment_successes enable row level security;
revoke all on table public.personal_vocabulary_assignment_successes from public;

alter function public.create_exercise_assignment(
  uuid[], text, text, text, timestamptz, timestamptz, integer, jsonb
) rename to create_exercise_assignment_without_personal_words;

revoke all on function public.create_exercise_assignment_without_personal_words(
  uuid[], text, text, text, timestamptz, timestamptz, integer, jsonb
) from authenticated;

create or replace function public.create_exercise_assignment(
  input_class_ids uuid[],
  input_activity_type text,
  input_title text,
  input_instructions text,
  input_available_from timestamptz,
  input_due_at timestamptz,
  input_max_attempts integer,
  input_settings jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  personal_words_value boolean := coalesce(
    (input_settings ->> 'personal_words')::boolean,
    false
  );
  required_count integer;
  settings_mode text;
  new_assignment_id uuid;
  class_id_value uuid;
begin
  if not personal_words_value then
    return public.create_exercise_assignment_without_personal_words(
      input_class_ids,
      input_activity_type,
      input_title,
      input_instructions,
      input_available_from,
      input_due_at,
      input_max_attempts,
      input_settings
    );
  end if;

  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if input_activity_type not in ('vocabulary', 'hangman') then
    raise exception 'personal words are available only for vocabulary and hangman';
  end if;
  if coalesce(cardinality(input_class_ids), 0) = 0 then
    raise exception 'at least one class is required';
  end if;
  if nullif(trim(input_title), '') is null then
    raise exception 'title is required';
  end if;
  if input_max_attempts is not null and input_max_attempts < 1 then
    raise exception 'max attempts must be positive';
  end if;
  if input_due_at is not null
     and input_due_at <= coalesce(input_available_from, now()) then
    raise exception 'due date must be after availability date';
  end if;

  required_count := nullif(input_settings ->> 'required_count', '')::integer;
  if required_count is null or required_count < 1 then
    raise exception 'personal word count must be positive';
  end if;

  settings_mode := nullif(trim(input_settings ->> 'mode'), '');
  if input_activity_type = 'vocabulary'
     and settings_mode not in ('multiple_choice', 'write_foreign', 'write_greek') then
    raise exception 'invalid personal vocabulary mode';
  end if;

  foreach class_id_value in array input_class_ids loop
    if not public.teacher_can_access_class(class_id_value) then
      raise exception 'class access denied';
    end if;
  end loop;

  if not exists (
    select 1
    from public.student_vocabulary_review_words review
    join public.students_language enrollment
      on enrollment.student_id = review.student_id
     and enrollment.class_id = review.class_id
    where review.class_id = any(input_class_ids)
      and review.mastered_at is null
  ) then
    raise exception 'there are no personal review words in the selected class';
  end if;

  insert into public.exercise_assignments (
    created_by_auth_user_id,
    activity_type,
    title,
    instructions,
    available_from,
    due_at,
    max_attempts,
    status
  ) values (
    auth.uid(),
    input_activity_type,
    trim(input_title),
    nullif(trim(input_instructions), ''),
    coalesce(input_available_from, now()),
    input_due_at,
    input_max_attempts,
    'published'
  ) returning id into new_assignment_id;

  insert into public.exercise_assignment_classes (assignment_id, class_id)
  select new_assignment_id, selected_class.class_id
  from unnest(input_class_ids) as selected_class(class_id)
  on conflict do nothing;

  if input_activity_type = 'vocabulary' then
    insert into public.vocabulary_assignment_settings (
      assignment_id, unit, unit_order, level, mode, pass_percentage,
      important_only, personal_words, personal_word_limit
    ) values (
      new_assignment_id, '__personal__', null, 'personal', settings_mode, 71,
      false, true, required_count
    );
  else
    insert into public.hangman_assignment_settings (
      assignment_id, unit, unit_order, level, required_words,
      personal_words, personal_word_limit
    ) values (
      new_assignment_id, '__personal__', null, 'personal', required_count,
      true, required_count
    );
  end if;

  insert into public.exercise_assignment_personal_words (
    assignment_id,
    student_id,
    class_id,
    vocabulary_word_id,
    position
  )
  select
    new_assignment_id,
    ranked.student_id,
    ranked.class_id,
    ranked.vocabulary_word_id,
    ranked.position
  from (
    select
      enrollment.student_id,
      enrollment.class_id,
      review.vocabulary_word_id,
      row_number() over (
        partition by enrollment.student_id, enrollment.class_id
        order by
          review.mistake_count desc,
          review.last_mistake_at desc,
          review.vocabulary_word_id
      )::integer as position
    from public.students_language enrollment
    join public.student_vocabulary_review_words review
      on review.student_id = enrollment.student_id
     and review.class_id = enrollment.class_id
     and review.mastered_at is null
    where enrollment.class_id = any(input_class_ids)
  ) ranked
  where ranked.position <= required_count;

  return new_assignment_id;
end;
$$;

revoke all on function public.create_exercise_assignment(
  uuid[], text, text, text, timestamptz, timestamptz, integer, jsonb
) from public;
grant execute on function public.create_exercise_assignment(
  uuid[], text, text, text, timestamptz, timestamptz, integer, jsonb
) to authenticated;

alter function public.get_student_exercise_assignments(uuid, uuid)
rename to get_student_exercise_assignments_without_personal_words;

revoke all on function public.get_student_exercise_assignments_without_personal_words(
  uuid, uuid
) from authenticated;

create or replace function public.get_student_exercise_assignments(
  input_student_id uuid,
  input_class_id uuid
)
returns table (
  assignment_id uuid,
  activity_type text,
  title text,
  instructions text,
  available_from timestamptz,
  due_at timestamptz,
  max_attempts integer,
  settings jsonb,
  attempt_count integer,
  completed boolean,
  progress_value integer,
  target_value integer,
  best_score numeric
)
language sql
security definer
set search_path = public
as $$
  select
    assignment.assignment_id,
    assignment.activity_type,
    assignment.title,
    assignment.instructions,
    assignment.available_from,
    assignment.due_at,
    assignment.max_attempts,
    case
      when assignment.settings ->> 'unit' = '__personal__' then
        assignment.settings || jsonb_build_object(
          'personal_words', true,
          'personal_word_limit', coalesce(
            vocabulary.personal_word_limit,
            hangman.personal_word_limit
          )
        )
      else assignment.settings
    end,
    assignment.attempt_count,
    assignment.completed,
    assignment.progress_value,
    case
      when assignment.activity_type = 'hangman'
       and assignment.settings ->> 'unit' = '__personal__'
      then personal_words.word_count
      else assignment.target_value
    end,
    assignment.best_score
  from public.get_student_exercise_assignments_without_personal_words(
    input_student_id,
    input_class_id
  ) assignment
  left join public.vocabulary_assignment_settings vocabulary
    on vocabulary.assignment_id = assignment.assignment_id
  left join public.hangman_assignment_settings hangman
    on hangman.assignment_id = assignment.assignment_id
  left join lateral (
    select count(*)::integer as word_count
    from public.exercise_assignment_personal_words personal
    where personal.assignment_id = assignment.assignment_id
      and personal.student_id = input_student_id
      and personal.class_id = input_class_id
  ) personal_words on true
  where assignment.settings ->> 'unit' is distinct from '__personal__'
     or personal_words.word_count > 0
  order by
    assignment.completed,
    assignment.due_at nulls last,
    assignment.available_from desc;
$$;

revoke all on function public.get_student_exercise_assignments(uuid, uuid)
from public;
grant execute on function public.get_student_exercise_assignments(uuid, uuid)
to authenticated;

alter function public.start_exercise_assignment_attempt(uuid, uuid, uuid)
rename to start_exercise_assignment_attempt_without_personal_words;

revoke all on function public.start_exercise_assignment_attempt_without_personal_words(
  uuid, uuid, uuid
) from authenticated;

create or replace function public.start_exercise_assignment_attempt(
  input_assignment_id uuid,
  input_student_id uuid,
  input_class_id uuid
)
returns table (
  attempt_id uuid,
  attempt_number integer,
  progress_value integer,
  target_value integer,
  completed_source_keys text[],
  started_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  assignment_row public.exercise_assignments%rowtype;
  active_attempt public.exercise_assignment_attempts%rowtype;
  next_attempt_number integer;
  personal_word_count integer;
  is_personal boolean;
begin
  select coalesce(vocabulary.personal_words, hangman.personal_words, false)
  into is_personal
  from public.exercise_assignments assignment
  left join public.vocabulary_assignment_settings vocabulary
    on vocabulary.assignment_id = assignment.id
  left join public.hangman_assignment_settings hangman
    on hangman.assignment_id = assignment.id
  where assignment.id = input_assignment_id;

  if not coalesce(is_personal, false) then
    return query
    select * from public.start_exercise_assignment_attempt_without_personal_words(
      input_assignment_id,
      input_student_id,
      input_class_id
    );
    return;
  end if;

  perform pg_advisory_xact_lock(
    hashtext(input_assignment_id::text || ':' || input_student_id::text)
  );

  if not exists (
    select 1
    from public.students student
    join public.students_language enrollment
      on enrollment.student_id = student.id
    join public.user_access access on access.user_id = student.user_id
    join public.exercise_assignment_classes assignment_class
      on assignment_class.class_id = enrollment.class_id
     and assignment_class.assignment_id = input_assignment_id
    where student.id = input_student_id
      and enrollment.class_id = input_class_id
      and access.auth_user_id = auth.uid()
  ) then
    raise exception 'assignment access denied';
  end if;

  select * into assignment_row
  from public.exercise_assignments
  where id = input_assignment_id;

  if assignment_row.status <> 'published'
     or assignment_row.available_from > now() then
    raise exception 'assignment is not available';
  end if;
  if assignment_row.due_at is not null and assignment_row.due_at < now() then
    raise exception 'assignment has expired';
  end if;
  if exists (
    select 1 from public.exercise_assignment_attempts attempt
    where attempt.assignment_id = input_assignment_id
      and attempt.student_id = input_student_id
      and attempt.passed
  ) then
    raise exception 'assignment is already completed';
  end if;

  select * into active_attempt
  from public.exercise_assignment_attempts attempt
  where attempt.assignment_id = input_assignment_id
    and attempt.student_id = input_student_id
    and attempt.status = 'in_progress';

  if found then
    return query select
      active_attempt.id,
      active_attempt.attempt_number,
      active_attempt.progress_value,
      active_attempt.target_value,
      coalesce((
        select array_agg(item.source_key order by item.completed_at)
        from public.exercise_assignment_attempt_items item
        where item.attempt_id = active_attempt.id
      ), '{}'::text[]),
      active_attempt.started_at;
    return;
  end if;

  select count(*)::integer into personal_word_count
  from public.exercise_assignment_personal_words personal
  where personal.assignment_id = input_assignment_id
    and personal.student_id = input_student_id
    and personal.class_id = input_class_id;

  if personal_word_count < 1 then
    raise exception 'no personal words are available for this assignment';
  end if;

  select coalesce(max(attempt.attempt_number), 0) + 1
  into next_attempt_number
  from public.exercise_assignment_attempts attempt
  where attempt.assignment_id = input_assignment_id
    and attempt.student_id = input_student_id;

  if assignment_row.max_attempts is not null
     and next_attempt_number > assignment_row.max_attempts then
    raise exception 'maximum attempts reached';
  end if;

  insert into public.exercise_assignment_attempts (
    assignment_id, student_id, class_id, auth_user_id,
    attempt_number, target_value
  ) values (
    input_assignment_id, input_student_id, input_class_id, auth.uid(),
    next_attempt_number,
    case when assignment_row.activity_type = 'vocabulary'
      then 100 else personal_word_count end
  ) returning * into active_attempt;

  return query select
    active_attempt.id,
    active_attempt.attempt_number,
    active_attempt.progress_value,
    active_attempt.target_value,
    '{}'::text[],
    active_attempt.started_at;
end;
$$;

revoke all on function public.start_exercise_assignment_attempt(uuid, uuid, uuid)
from public;
grant execute on function public.start_exercise_assignment_attempt(uuid, uuid, uuid)
to authenticated;

create or replace function public.get_student_assignment_vocabulary_words(
  input_assignment_id uuid,
  input_student_id uuid,
  input_class_id uuid
)
returns table (
  id uuid,
  cefr_book_id integer,
  book_name text,
  language text,
  level text,
  unit text,
  unit_order integer,
  word text,
  translation_gr text,
  accepted_words text,
  part_of_speech text,
  example_sentence text,
  is_important boolean
)
language sql
security definer
set search_path = public
as $$
  select
    vocabulary.id,
    vocabulary.cefr_book_id,
    vocabulary.book_name,
    coalesce(vocabulary.language, class.language),
    vocabulary.level,
    vocabulary.unit,
    vocabulary.unit_order,
    vocabulary.word,
    vocabulary.translation_gr,
    vocabulary.accepted_words,
    vocabulary.part_of_speech,
    vocabulary.example_sentence,
    vocabulary.is_important
  from public.exercise_assignment_personal_words personal
  join public.vocabulary_words vocabulary
    on vocabulary.id = personal.vocabulary_word_id
  join public.classes class on class.id = personal.class_id
  where personal.assignment_id = input_assignment_id
    and personal.student_id = input_student_id
    and personal.class_id = input_class_id
    and vocabulary.is_active = true
    and exists (
      select 1
      from public.students student
      join public.user_access access on access.user_id = student.user_id
      where student.id = input_student_id
        and access.auth_user_id = auth.uid()
    )
  order by personal.position;
$$;

revoke all on function public.get_student_assignment_vocabulary_words(
  uuid, uuid, uuid
) from public;
grant execute on function public.get_student_assignment_vocabulary_words(
  uuid, uuid, uuid
) to authenticated;

create or replace function public.record_personal_vocabulary_assignment_successes(
  input_assignment_id uuid,
  input_student_id uuid,
  input_class_id uuid,
  input_vocabulary_word_ids uuid[]
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  recorded_count integer;
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
    raise exception 'student or class access denied';
  end if;

  with inserted as (
    insert into public.personal_vocabulary_assignment_successes (
      assignment_id, student_id, class_id, vocabulary_word_id
    )
    select
      personal.assignment_id,
      personal.student_id,
      personal.class_id,
      personal.vocabulary_word_id
    from public.exercise_assignment_personal_words personal
    where personal.assignment_id = input_assignment_id
      and personal.student_id = input_student_id
      and personal.class_id = input_class_id
      and personal.vocabulary_word_id = any(
        coalesce(input_vocabulary_word_ids, '{}'::uuid[])
      )
    on conflict do nothing
    returning student_id, class_id, vocabulary_word_id
  ), updated as (
    update public.student_vocabulary_review_words review
    set
      correct_streak = least(review.correct_streak + 1, 2),
      mastered_at = case
        when review.correct_streak + 1 >= 2 then now()
        else null
      end
    from inserted
    where review.student_id = inserted.student_id
      and review.class_id = inserted.class_id
      and review.vocabulary_word_id = inserted.vocabulary_word_id
    returning review.vocabulary_word_id
  )
  select count(*)::integer into recorded_count from updated;

  return recorded_count;
end;
$$;

revoke all on function public.record_personal_vocabulary_assignment_successes(
  uuid, uuid, uuid, uuid[]
) from public;
grant execute on function public.record_personal_vocabulary_assignment_successes(
  uuid, uuid, uuid, uuid[]
) to authenticated;

-- Teacher result screens count only students who actually received words.
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
  with eligible_students as (
    select distinct assignment.id as assignment_id, enrollment.student_id
    from public.exercise_assignments assignment
    join public.exercise_assignment_classes assignment_class
      on assignment_class.assignment_id = assignment.id
     and assignment_class.class_id = input_class_id
    join public.students_language enrollment
      on enrollment.class_id = input_class_id
    left join public.vocabulary_assignment_settings vocabulary
      on vocabulary.assignment_id = assignment.id
    left join public.hangman_assignment_settings hangman
      on hangman.assignment_id = assignment.id
    where not coalesce(vocabulary.personal_words, hangman.personal_words, false)
       or exists (
         select 1
         from public.exercise_assignment_personal_words personal
         where personal.assignment_id = assignment.id
           and personal.student_id = enrollment.student_id
           and personal.class_id = input_class_id
       )
  ), assignment_totals as (
    select
      student.assignment_id,
      count(distinct student.student_id)::integer as total_students,
      count(distinct student.student_id) filter (
        where attempt.student_id is not null
      )::integer as students_started,
      count(distinct student.student_id) filter (
        where attempt.passed
      )::integer as students_completed
    from eligible_students student
    left join public.exercise_assignment_attempts attempt
      on attempt.assignment_id = student.assignment_id
     and attempt.class_id = input_class_id
     and attempt.student_id = student.student_id
    group by student.assignment_id
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
  left join assignment_totals totals on totals.assignment_id = assignment.id
  order by assignment.created_at desc;
end;
$$;

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
declare
  is_personal boolean;
begin
  if not public.teacher_can_access_class(input_class_id) then
    raise exception 'Teacher cannot access this class'
      using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.exercise_assignment_classes assignment_class
    where assignment_class.assignment_id = input_assignment_id
      and assignment_class.class_id = input_class_id
  ) then
    raise exception 'Assignment is not available for this class'
      using errcode = '22023';
  end if;

  select coalesce(vocabulary.personal_words, hangman.personal_words, false)
  into is_personal
  from public.exercise_assignments assignment
  left join public.vocabulary_assignment_settings vocabulary
    on vocabulary.assignment_id = assignment.id
  left join public.hangman_assignment_settings hangman
    on hangman.assignment_id = assignment.id
  where assignment.id = input_assignment_id;

  return query
  with eligible_students as (
    select distinct student.id, student.name, student.profile_pic
    from public.students_language enrollment
    join public.students student on student.id = enrollment.student_id
    where enrollment.class_id = input_class_id
      and (
        not coalesce(is_personal, false)
        or exists (
          select 1
          from public.exercise_assignment_personal_words personal
          where personal.assignment_id = input_assignment_id
            and personal.student_id = student.id
            and personal.class_id = input_class_id
        )
      )
  ), attempt_totals as (
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
  from eligible_students student
  left join attempt_totals attempt on attempt.student_id = student.id
  order by student.name;
end;
$$;
