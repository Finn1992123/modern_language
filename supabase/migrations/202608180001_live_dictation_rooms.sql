-- Live rooms are intentionally generic enough to host more classroom games later.

create table if not exists public.live_activity_rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z2-9]{6}$'),
  class_id uuid not null references public.classes(id) on delete cascade,
  created_by_auth_user_id uuid not null references auth.users(id) on delete cascade,
  activity_type text not null default 'dictation' check (activity_type in ('dictation')),
  status text not null default 'waiting' check (
    status in ('waiting', 'active', 'finished', 'cancelled')
  ),
  duration_seconds integer not null check (duration_seconds between 60 and 7200),
  unit text not null check (length(trim(unit)) > 0),
  unit_order integer,
  important_only boolean not null default false,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz
);

create table if not exists public.live_activity_room_words (
  room_id uuid not null references public.live_activity_rooms(id) on delete cascade,
  position integer not null check (position > 0),
  vocabulary_word_id uuid not null references public.vocabulary_words(id),
  primary key (room_id, position),
  unique (room_id, vocabulary_word_id)
);

create table if not exists public.live_activity_participants (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.live_activity_rooms(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  submitted_at timestamptz,
  correct_count integer check (correct_count is null or correct_count >= 0),
  score_percentage numeric check (
    score_percentage is null or score_percentage between 0 and 100
  ),
  unique (room_id, student_id)
);

create table if not exists public.live_activity_answers (
  participant_id uuid not null references public.live_activity_participants(id) on delete cascade,
  position integer not null check (position > 0),
  answer text not null default '',
  is_correct boolean not null,
  primary key (participant_id, position)
);

create index if not exists live_activity_rooms_teacher_idx
on public.live_activity_rooms(created_by_auth_user_id, created_at desc);

create index if not exists live_activity_participants_room_idx
on public.live_activity_participants(room_id, joined_at);

alter table public.live_activity_rooms enable row level security;
alter table public.live_activity_room_words enable row level security;
alter table public.live_activity_participants enable row level security;
alter table public.live_activity_answers enable row level security;

-- Direct table access stays closed. All access goes through the checked functions below.

create or replace function public.live_normalize_answer(input_value text)
returns text
language sql
immutable
set search_path = public
as $$
  select regexp_replace(
    translate(
      lower(trim(coalesce(input_value, ''))),
      'άέήίόύώϊΐϋΰς',
      'αεηιουωιιυυσ'
    ),
    '\s+',
    ' ',
    'g'
  );
$$;

create or replace function public.live_random_room_code()
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  result text := '';
begin
  for index_value in 1..6 loop
    result := result || substr(alphabet, 1 + floor(random() * length(alphabet))::integer, 1);
  end loop;
  return result;
end;
$$;

create or replace function public.create_live_dictation_room(
  input_class_id uuid,
  input_unit text,
  input_unit_order integer,
  input_important_only boolean default false,
  input_word_count integer default null,
  input_duration_seconds integer default 300
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  new_room public.live_activity_rooms;
  requested_count integer := coalesce(input_word_count, 15);
  generated_code text;
  inserted_count integer;
begin
  if not public.teacher_can_access_class(input_class_id) then
    raise exception 'class access denied';
  end if;
  if nullif(trim(input_unit), '') is null then
    raise exception 'unit is required';
  end if;
  if requested_count < 1 or requested_count > 100 then
    raise exception 'word count must be between 1 and 100';
  end if;
  if input_duration_seconds < 60 or input_duration_seconds > 7200 then
    raise exception 'duration must be between 1 and 120 minutes';
  end if;

  loop
    generated_code := public.live_random_room_code();
    exit when not exists (
      select 1 from public.live_activity_rooms room where room.code = generated_code
    );
  end loop;

  insert into public.live_activity_rooms (
    code, class_id, created_by_auth_user_id, activity_type, duration_seconds,
    unit, unit_order, important_only
  ) values (
    generated_code, input_class_id, auth.uid(), 'dictation', input_duration_seconds,
    trim(input_unit), input_unit_order, coalesce(input_important_only, false)
  ) returning * into new_room;

  insert into public.live_activity_room_words (room_id, position, vocabulary_word_id)
  select new_room.id, row_number() over ()::integer, selected.id
  from (
    select word.id
    from public.classes class_row
    join public.vocabulary_words word
      on word.cefr_book_id = class_row.cefr_book_id
    where class_row.id = input_class_id
      and word.is_active = true
      and word.unit = trim(input_unit)
      and (input_unit_order is null or word.unit_order = input_unit_order)
      and nullif(trim(word.word), '') is not null
      and nullif(trim(word.translation_gr), '') is not null
      and (not coalesce(input_important_only, false) or word.is_important)
    order by random()
    limit requested_count
  ) selected;

  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    delete from public.live_activity_rooms where id = new_room.id;
    raise exception 'no words found for this selection';
  end if;

  return jsonb_build_object(
    'room_id', new_room.id,
    'code', new_room.code,
    'word_count', inserted_count
  );
end;
$$;

create or replace function public.join_live_activity_room(
  input_code text,
  input_student_id uuid,
  input_class_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_room public.live_activity_rooms;
  participant public.live_activity_participants;
begin
  select * into selected_room
  from public.live_activity_rooms room
  where room.code = upper(trim(input_code))
  limit 1;

  if selected_room.id is null then
    raise exception 'room not found';
  end if;
  if selected_room.status <> 'waiting' then
    raise exception 'room is not accepting participants';
  end if;
  if selected_room.class_id <> input_class_id then
    raise exception 'room belongs to another class';
  end if;
  if not exists (
    select 1
    from public.students student
    join public.students_language enrollment on enrollment.student_id = student.id
    join public.user_access access_row on access_row.user_id = student.user_id
    where student.id = input_student_id
      and enrollment.class_id = input_class_id
      and access_row.auth_user_id = auth.uid()
  ) then
    raise exception 'student or class access denied';
  end if;

  insert into public.live_activity_participants (
    room_id, student_id, auth_user_id
  ) values (
    selected_room.id, input_student_id, auth.uid()
  )
  on conflict (room_id, student_id) do update
  set auth_user_id = excluded.auth_user_id
  returning * into participant;

  return jsonb_build_object(
    'participant_id', participant.id,
    'room_id', selected_room.id,
    'activity_type', selected_room.activity_type
  );
end;
$$;

create or replace function public.start_live_activity_room(input_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.live_activity_rooms room
  set status = 'active', started_at = now()
  where room.id = input_room_id
    and room.created_by_auth_user_id = auth.uid()
    and room.status = 'waiting';
  if not found then
    raise exception 'room cannot be started';
  end if;
end;
$$;

create or replace function public.get_teacher_live_activity_room(input_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_room public.live_activity_rooms;
  participants_json jsonb;
  room_word_count integer;
begin
  select * into selected_room
  from public.live_activity_rooms room
  where room.id = input_room_id
    and room.created_by_auth_user_id = auth.uid();
  if selected_room.id is null then raise exception 'room access denied'; end if;

  if selected_room.status = 'active' and (
    selected_room.started_at + make_interval(secs => selected_room.duration_seconds) <= now()
    or (
      exists (select 1 from public.live_activity_participants p where p.room_id = selected_room.id)
      and not exists (
        select 1 from public.live_activity_participants p
        where p.room_id = selected_room.id and p.submitted_at is null
      )
    )
  ) then
    update public.live_activity_rooms
    set status = 'finished', finished_at = now()
    where id = selected_room.id;
    selected_room.status := 'finished';
  end if;

  select count(*)::integer into room_word_count
  from public.live_activity_room_words word where word.room_id = selected_room.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'participant_id', participant.id,
    'student_name', coalesce(nullif(trim(student.name), ''), 'Μαθητής'),
    'profile_pic', student.profile_pic,
    'joined_at', participant.joined_at,
    'submitted_at', participant.submitted_at,
    'correct_count', participant.correct_count,
    'score_percentage', participant.score_percentage
  ) order by participant.joined_at), '[]'::jsonb)
  into participants_json
  from public.live_activity_participants participant
  join public.students student on student.id = participant.student_id
  where participant.room_id = selected_room.id;

  return jsonb_build_object(
    'room_id', selected_room.id, 'code', selected_room.code,
    'status', selected_room.status, 'activity_type', selected_room.activity_type,
    'unit', selected_room.unit, 'important_only', selected_room.important_only,
    'duration_seconds', selected_room.duration_seconds,
    'started_at', selected_room.started_at, 'word_count', room_word_count,
    'participants', participants_json
  );
end;
$$;

create or replace function public.get_student_live_activity_room(input_participant_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  participant public.live_activity_participants;
  selected_room public.live_activity_rooms;
  words_json jsonb := '[]'::jsonb;
begin
  select * into participant
  from public.live_activity_participants p
  where p.id = input_participant_id and p.auth_user_id = auth.uid();
  if participant.id is null then raise exception 'participant access denied'; end if;

  select * into selected_room from public.live_activity_rooms where id = participant.room_id;
  if selected_room.status = 'active'
     and selected_room.started_at + make_interval(secs => selected_room.duration_seconds) <= now() then
    update public.live_activity_rooms
    set status = 'finished', finished_at = now()
    where id = selected_room.id and status = 'active';
    selected_room.status := 'finished';
  end if;

  if selected_room.status in ('active', 'finished') then
    select coalesce(jsonb_agg(jsonb_build_object(
      'position', room_word.position,
      'prompt', vocabulary.word
    ) order by room_word.position), '[]'::jsonb)
    into words_json
    from public.live_activity_room_words room_word
    join public.vocabulary_words vocabulary on vocabulary.id = room_word.vocabulary_word_id
    where room_word.room_id = selected_room.id;
  end if;

  return jsonb_build_object(
    'room_id', selected_room.id, 'code', selected_room.code,
    'status', selected_room.status, 'activity_type', selected_room.activity_type,
    'duration_seconds', selected_room.duration_seconds,
    'started_at', selected_room.started_at,
    'submitted_at', participant.submitted_at,
    'correct_count', participant.correct_count,
    'score_percentage', participant.score_percentage,
    'words', words_json
  );
end;
$$;

create or replace function public.submit_live_dictation_answers(
  input_participant_id uuid,
  input_answers jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  participant public.live_activity_participants;
  selected_room public.live_activity_rooms;
  answer_row record;
  correct_total integer;
  word_total integer;
  score_value numeric;
  submission_expired boolean;
begin
  select * into participant
  from public.live_activity_participants p
  where p.id = input_participant_id and p.auth_user_id = auth.uid()
  for update;
  if participant.id is null then raise exception 'participant access denied'; end if;
  if participant.submitted_at is not null then raise exception 'answers already submitted'; end if;

  select * into selected_room from public.live_activity_rooms where id = participant.room_id;
  if selected_room.status not in ('active', 'finished') then raise exception 'room is not active'; end if;
  submission_expired := now() > selected_room.started_at
    + make_interval(secs => selected_room.duration_seconds + 10);

  for answer_row in
    select
      room_word.position,
      coalesce(given.answer, '') as answer,
      vocabulary.translation_gr,
      vocabulary.accepted_words
    from public.live_activity_room_words room_word
    join public.vocabulary_words vocabulary on vocabulary.id = room_word.vocabulary_word_id
    left join lateral (
      select item ->> 'answer' as answer
      from jsonb_array_elements(coalesce(input_answers, '[]'::jsonb)) item
      where nullif(item ->> 'position', '')::integer = room_word.position
      limit 1
    ) given on true
    where room_word.room_id = selected_room.id
  loop
    insert into public.live_activity_answers (participant_id, position, answer, is_correct)
    values (
      participant.id,
      answer_row.position,
      case when submission_expired then '' else answer_row.answer end,
      exists (
        select 1
        from regexp_split_to_table(
          concat_ws('|', answer_row.translation_gr, answer_row.accepted_words),
          '[|]'
        ) accepted(value)
        where public.live_normalize_answer(accepted.value) =
              public.live_normalize_answer(
                case when submission_expired then '' else answer_row.answer end
              )
          and public.live_normalize_answer(
                case when submission_expired then '' else answer_row.answer end
              ) <> ''
      )
    )
    on conflict (participant_id, position) do update
    set answer = excluded.answer, is_correct = excluded.is_correct;
  end loop;

  select count(*)::integer, count(*) filter (where answer.is_correct)::integer
  into word_total, correct_total
  from public.live_activity_answers answer
  where answer.participant_id = participant.id;
  score_value := round(correct_total * 100.0 / greatest(word_total, 1), 2);

  update public.live_activity_participants
  set submitted_at = now(), correct_count = correct_total, score_percentage = score_value
  where id = participant.id;

  return jsonb_build_object(
    'correct_count', correct_total,
    'word_count', word_total,
    'score_percentage', score_value
  );
end;
$$;

revoke all on function public.live_normalize_answer(text) from public;
revoke all on function public.live_random_room_code() from public;
revoke all on function public.create_live_dictation_room(uuid, text, integer, boolean, integer, integer) from public;
revoke all on function public.join_live_activity_room(text, uuid, uuid) from public;
revoke all on function public.start_live_activity_room(uuid) from public;
revoke all on function public.get_teacher_live_activity_room(uuid) from public;
revoke all on function public.get_student_live_activity_room(uuid) from public;
revoke all on function public.submit_live_dictation_answers(uuid, jsonb) from public;

grant execute on function public.create_live_dictation_room(uuid, text, integer, boolean, integer, integer) to authenticated;
grant execute on function public.join_live_activity_room(text, uuid, uuid) to authenticated;
grant execute on function public.start_live_activity_room(uuid) to authenticated;
grant execute on function public.get_teacher_live_activity_room(uuid) to authenticated;
grant execute on function public.get_student_live_activity_room(uuid) to authenticated;
grant execute on function public.submit_live_dictation_answers(uuid, jsonb) to authenticated;
