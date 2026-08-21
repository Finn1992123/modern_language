-- Keep active rooms open to late participants until the shared timer expires.

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
  if selected_room.status not in ('waiting', 'active')
     or (
       selected_room.status = 'active'
       and selected_room.started_at
         + make_interval(secs => selected_room.duration_seconds) <= now()
     ) then
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

  if selected_room.status = 'active'
     and selected_room.started_at
       + make_interval(secs => selected_room.duration_seconds) <= now() then
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
  ) order by
    participant.score_percentage desc nulls last,
    participant.submitted_at,
    participant.joined_at
  ), '[]'::jsonb)
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

revoke all on function public.join_live_activity_room(text, uuid, uuid) from public;
revoke all on function public.get_teacher_live_activity_room(uuid) from public;
grant execute on function public.join_live_activity_room(text, uuid, uuid) to authenticated;
grant execute on function public.get_teacher_live_activity_room(uuid) to authenticated;
