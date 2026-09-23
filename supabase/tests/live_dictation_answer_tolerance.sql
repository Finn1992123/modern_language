-- Run after migrations. Raises an error on any incorrect grading result.
begin;
do $$
declare
  example record;
begin
  for example in select * from (values
    ('σπιτι', 'σπίτι', true),
    ('σπήτι', 'σπίτι', true),
    ('σπιτ', 'σπίτι', true),
    ('σπιττι', 'σπίτι', true),
    ('σπυτη', 'σπίτι', false),
    ('επικηνωνια', 'επικοινωνία', true),
    ('επυκηνωνια', 'επικοινωνία', false),
    ('επικοινωνια', 'με επικοινωνία', true),
    ('επικηνωνια', 'με επικοινωνία', true),
    ('επικοινωνία', 'με την επικοινωνία', true),
    ('την επικοινωνία', 'με την επικοινωνία', true),
    ('σπίτι', 'το σπίτι', true),
    ('σπίτι', 'στο σπίτι', true),
    ('σπίτι', 'ένα σπίτι', true),
    ('  ΤΟ   ΣΠΙΤΙ! ', 'το σπίτι', true),
    ('κοσμοσ', 'κόσμος', true),
    ('μαιοσ', 'Μάϊος', true),
    ('', 'το σπίτι', false),
    ('!!!', 'το σπίτι', false),
    (null, 'το σπίτι', false),
    ('σπίτι', null, false),
    ('με', 'με επικοινωνία', false),
    ('επικοινωνία', 'χωρίς επικοινωνία', false),
    ('καταλαβαίνω', 'δεν καταλαβαίνω', false),
    ('σπίτι', 'μεγάλο σπίτι', false),
    ('γάτα', 'σπίτι', false),
    ('αβγδεζη', 'αβγδεζη', true),
    ('χβγδεζψ', 'αβγδεζη', false),
    ('χβγδεζηψ', 'αβγδεζηθ', true)
  ) as cases(typed, correct, expected)
  loop
    if public.live_dictation_answer_matches(example.typed, example.correct)
       is distinct from example.expected then
      raise exception 'Unexpected grading: typed=%, correct=%, expected=%',
        example.typed, example.correct, example.expected;
    end if;
  end loop;
end;
$$;
rollback;
