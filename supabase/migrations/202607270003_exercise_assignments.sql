-- Extensible exercise assignments shared by games and future content types.

create table if not exists public.exercise_assignments (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  created_by_auth_user_id uuid not null references auth.users(id) on delete cascade,
  activity_type text not null check (
    activity_type in (
      'reader',
      'vocabulary',
      'hangman',
      'identify_tense',
      'study_grammar'
    )
  ),
  title text not null check (length(trim(title)) > 0),
  instructions text,
  available_from timestamptz not null default now(),
  due_at timestamptz,
  max_attempts integer check (max_attempts is null or max_attempts > 0),
  status text not null default 'published' check (
    status in ('draft', 'published', 'closed')
  ),
  check (due_at is null or due_at > available_from)
);

create table if not exists public.exercise_assignment_classes (
  assignment_id uuid not null references public.exercise_assignments(id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete cascade,
  primary key (assignment_id, class_id)
);

create table if not exists public.reader_assignment_settings (
  assignment_id uuid primary key references public.exercise_assignments(id) on delete cascade,
  level_code text not null check (length(trim(level_code)) > 0),
  required_passages integer not null check (required_passages > 0)
);

create table if not exists public.vocabulary_assignment_settings (
  assignment_id uuid primary key references public.exercise_assignments(id) on delete cascade,
  unit text not null check (length(trim(unit)) > 0),
  unit_order integer,
  level text,
  mode text not null check (
    mode in ('speaking', 'multiple_choice', 'write_foreign', 'write_greek')
  ),
  pass_percentage integer not null default 71 check (
    pass_percentage between 1 and 100
  ),
  important_only boolean not null default false
);

create table if not exists public.hangman_assignment_settings (
  assignment_id uuid primary key references public.exercise_assignments(id) on delete cascade,
  unit text not null check (length(trim(unit)) > 0),
  unit_order integer,
  level text not null check (length(trim(level)) > 0),
  required_words integer not null check (required_words > 0)
);

create table if not exists public.timed_question_assignment_settings (
  assignment_id uuid primary key references public.exercise_assignments(id) on delete cascade,
  limit_type text not null check (limit_type in ('time', 'questions')),
  limit_value integer not null check (limit_value > 0),
  topic_slugs text[] not null default '{}',
  pass_percentage integer not null default 71 check (
    pass_percentage between 1 and 100
  )
);

alter table public.timed_question_assignment_settings
add column if not exists pass_percentage integer not null default 71;

create table if not exists public.exercise_assignment_attempts (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.exercise_assignments(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete cascade,
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  attempt_number integer not null check (attempt_number > 0),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  status text not null default 'in_progress' check (
    status in ('in_progress', 'completed', 'failed', 'expired')
  ),
  progress_value integer not null default 0 check (progress_value >= 0),
  target_value integer not null check (target_value > 0),
  score_percentage numeric check (
    score_percentage is null
    or score_percentage between 0 and 100
  ),
  passed boolean not null default false,
  unique (assignment_id, student_id, attempt_number)
);

create table if not exists public.exercise_assignment_attempt_items (
  attempt_id uuid not null references public.exercise_assignment_attempts(id) on delete cascade,
  source_key text not null check (length(trim(source_key)) > 0),
  completed_at timestamptz not null default now(),
  primary key (attempt_id, source_key)
);

create index if not exists exercise_assignment_classes_class_idx
on public.exercise_assignment_classes(class_id, assignment_id);

create index if not exists exercise_assignments_availability_idx
on public.exercise_assignments(status, available_from, due_at);

create index if not exists exercise_attempts_student_idx
on public.exercise_assignment_attempts(student_id, class_id, started_at desc);

create unique index if not exists exercise_attempts_one_active_idx
on public.exercise_assignment_attempts(assignment_id, student_id)
where status = 'in_progress';

alter table public.exercise_assignments enable row level security;
alter table public.exercise_assignment_classes enable row level security;
alter table public.reader_assignment_settings enable row level security;
alter table public.vocabulary_assignment_settings enable row level security;
alter table public.hangman_assignment_settings enable row level security;
alter table public.timed_question_assignment_settings enable row level security;
alter table public.exercise_assignment_attempts enable row level security;
alter table public.exercise_assignment_attempt_items enable row level security;

-- Tables are intentionally accessed through the security-definer functions below.

create or replace function public.get_teacher_assignment_vocabulary_units(
  input_class_id uuid
)
returns table (
  unit text,
  unit_order integer,
  level text,
  word_count integer,
  important_word_count integer
)
language sql
security definer
set search_path = public
as $$
  select
    vw.unit,
    vw.unit_order,
    coalesce(vw.level, '') as level,
    count(*)::integer as word_count,
    count(*) filter (where vw.is_important)::integer as important_word_count
  from public.classes c
  join public.vocabulary_words vw
    on vw.cefr_book_id = c.cefr_book_id
  where c.id = input_class_id
    and public.teacher_can_access_class(input_class_id)
    and vw.is_active = true
    and nullif(trim(vw.unit), '') is not null
  group by vw.unit, vw.unit_order, coalesce(vw.level, '')
  order by vw.unit_order nulls last, vw.unit, coalesce(vw.level, '');
$$;

revoke all on function public.get_teacher_assignment_vocabulary_units(uuid)
from public;
grant execute on function public.get_teacher_assignment_vocabulary_units(uuid)
to authenticated;

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
  new_assignment_id uuid;
  class_id_value uuid;
  required_count integer;
  settings_unit text;
  settings_level text;
  settings_unit_order integer;
  settings_mode text;
  important_only_value boolean;
  limit_type_value text;
  topic_slugs_value text[];
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if coalesce(cardinality(input_class_ids), 0) = 0 then
    raise exception 'at least one class is required';
  end if;

  if input_activity_type not in (
    'reader',
    'vocabulary',
    'hangman',
    'identify_tense',
    'study_grammar'
  ) then
    raise exception 'unsupported assignment activity';
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

  foreach class_id_value in array input_class_ids loop
    if not public.teacher_can_access_class(class_id_value) then
      raise exception 'class access denied';
    end if;
  end loop;

  required_count := nullif(input_settings ->> 'required_count', '')::integer;
  settings_unit := nullif(trim(input_settings ->> 'unit'), '');
  settings_level := nullif(trim(input_settings ->> 'level'), '');
  settings_unit_order := nullif(input_settings ->> 'unit_order', '')::integer;
  settings_mode := nullif(trim(input_settings ->> 'mode'), '');
  important_only_value := coalesce(
    (input_settings ->> 'important_only')::boolean,
    false
  );
  limit_type_value := nullif(trim(input_settings ->> 'limit_type'), '');
  select coalesce(array_agg(selected_topic.slug), '{}'::text[])
  into topic_slugs_value
  from jsonb_array_elements_text(
    coalesce(input_settings -> 'topic_slugs', '[]'::jsonb)
  ) as selected_topic(slug);

  if required_count is null or required_count < 1 then
    raise exception 'required count must be positive';
  end if;

  if input_activity_type = 'reader' then
    if settings_level is null then
      raise exception 'reader level is required';
    end if;
    if (
      select count(*)
      from public.reader_passages rp
      where rp.level_code = settings_level
        and rp.is_active = true
    ) < required_count then
      raise exception 'not enough active reader passages';
    end if;
  elsif input_activity_type = 'vocabulary' then
    if settings_unit is null then
      raise exception 'vocabulary unit is required';
    end if;
    if settings_mode not in (
      'speaking',
      'multiple_choice',
      'write_foreign',
      'write_greek'
    ) then
      raise exception 'invalid vocabulary mode';
    end if;

    foreach class_id_value in array input_class_ids loop
      if not exists (
        select 1
        from public.classes c
        join public.vocabulary_words vw
          on vw.cefr_book_id = c.cefr_book_id
        where c.id = class_id_value
          and vw.is_active = true
          and vw.unit = settings_unit
          and (settings_unit_order is null or vw.unit_order = settings_unit_order)
          and (settings_level is null or vw.level = settings_level)
          and (not important_only_value or vw.is_important)
      ) then
        raise exception 'the selected vocabulary unit is empty for a class';
      end if;
      if settings_mode = 'multiple_choice' and (
        select count(*)
        from public.classes c
        join public.vocabulary_words vw
          on vw.cefr_book_id = c.cefr_book_id
        where c.id = class_id_value
          and vw.is_active = true
          and vw.unit = settings_unit
          and (settings_unit_order is null or vw.unit_order = settings_unit_order)
          and (settings_level is null or vw.level = settings_level)
          and (not important_only_value or vw.is_important)
      ) < 4 then
        raise exception 'multiple choice requires at least four words';
      end if;
    end loop;
  elsif input_activity_type = 'hangman' then
    if settings_unit is null or settings_level is null then
      raise exception 'hangman unit and level are required';
    end if;

    foreach class_id_value in array input_class_ids loop
      if (
        select count(distinct upper(trim(vw.word)))
        from public.classes c
        join public.vocabulary_words vw
          on vw.cefr_book_id = c.cefr_book_id
        where c.id = class_id_value
          and vw.is_active = true
          and vw.unit = settings_unit
          and vw.level = settings_level
          and (settings_unit_order is null or vw.unit_order = settings_unit_order)
      ) < required_count then
        raise exception 'not enough active hangman words';
      end if;
    end loop;
  elsif input_activity_type in ('identify_tense', 'study_grammar') then
    if limit_type_value not in ('time', 'questions') then
      raise exception 'time or question limit is required';
    end if;
    if input_activity_type = 'study_grammar' then
      if cardinality(topic_slugs_value) = 0 then
        raise exception 'at least one grammar topic is required';
      end if;
      if exists (
        select 1
        from unnest(topic_slugs_value) selected_topic(slug)
        where not exists (
          select 1
          from public.study_gram_topics topic
          where topic.slug = selected_topic.slug
            and topic.is_active = true
        )
      ) then
        raise exception 'invalid grammar topic';
      end if;
      if limit_type_value = 'questions' and (
        select count(*)
        from public.study_gram_questions question
        where question.topic_slug = any(topic_slugs_value)
          and question.is_active = true
      ) < required_count then
        raise exception 'not enough active grammar questions';
      end if;
    end if;
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
  )
  values (
    auth.uid(),
    input_activity_type,
    trim(input_title),
    nullif(trim(input_instructions), ''),
    coalesce(input_available_from, now()),
    input_due_at,
    input_max_attempts,
    'published'
  )
  returning id into new_assignment_id;

  insert into public.exercise_assignment_classes (assignment_id, class_id)
  select new_assignment_id, class_ids.class_id
  from unnest(input_class_ids) as class_ids(class_id)
  on conflict do nothing;

  if input_activity_type = 'reader' then
    insert into public.reader_assignment_settings (
      assignment_id,
      level_code,
      required_passages
    )
    values (new_assignment_id, settings_level, required_count);
  elsif input_activity_type = 'vocabulary' then
    insert into public.vocabulary_assignment_settings (
      assignment_id,
      unit,
      unit_order,
      level,
      mode,
      pass_percentage,
      important_only
    )
    values (
      new_assignment_id,
      settings_unit,
      settings_unit_order,
      settings_level,
      settings_mode,
      71,
      important_only_value
    );
  elsif input_activity_type = 'hangman' then
    insert into public.hangman_assignment_settings (
      assignment_id,
      unit,
      unit_order,
      level,
      required_words
    )
    values (
      new_assignment_id,
      settings_unit,
      settings_unit_order,
      settings_level,
      required_count
    );
  elsif input_activity_type in ('identify_tense', 'study_grammar') then
    insert into public.timed_question_assignment_settings (
      assignment_id,
      limit_type,
      limit_value,
      topic_slugs
    )
    values (
      new_assignment_id,
      limit_type_value,
      required_count,
      topic_slugs_value
    );
  end if;

  return new_assignment_id;
end;
$$;

revoke all on function public.create_exercise_assignment(
  uuid[], text, text, text, timestamptz, timestamptz, integer, jsonb
) from public;
grant execute on function public.create_exercise_assignment(
  uuid[], text, text, text, timestamptz, timestamptz, integer, jsonb
) to authenticated;

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
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.students student
    join public.students_language student_language
      on student_language.student_id = student.id
    join public.user_access access
      on access.user_id = student.user_id
    where student.id = input_student_id
      and student_language.class_id = input_class_id
      and access.auth_user_id = auth.uid()
  ) then
    raise exception 'student or class access denied';
  end if;

  return query
  select
    assignment.id,
    assignment.activity_type,
    assignment.title,
    assignment.instructions,
    assignment.available_from,
    assignment.due_at,
    assignment.max_attempts,
    case assignment.activity_type
      when 'reader' then jsonb_build_object(
        'level', reader.level_code,
        'required_count', reader.required_passages
      )
      when 'vocabulary' then jsonb_build_object(
        'unit', vocabulary.unit,
        'unit_order', vocabulary.unit_order,
        'level', vocabulary.level,
        'mode', vocabulary.mode,
        'pass_percentage', vocabulary.pass_percentage,
        'important_only', vocabulary.important_only
      )
      when 'hangman' then jsonb_build_object(
        'unit', hangman.unit,
        'unit_order', hangman.unit_order,
        'level', hangman.level,
        'required_count', hangman.required_words
      )
      when 'identify_tense' then jsonb_build_object(
        'limit_type', timed_question.limit_type,
        'limit_value', timed_question.limit_value,
        'pass_percentage', timed_question.pass_percentage
      )
      when 'study_grammar' then jsonb_build_object(
        'limit_type', timed_question.limit_type,
        'limit_value', timed_question.limit_value,
        'topic_slugs', timed_question.topic_slugs,
        'pass_percentage', timed_question.pass_percentage
      )
      else '{}'::jsonb
    end as settings,
    coalesce(attempts.attempt_count, 0)::integer,
    coalesce(attempts.completed, false),
    coalesce(attempts.progress_value, 0)::integer,
    coalesce(
      attempts.target_value,
      reader.required_passages,
      hangman.required_words,
      timed_question.limit_value,
      100
    )::integer,
    attempts.best_score
  from public.exercise_assignments assignment
  join public.exercise_assignment_classes assignment_class
    on assignment_class.assignment_id = assignment.id
   and assignment_class.class_id = input_class_id
  left join public.reader_assignment_settings reader
    on reader.assignment_id = assignment.id
  left join public.vocabulary_assignment_settings vocabulary
    on vocabulary.assignment_id = assignment.id
  left join public.hangman_assignment_settings hangman
    on hangman.assignment_id = assignment.id
  left join public.timed_question_assignment_settings timed_question
    on timed_question.assignment_id = assignment.id
  left join lateral (
    select
      count(*)::integer as attempt_count,
      bool_or(attempt.passed) as completed,
      max(attempt.progress_value)::integer as progress_value,
      max(attempt.target_value)::integer as target_value,
      max(attempt.score_percentage) as best_score
    from public.exercise_assignment_attempts attempt
    where attempt.assignment_id = assignment.id
      and attempt.student_id = input_student_id
      and attempt.class_id = input_class_id
  ) attempts on true
  where assignment.status = 'published'
  order by
    coalesce(attempts.completed, false),
    assignment.due_at nulls last,
    assignment.created_at desc;
