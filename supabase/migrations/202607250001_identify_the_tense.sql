create table if not exists public.tense_questions (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  sentence text not null unique,
  tense text not null check (
    tense in (
      'Present simple',
      'Present continuous',
      'Present perfect',
      'Present perfect continuous',
      'Past simple',
      'Past continuous',
      'Past perfect',
      'Past perfect continuous',
      'Future simple',
      'Future continuous',
      'Future perfect',
      'Future perfect continuous',
      'Passive voice',
      'Reported speech',
      'Conditional'
    )
  ),
  highlight_phrases text[] not null default '{}',
  language text not null default 'English',
  is_active boolean not null default true,
  check (length(trim(sentence)) > 0),
  check (cardinality(highlight_phrases) > 0)
);

create index if not exists tense_questions_active_language_idx
on public.tense_questions(language, is_active)
where is_active = true;

alter table public.tense_questions enable row level security;

drop policy if exists "Authenticated users can read active tense questions"
on public.tense_questions;

create policy "Authenticated users can read active tense questions"
on public.tense_questions
for select
to authenticated
using (is_active = true);

create table if not exists public.tense_game_scores (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  student_id uuid not null references public.students(id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete cascade,
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  mode text not null check (mode in ('timeAttack', 'survival')),
  score integer not null check (score >= 0)
);

create index if not exists tense_game_scores_student_idx
on public.tense_game_scores(student_id, created_at desc);

create index if not exists tense_game_scores_auth_user_idx
on public.tense_game_scores(auth_user_id, created_at desc);

alter table public.tense_game_scores enable row level security;

drop policy if exists "Users can read their tense game scores"
on public.tense_game_scores;

create policy "Users can read their tense game scores"
on public.tense_game_scores
for select
to authenticated
using (auth_user_id = auth.uid());

create or replace function public.submit_tense_game_score(
  input_student_id uuid,
  input_class_id uuid,
  input_mode text,
  input_score integer
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_score_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if input_mode not in ('timeAttack', 'survival') then
    raise exception 'invalid game mode';
  end if;

  if input_score < 0 then
    raise exception 'score cannot be negative';
  end if;

  if not exists (
    select 1
    from public.students s
    join public.students_language sl
      on sl.student_id = s.id
    join public.user_access ua
      on ua.user_id = s.user_id
    where s.id = input_student_id
      and sl.class_id = input_class_id
      and ua.auth_user_id = auth.uid()
  ) then
    raise exception 'student or class access denied';
  end if;

  insert into public.tense_game_scores (
    student_id,
    class_id,
    auth_user_id,
    mode,
    score
  )
  values (
    input_student_id,
    input_class_id,
    auth.uid(),
    input_mode,
    input_score
  )
  returning id into new_score_id;

  return new_score_id;
end;
$$;

revoke all on function public.submit_tense_game_score(
  uuid,
  uuid,
  text,
  integer
) from public;

grant execute on function public.submit_tense_game_score(
  uuid,
  uuid,
  text,
  integer
) to authenticated;

insert into public.tense_questions (
  sentence,
  tense,
  highlight_phrases
)
values
  (
    'Emma walks to school every day.',
    'Present simple',
    array['walks', 'every day']
  ),
  (
    'My brother usually drinks coffee in the morning.',
    'Present simple',
    array['drinks', 'usually']
  ),
  (
    'John is playing football now.',
    'Present continuous',
    array['is playing', 'now']
  ),
  (
    'They are studying for their exam at the moment.',
    'Present continuous',
    array['are studying', 'at the moment']
  ),
  (
    'We have already finished our homework.',
    'Present perfect',
    array['have finished', 'already']
  ),
  (
    'She has never visited Scotland.',
    'Present perfect',
    array['has visited', 'never']
  ),
  (
    'Tom has been studying for three hours.',
    'Present perfect continuous',
    array['has been studying', 'for three hours']
  ),
  (
    'It has been raining since this morning.',
    'Present perfect continuous',
    array['has been raining', 'since this morning']
  ),
  (
    'We visited Rome last summer.',
    'Past simple',
    array['visited', 'last summer']
  ),
  (
    'Sophie bought a new laptop yesterday.',
    'Past simple',
    array['bought', 'yesterday']
  ),
  (
    'They were watching television at eight o''clock.',
    'Past continuous',
    array['were watching', 'at eight o''clock']
  ),
  (
    'I was cooking when the phone rang.',
    'Past continuous',
    array['was cooking', 'when the phone rang']
  ),
  (
    'The train had left before we reached the station.',
    'Past perfect',
    array['had left', 'before we reached']
  ),
  (
    'She had completed the test by noon.',
    'Past perfect',
    array['had completed', 'by noon']
  ),
  (
    'We had been waiting for an hour before the bus arrived.',
    'Past perfect continuous',
    array['had been waiting', 'for an hour']
  ),
  (
    'He had been working all day, so he was exhausted.',
    'Past perfect continuous',
    array['had been working', 'all day']
  ),
  (
    'I will call you tomorrow.',
    'Future simple',
    array['will call', 'tomorrow']
  ),
  (
    'They will probably arrive soon.',
    'Future simple',
    array['will arrive', 'probably']
  ),
  (
    'This time tomorrow, we will be flying to Paris.',
    'Future continuous',
    array['will be flying', 'this time tomorrow']
  ),
  (
    'At nine tonight, she will be studying.',
    'Future continuous',
    array['will be studying', 'at nine tonight']
  ),
  (
    'By Friday, I will have completed the report.',
    'Future perfect',
    array['will have completed', 'by Friday']
  ),
  (
    'They will have arrived by the time the meeting starts.',
    'Future perfect',
    array['will have arrived', 'by the time']
  ),
  (
    'By June, she will have been teaching here for ten years.',
    'Future perfect continuous',
    array['will have been teaching', 'for ten years', 'by June']
  ),
  (
    'Next month, we will have been living here for a year.',
    'Future perfect continuous',
    array['will have been living', 'for a year', 'next month']
  ),
  (
    'The museum was built in 1890.',
    'Passive voice',
    array['was built', 'in 1890']
  ),
  (
    'The classrooms are cleaned every morning.',
    'Passive voice',
    array['are cleaned', 'every morning']
  ),
  (
    'Anna said that she was feeling tired.',
    'Reported speech',
    array['said that', 'was feeling']
  ),
  (
    'He told me that he had lost his keys.',
    'Reported speech',
    array['told me that', 'had lost']
  ),
  (
    'If it rains, we will stay at home.',
    'Conditional',
    array['if it rains', 'will stay']
  ),
  (
    'If I had more time, I would learn Japanese.',
    'Conditional',
    array['if I had', 'would learn']
  )
on conflict (sentence) do update
set
  tense = excluded.tense,
  highlight_phrases = excluded.highlight_phrases,
  language = excluded.language,
  is_active = true;
