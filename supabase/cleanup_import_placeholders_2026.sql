-- Removes only the empty student/student_language placeholders that were
-- automatically created for the 36 accounts imported on 2026-08-26.
-- Real students are protected by the explicit NULL predicates.

begin;

create temporary table placeholder_account_codes (
  connect_code text not null
) on commit drop;

insert into placeholder_account_codes (connect_code)
values
  ('PO2026'),
  ('LI2026'),
  ('SIA2026'),
  ('AG2026'),
  ('ST2026'),
  ('MAR2026'),
  ('KA2026'),
  ('SK2026'),
  ('SP2026'),
  ('KONTA2026'),
  ('KAA2026'),
  ('SID2026'),
  ('ZO2026'),
  ('NA2026'),
  ('GA2026'),
  ('KI2026'),
  ('MI2026'),
  ('KARA2026'),
  ('SI2026'),
  ('MAK2026'),
  ('KOU2026'),
  ('ER2026'),
  ('TZ2026'),
  ('KO2026'),
  ('STA2026'),
  ('MA2026'),
  ('HA2026'),
  ('AD2026'),
  ('KOUT2026'),
  ('LY2026'),
  ('KOSK2026'),
  ('KONSTA2026'),
  ('SPI2026'),
  ('MAN2026'),
  ('MITR2026'),
  ('KEF2026');

delete from public.students_language student_language
using public.students student,
      public.users account,
      placeholder_account_codes imported
where student_language.student_id = student.id
  and account.id = student.user_id
  and imported.connect_code = account.connect_code
  and student.name is null
  and student_language.student_name is null
  and student_language.language is null
  and student_language.class_id is null;

delete from public.students student
using public.users account,
      placeholder_account_codes imported
where account.id = student.user_id
  and imported.connect_code = account.connect_code
  and student.name is null;

commit;

-- Expected result after cleanup: 0.
select count(*) as remaining_empty_import_placeholders
from public.students_language student_language
join public.students student
  on student.id = student_language.student_id
join public.users account
  on account.id = student.user_id
where account.connect_code in (
  'PO2026', 'LI2026', 'SIA2026', 'AG2026', 'ST2026', 'MAR2026',
  'KA2026', 'SK2026', 'SP2026', 'KONTA2026', 'KAA2026', 'SID2026',
  'ZO2026', 'NA2026', 'GA2026', 'KI2026', 'MI2026', 'KARA2026',
  'SI2026', 'MAK2026', 'KOU2026', 'ER2026', 'TZ2026', 'KO2026',
  'STA2026', 'MA2026', 'HA2026', 'AD2026', 'KOUT2026', 'LY2026',
  'KOSK2026', 'KONSTA2026', 'SPI2026', 'MAN2026', 'MITR2026',
  'KEF2026'
)
  and student.name is null
  and student_language.student_name is null
  and student_language.language is null
  and student_language.class_id is null;

