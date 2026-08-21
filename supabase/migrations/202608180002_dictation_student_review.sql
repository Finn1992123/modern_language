-- Reveal corrections only after the participant has submitted the dictation.

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
      'prompt', vocabulary.word,
      'answer', case when participant.submitted_at is not null then answer.answer else null end,
      'correct_answer', case when participant.submitted_at is not null then vocabulary.translation_gr else null end,
      'is_correct', case when participant.submitted_at is not null then answer.is_correct else null end
    ) order by room_word.position), '[]'::jsonb)
    into words_json
    from public.live_activity_room_words room_word
    join public.vocabulary_words vocabulary on vocabulary.id = room_word.vocabulary_word_id
    left join public.live_activity_answers answer
      on answer.participant_id = participant.id
     and answer.position = room_word.position
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

revoke all on function public.get_student_live_activity_room(uuid) from public;
revoke all on function public.submit_live_dictation_answers(uuid, jsonb) from public;
grant execute on function public.get_student_live_activity_room(uuid) to authenticated;
grant execute on function public.submit_live_dictation_answers(uuid, jsonb) to authenticated;
