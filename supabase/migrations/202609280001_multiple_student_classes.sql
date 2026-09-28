-- Keep existing enrollment IDs and all RPC signatures used by released apps.
begin;

alter table public.students_language
  add column if not exists days_hours text;

comment on column public.students_language.days_hours is
  'Optional attendance schedule for this student in this class. NULL or blank uses classes.days_hours.';

-- The original schema is managed outside this repository. Discover the old
-- student-only unique key instead of depending on its generated name.
-- Never use CASCADE: unexpected foreign-key dependencies must stop migration.
do $$
declare
  old_key record;
  student_column smallint;
begin
  select attnum into strict student_column
  from pg_attribute
  where attrelid = 'public.students_language'::regclass
    and attname = 'student_id' and not attisdropped;

  for old_key in
    select conname from pg_constraint
    where conrelid = 'public.students_language'::regclass
      and contype = 'u' and conkey = array[student_column]
  loop
    execute format('alter table public.students_language drop constraint %I', old_key.conname);
  end loop;

  -- Also handle a standalone UNIQUE index, if the original key used one.
  for old_key in
    select indexrelid::regclass as index_name
    from pg_index i
    where i.indrelid = 'public.students_language'::regclass
      and i.indisunique and not i.indisprimary
      and i.indnkeyatts = 1 and i.indkey[0] = student_column
      and not exists (select 1 from pg_constraint c where c.conindid = i.indexrelid)
  loop
    execute format('drop index %s', old_key.index_name);
  end loop;
end;
$$;

create unique index if not exists students_language_student_class_uidx
  on public.students_language(student_id, class_id);

-- CREATE OR REPLACE preserves the return shape and existing grants.
create or replace function public.get_student_language_averages(input_student_id uuid)
returns table (
  class_id uuid,
  class_name text,
  language text,
  days_hours text,
  reading numeric,
  vocabulary numeric,
  grammar numeric,
  writing numeric,
  listening numeric,
  speaking numeric,
  homework numeric,
  effort numeric,
  overall numeric
)
language sql
security definer
set search_path = public
as $$
  select
    c.id as class_id,
    c.name as class_name,
    c.language,
    coalesce(nullif(btrim(sl.days_hours), ''), c.days_hours) as days_hours,
    round(avg(sg.reading)::numeric, 2) as reading,
    round(avg(sg.vocabulary)::numeric, 2) as vocabulary,
    round(avg(sg.grammar)::numeric, 2) as grammar,
    round(avg(sg.writing)::numeric, 2) as writing,
    round(avg(sg.listening)::numeric, 2) as listening,
    round(avg(sg.speaking)::numeric, 2) as speaking,
    round(avg(sg.homework)::numeric, 2) as homework,
    round(avg(sg.effort)::numeric, 2) as effort,
    round(avg(grades.grade_value)::numeric, 2) as overall
  from public.students_language sl
  join public.students s on s.id = sl.student_id
  join public.classes c on c.id = sl.class_id
  left join public.students_grades sg
    on sg.student_language_id = sl.id and sg.student_id = s.id
  cross join lateral (
    values (sg.reading), (sg.vocabulary), (sg.grammar), (sg.writing),
      (sg.listening), (sg.speaking), (sg.homework), (sg.effort)
  ) as grades(grade_value)
  where sl.student_id = input_student_id
    and exists (
      select 1 from public.user_access ua
      where ua.user_id = s.user_id and ua.auth_user_id = auth.uid()
    )
  group by c.id, c.name, c.language, c.days_hours, sl.days_hours
  order by c.language, c.name, c.id;
$$;

grant execute on function public.get_student_language_averages(uuid) to authenticated;

commit;