end;
$$;

revoke all on function public.get_student_exercise_assignments(uuid, uuid)
from public;
grant execute on function public.get_student_exercise_assignments(uuid, uuid)
to authenticated;

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
  computed_target integer;
begin
  perform pg_advisory_xact_lock(
    hashtext(input_assignment_id::text || ':' || input_student_id::text)
  );

  if not exists (
    select 1
    from public.students student
    join public.students_language student_language
      on student_language.student_id = student.id
    join public.user_access access
      on access.user_id = student.user_id
    join public.exercise_assignment_classes assignment_class
      on assignment_class.class_id = student_language.class_id
     and assignment_class.assignment_id = input_assignment_id
    where student.id = input_student_id
      and student_language.class_id = input_class_id
      and access.auth_user_id = auth.uid()
  ) then
    raise exception 'assignment access denied';
  end if;

  select *
  into assignment_row
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
    select 1
    from public.exercise_assignment_attempts attempt
    where attempt.assignment_id = input_assignment_id
      and attempt.student_id = input_student_id
      and attempt.passed
  ) then
    raise exception 'assignment is already completed';
  end if;

  select *
  into active_attempt
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
      coalesce(
        (
          select array_agg(item.source_key order by item.completed_at)
          from public.exercise_assignment_attempt_items item
          where item.attempt_id = active_attempt.id
        ),
        '{}'::text[]
      ),
      active_attempt.started_at;
    return;
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

  select coalesce(
    reader.required_passages,
    hangman.required_words,
    timed_question.limit_value,
    100
  )
  into computed_target
  from public.exercise_assignments assignment
  left join public.reader_assignment_settings reader
    on reader.assignment_id = assignment.id
  left join public.hangman_assignment_settings hangman
    on hangman.assignment_id = assignment.id
  left join public.timed_question_assignment_settings timed_question
    on timed_question.assignment_id = assignment.id
  where assignment.id = input_assignment_id;

  insert into public.exercise_assignment_attempts (
    assignment_id,
    student_id,
    class_id,
    auth_user_id,
    attempt_number,
    target_value
  )
  values (
    input_assignment_id,
    input_student_id,
    input_class_id,
    auth.uid(),
    next_attempt_number,
    computed_target
  )
  returning * into active_attempt;

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

