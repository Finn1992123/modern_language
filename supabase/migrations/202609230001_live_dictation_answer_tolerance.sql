-- Match Greek dictation answers with the Study your voc spelling tolerance.
-- Leading articles/prepositions may be omitted, but content words stay required.
create or replace function public.live_normalize_answer(input_value text)
returns text
language sql
immutable
set search_path = public
as $$
  select trim(regexp_replace(
    regexp_replace(
      translate(lower(coalesce(input_value, '')),
        'άέήίόύώϊΐϋΰς', 'αεηιουωιιυυσ'),
      '[^a-z0-9α-ω\s]', '', 'g'),
    '\s+', ' ', 'g'));
$$;

create or replace function public.live_answer_within_tolerance(typed text, correct text)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  tolerance integer := case when char_length(correct) >= 8 then 2 else 1 end;
  previous_row integer[];
  current_row integer[];
  typed_index integer;
  correct_index integer;
begin
  if coalesce(typed, '') = '' or coalesce(correct, '') = '' then return false; end if;
  if typed = correct then return true; end if;
  if abs(char_length(typed) - char_length(correct)) > tolerance then return false; end if;

  select array_agg(value order by value) into previous_row
  from generate_series(0, char_length(correct)) value;
  for typed_index in 1..char_length(typed) loop
    current_row := array[typed_index];
    for correct_index in 1..char_length(correct) loop
      current_row := array_append(current_row, least(
        current_row[correct_index] + 1,
        previous_row[correct_index + 1] + 1,
        previous_row[correct_index] + case
          when substr(typed, typed_index, 1) = substr(correct, correct_index, 1)
          then 0 else 1 end));
    end loop;
    if (select min(value) from unnest(current_row) value) > tolerance then return false; end if;
    previous_row := current_row;
  end loop;
  return previous_row[char_length(correct) + 1] <= tolerance;
end;
$$;

create or replace function public.live_dictation_answer_matches(typed text, correct text)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  normalized_typed text := public.live_normalize_answer(typed);
  candidate text := public.live_normalize_answer(correct);
  optional_prefixes constant text[] := array[
    'ο', 'η', 'το', 'οι', 'τα', 'του', 'τησ', 'των', 'τον', 'την', 'τη', 'τουσ', 'τισ',
    'ενασ', 'μια', 'μιασ', 'ενα', 'ενοσ', 'εναν',
    'με', 'σε', 'απο', 'για', 'στο', 'στον', 'στη', 'στην', 'στα', 'στουσ', 'στισ',
    'στου', 'στησ', 'στων'
  ];
begin
  if normalized_typed = '' or candidate = '' then return false; end if;
  loop
    if public.live_answer_within_tolerance(normalized_typed, candidate) then return true; end if;
    -- Only drop complete, leading function words from the expected answer.
    -- Never drop negation or reduce a single-word answer to an empty string.
    exit when position(' ' in candidate) = 0
      or not (split_part(candidate, ' ', 1) = any(optional_prefixes));
    candidate := substr(candidate, position(' ' in candidate) + 1);
  end loop;
  return false;
end;
$$;

revoke all on function public.live_answer_within_tolerance(text, text) from public;
revoke all on function public.live_dictation_answer_matches(text, text) from public;

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
  review_json jsonb;
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
        where public.live_dictation_answer_matches(
          case when submission_expired then '' else answer_row.answer end,
          accepted.value
        )
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

  select coalesce(jsonb_agg(jsonb_build_object(
    'position', room_word.position,
    'prompt', vocabulary.word,
    'answer', answer.answer,
    'correct_answer', vocabulary.translation_gr,
    'is_correct', answer.is_correct
  ) order by room_word.position), '[]'::jsonb)
  into review_json
  from public.live_activity_room_words room_word
  join public.vocabulary_words vocabulary on vocabulary.id = room_word.vocabulary_word_id
  join public.live_activity_answers answer
    on answer.participant_id = participant.id
   and answer.position = room_word.position
  where room_word.room_id = selected_room.id;

  return jsonb_build_object(
    'correct_count', correct_total,
    'word_count', word_total,
    'score_percentage', score_value,
    'words', review_json
  );
end;
$$;
