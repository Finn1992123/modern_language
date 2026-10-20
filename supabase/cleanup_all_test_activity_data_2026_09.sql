-- ONE-TIME DESTRUCTIVE CLEANUP.
-- Deletes test activity/teaching data while preserving accounts, students,
-- classes, enrolments, payments, expenses, Auth links and learning content.
-- Run the whole file in the Supabase SQL Editor.

begin;

create temporary table deleted_test_data_counts (
  table_name text primary key,
  deleted_rows bigint not null
) on commit preserve rows;

do $cleanup$
declare
  affected bigint;
begin
  -- Exercise results and teacher-created assignments.
  if to_regclass('public.personal_vocabulary_assignment_successes') is not null then
    delete from public.personal_vocabulary_assignment_successes;
    get diagnostics affected = row_count;
    insert into deleted_test_data_counts values ('personal_vocabulary_assignment_successes', affected);
  end if;

  if to_regclass('public.exercise_assignment_attempt_items') is not null then
    delete from public.exercise_assignment_attempt_items;
    get diagnostics affected = row_count;
    insert into deleted_test_data_counts values ('exercise_assignment_attempt_items', affected);
  end if;

  if to_regclass('public.exercise_assignment_personal_words') is not null then
    delete from public.exercise_assignment_personal_words;
    get diagnostics affected = row_count;
    insert into deleted_test_data_counts values ('exercise_assignment_personal_words', affected);
  end if;

  if to_regclass('public.reader_assignment_settings') is not null then
    delete from public.reader_assignment_settings;
    get diagnostics affected = row_count;
    insert into deleted_test_data_counts values ('reader_assignment_settings', affected);
  end if;

  if to_regclass('public.vocabulary_assignment_settings') is not null then
    delete from public.vocabulary_assignment_settings;
    get diagnostics affected = row_count;
    insert into deleted_test_data_counts values ('vocabulary_assignment_settings', affected);
  end if;

  if to_regclass('public.hangman_assignment_settings') is not null then
    delete from public.hangman_assignment_settings;
    get diagnostics affected = row_count;
    insert into deleted_test_data_counts values ('hangman_assignment_settings', affected);
  end if;

  if to_regclass('public.timed_question_assignment_settings') is not null then
    delete from public.timed_question_assignment_settings;
    get diagnostics affected = row_count;
    insert into deleted_test_data_counts values ('timed_question_assignment_settings', affected);
  end if;

  if to_regclass('public.exercise_assignment_attempts') is not null then
    delete from public.exercise_assignment_attempts;
    get diagnostics affected = row_count;
    insert into deleted_test_data_counts values ('exercise_assignment_attempts', affected);
  end if;

  if to_regclass('public.exercise_assignment_classes') is not null then
    delete from public.exercise_assignment_classes;
    get diagnostics affected = row_count;
    insert into deleted_test_data_counts values ('exercise_assignment_classes', affected);
  end if;

  if to_regclass('public.exercise_assignments') is not null then
    delete from public.exercise_assignments;
    get diagnostics affected = row_count;
    insert into deleted_test_data_counts values ('exercise_assignments', affected);
  end if;

  -- Live dictation/activity sessions and their results.
  if to_regclass('public.live_activity_answers') is not null then
    delete from public.live_activity_answers;
    get diagnostics affected = row_count;
    insert into deleted_test_data_counts values ('live_activity_answers', affected);
  end if;

  if to_regclass('public.live_activity_participants') is not null then
    delete from public.live_activity_participants;
    get diagnostics affected = row_count;
    insert into deleted_test_data_counts values ('live_activity_participants', affected);
  end if;

  if to_regclass('public.live_activity_room_words') is not null then
    delete from public.live_activity_room_words;
    get diagnostics affected = row_count;
    insert into deleted_test_data_counts values ('live_activity_room_words', affected);
  end if;

  if to_regclass('public.live_activity_rooms') is not null then
    delete from public.live_activity_rooms;
    get diagnostics affected = row_count;
    insert into deleted_test_data_counts values ('live_activity_rooms', affected);
  end if;

  -- Homework, curriculum, grades and absences.
  if to_regclass('public.personal_homework') is not null then
    delete from public.personal_homework;
    get diagnostics affected = row_count;
    insert into deleted_test_data_counts values ('personal_homework', affected);
  end if;

  if to_regclass('public.students_grades') is not null then
    delete from public.students_grades;
    get diagnostics affected = row_count;
    insert into deleted_test_data_counts values ('students_grades', affected);
  end if;

  if to_regclass('public.absences') is not null then
    delete from public.absences;
    get diagnostics affected = row_count;
    insert into deleted_test_data_counts values ('absences', affected);
  end if;

  if to_regclass('public.curriculum') is not null then
    delete from public.curriculum;
    get diagnostics affected = row_count;
    insert into deleted_test_data_counts values ('curriculum', affected);
  end if;

  -- Medals, leaderboards, game progress and vocabulary mistakes.
  if to_regclass('public."juniorAchievements"') is not null then
    delete from public."juniorAchievements";
    get diagnostics affected = row_count;
    insert into deleted_test_data_counts values ('juniorAchievements', affected);
  end if;

  if to_regclass('public.tense_game_scores') is not null then
    delete from public.tense_game_scores;
    get diagnostics affected = row_count;
    insert into deleted_test_data_counts values ('tense_game_scores', affected);
  end if;

  if to_regclass('public.study_gram_attempts') is not null then
    delete from public.study_gram_attempts;
    get diagnostics affected = row_count;
    insert into deleted_test_data_counts values ('study_gram_attempts', affected);
  end if;

  if to_regclass('public.reader_completions') is not null then
    delete from public.reader_completions;
    get diagnostics affected = row_count;
    insert into deleted_test_data_counts values ('reader_completions', affected);
  end if;

  if to_regclass('public.student_vocabulary_review_words') is not null then
    delete from public.student_vocabulary_review_words;
    get diagnostics affected = row_count;
    insert into deleted_test_data_counts values ('student_vocabulary_review_words', affected);
  end if;

  -- Teacher-created test announcements. Device registrations are preserved.
  if to_regclass('public.announcements') is not null then
    delete from public.announcements;
    get diagnostics affected = row_count;
    insert into deleted_test_data_counts values ('announcements', affected);
  end if;
end
$cleanup$;

commit;

-- Shows exactly how many rows were deleted from each existing table.
select table_name, deleted_rows
from deleted_test_data_counts
order by table_name;
