alter table public.student_vocabulary_review_words
add column if not exists dictation_mistake_count integer not null default 0
  check (dictation_mistake_count >= 0);

create or replace function public.record_student_vocabulary_mistake(
  input_student_id uuid,
  input_class_id uuid,
  input_vocabulary_word_id uuid,
  input_source text,
  input_wrong_answer text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if input_source not in ('study_your_voc', 'hangman', 'dictation') then
    raise exception 'Unknown vocabulary mistake source'
      using errcode = '22023';
  end if;

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
    raise exception 'Student or class access denied'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.classes c
    join public.vocabulary_words word
      on word.cefr_book_id = c.cefr_book_id
    where c.id = input_class_id
      and word.id = input_vocabulary_word_id
      and word.is_active = true
  ) then
    raise exception 'Vocabulary word is not available for this class'
      using errcode = '22023';
  end if;

  insert into public.student_vocabulary_review_words as review (
    student_id,
    class_id,
    vocabulary_word_id,
    mistake_count,
    study_your_voc_mistake_count,
    hangman_mistake_count,
    dictation_mistake_count,
    last_wrong_answer,
    first_mistake_at,
    last_mistake_at,
    correct_streak,
    mastered_at
  ) values (
    input_student_id,
    input_class_id,
    input_vocabulary_word_id,
    1,
    case when input_source = 'study_your_voc' then 1 else 0 end,
    case when input_source = 'hangman' then 1 else 0 end,
    case when input_source = 'dictation' then 1 else 0 end,
    nullif(trim(input_wrong_answer), ''),
    now(),
    now(),
    0,
    null
  )
  on conflict (student_id, class_id, vocabulary_word_id)
  do update set
    mistake_count = review.mistake_count + 1,
    study_your_voc_mistake_count =
      review.study_your_voc_mistake_count +
      case when input_source = 'study_your_voc' then 1 else 0 end,
    hangman_mistake_count =
      review.hangman_mistake_count +
      case when input_source = 'hangman' then 1 else 0 end,
    dictation_mistake_count =
      review.dictation_mistake_count +
      case when input_source = 'dictation' then 1 else 0 end,
    last_wrong_answer = coalesce(
      nullif(trim(input_wrong_answer), ''),
      review.last_wrong_answer
    ),
    last_mistake_at = now(),
    correct_streak = 0,
    mastered_at = null;
end;
$$;

create or replace function public.capture_live_dictation_mistake()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  participant public.live_activity_participants;
  room public.live_activity_rooms;
  word_id uuid;
begin
  if new.is_correct then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if old.is_correct = false then
      return new;
    end if;
  end if;

  select * into participant
  from public.live_activity_participants p
  where p.id = new.participant_id;

  select * into room
  from public.live_activity_rooms r
  where r.id = participant.room_id;

  select room_word.vocabulary_word_id into word_id
  from public.live_activity_room_words room_word
  where room_word.room_id = participant.room_id
    and room_word.position = new.position;

  if participant.id is null or room.id is null or word_id is null then
    return new;
  end if;

  insert into public.student_vocabulary_review_words as review (
    student_id,
    class_id,
    vocabulary_word_id,
    mistake_count,
    study_your_voc_mistake_count,
    hangman_mistake_count,
    dictation_mistake_count,
    last_wrong_answer,
    first_mistake_at,
    last_mistake_at,
    correct_streak,
    mastered_at
  ) values (
    participant.student_id,
    room.class_id,
    word_id,
    1,
    0,
    0,
    1,
    nullif(trim(new.answer), ''),
    now(),
    now(),
    0,
    null
  )
  on conflict (student_id, class_id, vocabulary_word_id)
  do update set
    mistake_count = review.mistake_count + 1,
    dictation_mistake_count = review.dictation_mistake_count + 1,
    last_wrong_answer = coalesce(
      nullif(trim(new.answer), ''),
      review.last_wrong_answer
    ),
    last_mistake_at = now(),
    correct_streak = 0,
    mastered_at = null;

  return new;
end;
$$;

drop trigger if exists capture_live_dictation_mistake_trigger
on public.live_activity_answers;

create trigger capture_live_dictation_mistake_trigger
after insert or update of is_correct, answer
on public.live_activity_answers
for each row
execute function public.capture_live_dictation_mistake();

revoke all on function public.capture_live_dictation_mistake() from public;
