create table if not exists public.student_vocabulary_review_words (
  student_id uuid not null references public.students(id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete cascade,
  vocabulary_word_id uuid not null references public.vocabulary_words(id) on delete cascade,
  mistake_count integer not null default 1 check (mistake_count > 0),
  study_your_voc_mistake_count integer not null default 0
    check (study_your_voc_mistake_count >= 0),
  hangman_mistake_count integer not null default 0
    check (hangman_mistake_count >= 0),
  last_wrong_answer text,
  first_mistake_at timestamptz not null default now(),
  last_mistake_at timestamptz not null default now(),
  correct_streak integer not null default 0 check (correct_streak >= 0),
  mastered_at timestamptz,
  primary key (student_id, class_id, vocabulary_word_id)
);

create index if not exists student_vocabulary_review_active_idx
on public.student_vocabulary_review_words(student_id, class_id, last_mistake_at desc)
where mastered_at is null;

alter table public.student_vocabulary_review_words enable row level security;

revoke all on table public.student_vocabulary_review_words from public;

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
  if input_source not in ('study_your_voc', 'hangman') then
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
    last_wrong_answer = coalesce(
      nullif(trim(input_wrong_answer), ''),
      review.last_wrong_answer
    ),
    last_mistake_at = now(),
    correct_streak = 0,
    mastered_at = null;
end;
$$;

revoke all on function public.record_student_vocabulary_mistake(
  uuid,
  uuid,
  uuid,
  text,
  text
) from public;
grant execute on function public.record_student_vocabulary_mistake(
  uuid,
  uuid,
  uuid,
  text,
  text
) to authenticated;