create or replace function public.finish_exercise_assignment_attempt(
  input_attempt_id uuid,
  input_progress_value integer,
  input_score_percentage numeric,
  input_finish_attempt boolean default true,
  input_source_key text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  attempt_row public.exercise_assignment_attempts%rowtype;
  assignment_type text;
  pass_percentage integer;
  did_pass boolean;
  effective_progress integer;
begin
  select attempt.*
  into attempt_row
  from public.exercise_assignment_attempts attempt
  where attempt.id = input_attempt_id
    and attempt.auth_user_id = auth.uid()
    and attempt.status = 'in_progress';

  if not found then
    raise exception 'active attempt not found';
  end if;

  select assignment.activity_type
  into assignment_type
  from public.exercise_assignments assignment
  where assignment.id = attempt_row.assignment_id;

  if input_progress_value < 0 then
    raise exception 'progress cannot be negative';
  end if;
  if input_score_percentage is not null
     and (input_score_percentage < 0 or input_score_percentage > 100) then
    raise exception 'invalid percentage';
  end if;

  if nullif(trim(input_source_key), '') is not null then
    insert into public.exercise_assignment_attempt_items (attempt_id, source_key)
    values (input_attempt_id, trim(input_source_key))
    on conflict do nothing;

    select count(*)::integer
    into effective_progress
    from public.exercise_assignment_attempt_items item
    where item.attempt_id = input_attempt_id;
  else
    effective_progress := input_progress_value;
  end if;

  if assignment_type = 'vocabulary' then
    select settings.pass_percentage
    into pass_percentage
    from public.vocabulary_assignment_settings settings
    where settings.assignment_id = attempt_row.assignment_id;
    did_pass := input_score_percentage is not null
      and input_score_percentage >= pass_percentage;
  elsif assignment_type in ('identify_tense', 'study_grammar') then
    select settings.pass_percentage
    into pass_percentage
    from public.timed_question_assignment_settings settings
    where settings.assignment_id = attempt_row.assignment_id;
    did_pass := effective_progress >= attempt_row.target_value
      and input_score_percentage is not null
      and input_score_percentage >= pass_percentage;
  else
    did_pass := effective_progress >= attempt_row.target_value;
  end if;

  update public.exercise_assignment_attempts
  set
    progress_value = least(
      greatest(effective_progress, progress_value),
      target_value
    ),
    score_percentage = input_score_percentage,
    passed = did_pass,
    status = case
      when did_pass then 'completed'
      when input_finish_attempt then 'failed'
      else 'in_progress'
    end,
    finished_at = case
      when did_pass or input_finish_attempt then now()
      else null
    end
  where id = input_attempt_id;

  return did_pass;
end;
$$;

revoke all on function public.finish_exercise_assignment_attempt(
  uuid, integer, numeric, boolean, text
) from public;
grant execute on function public.finish_exercise_assignment_attempt(
  uuid, integer, numeric, boolean, text
) to authenticated;

-- Repair results created before timed/question games required a passing score.
update public.exercise_assignment_attempts attempt
set
  passed = false,
  status = 'failed'
from public.exercise_assignments assignment
join public.timed_question_assignment_settings settings
  on settings.assignment_id = assignment.id
where attempt.assignment_id = assignment.id
  and assignment.activity_type in ('identify_tense', 'study_grammar')
  and attempt.passed = true
  and coalesce(attempt.score_percentage, 0) < settings.pass_percentage;
