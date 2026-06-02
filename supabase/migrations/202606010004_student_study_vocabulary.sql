create or replace function public.get_student_study_vocabulary(
  input_student_id uuid,
  input_class_id uuid
)
returns table (
  id uuid,
  cefr_book_id integer,
  book_name text,
  language text,
  level text,
  unit text,
  unit_order integer,
  word text,
  translation_gr text,
  accepted_words text,
  part_of_speech text,
  example_sentence text,
  is_important boolean
)
language sql
security definer
set search_path = public
as $$
  select
    vw.id,
    vw.cefr_book_id,
    vw.book_name,
    coalesce(vw.language, c.language) as language,
    vw.level,
    vw.unit,
    vw.unit_order,
    vw.word,
    vw.translation_gr,
    vw.accepted_words,
    vw.part_of_speech,
    vw.example_sentence,
    vw.is_important
  from public.classes c
  join public.vocabulary_words vw
    on vw.cefr_book_id = c.cefr_book_id
  where c.id = input_class_id
    and vw.is_active = true
    and exists (
      select 1
      from public.students s
      join public.students_language sl
        on sl.student_id = s.id
      join public.user_access ua
        on ua.user_id = s.user_id
      where s.id = input_student_id
        and sl.class_id = input_class_id
        and ua.auth_user_id = auth.uid()
    )
  order by vw.unit_order nulls last, vw.unit, vw.word;
$$;

grant execute on function public.get_student_study_vocabulary(uuid, uuid)
to authenticated;
