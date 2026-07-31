drop function if exists public.get_tense_game_leaderboard(text, integer);

create function public.get_tense_game_leaderboard(
  input_mode text,
  input_limit integer default 100
)
returns table (
  rank bigint,
  student_id uuid,
  student_name text,
  profile_pic text,
  score integer,
  achieved_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with best_attempts as (
    select
      tgs.student_id,
      coalesce(nullif(trim(s.name), ''), 'Μαθητής') as student_name,
      s.profile_pic,
      tgs.score,
      tgs.created_at as achieved_at,
      row_number() over (
        partition by tgs.student_id
        order by tgs.score desc, tgs.created_at asc
      ) as attempt_number
    from public.tense_game_scores tgs
    join public.students s
      on s.id = tgs.student_id
    where tgs.mode = input_mode
      and input_mode in ('timeAttack', 'survival')
      and auth.uid() is not null
  ),
  leaderboard as (
    select
      row_number() over (
        order by
          best_attempts.score desc,
          best_attempts.achieved_at asc,
          best_attempts.student_name,
          best_attempts.student_id
      ) as rank,
      best_attempts.student_id,
      best_attempts.student_name,
      best_attempts.profile_pic,
      best_attempts.score,
      best_attempts.achieved_at
    from best_attempts
    where best_attempts.attempt_number = 1
  )
  select
    leaderboard.rank,
    leaderboard.student_id,
    leaderboard.student_name,
    leaderboard.profile_pic,
    leaderboard.score,
    leaderboard.achieved_at
  from leaderboard
  order by leaderboard.rank
  limit greatest(1, least(coalesce(input_limit, 100), 100));
$$;

revoke all on function public.get_tense_game_leaderboard(
  text,
  integer
) from public;

grant execute on function public.get_tense_game_leaderboard(
  text,
  integer
) to authenticated;
