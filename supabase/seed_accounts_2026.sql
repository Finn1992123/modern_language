-- Seed generated from app.accounts (1).xlsx on 2026-08-26.
-- Insert-only: existing test profiles and all existing data remain unchanged.
-- Auth links are intentionally omitted. Users link later through connect_code.
--
-- Explicit corrections included:
--   SIA2026 for Loukia Siasiakou
--   MAR2026 for Maria Maragkou / Manos Krasanakis
--   KARA2026 for Efi Karakaxi / Flora Psaromati
--   KONTA2026 for Tonia Kontaxi payments
--   corrected student names supplied by the owner
--   Nikos Karagiannis enrolled in SC1
-- Leading/trailing whitespace from the workbook has been removed.

begin;

create temporary table import_users (
  id uuid not null default gen_random_uuid(),
  name text not null,
  surname text not null,
  email text,
  phone_number text not null,
  payment numeric not null,
  role text not null,
  connect_code text not null,
  emergency_contact bigint,
  alternative_email text
) on commit drop;

insert into import_users (
  name,
  surname,
  email,
  phone_number,
  payment,
  role,
  connect_code,
  emergency_contact,
  alternative_email
)
values
  ('Dimitra', 'Pomoni', 'dimitrapomoni@gmail.com', '6931091546', 220, 'parent', 'PO2026', '6937130764', 'xkmolyviatis@gmail.com'),
  ('Dimitra', 'Livanopoulou', 'dlivanop@hotmail.com', '6942855944', 160, 'parent', 'LI2026', null, null),
  ('Loukia', 'Siasiakou', 'lsiasiakou@gmail.com', '6974414498', 175, 'parent', 'SIA2026', null, null),
  ('Ada', 'Aggeli', 'teda@otenet.gr', '6977388466', 120, 'parent', 'AG2026', null, null),
  ('Nikoleta', 'Stathakopoulou', 'stathni@hotmail.com', '6936861234', 120, 'parent', 'ST2026', null, null),
  ('Maria', 'Maragkou', 'mmaragkou2@gmail.com', '6945316162', 120, 'parent', 'MAR2026', null, null),
  ('Xrisa', 'Kakagianni', 'xrusakakagiannh@icloud.com', '6985963908', 60, 'parent', 'KA2026', null, null),
  ('Despina', 'Sklavaki', 'despoina.latte@gmail.com', '6972850997', 65, 'parent', 'SK2026', null, null),
  ('Loukia', 'Spiratou', 'lousisp74@gmail.com', '6989719018', 80, 'parent', 'SP2026', null, null),
  ('Tonia', 'Kontaxi', 'tonia_kontaxi@yahoo.gr', '6937167994', 100, 'student', 'KONTA2026', null, null),
  ('Thomas', 'Karagiannis', 'thomas.karagiannis@yahoo.gr', '6976444033', 110, 'parent', 'KAA2026', null, null),
  ('Thalia', 'Sideri', 'thaliasideri@gmail.com', '6939749744', 90, 'parent', 'SID2026', null, null),
  ('Daphne', 'Zouka', 'dzouka@yahoo.com', '6970125788', 100, 'parent', 'ZO2026', null, null),
  ('Sofia', 'Nanopoulou', 'nanopoulou_sofia@yahoo.com', '6973898924', 120, 'parent', 'NA2026', null, null),
  ('Evaggelos', 'Garoufalis', 'aspa-103@hotmail.com', '6976587877', 55, 'parent', 'GA2026', '6933345981', null),
  ('Vasiliki', 'Kitsou', 'vasokitsou@gmail.com', '6947775318', 52, 'parent', 'KI2026', '6945958809', null),
  ('Magdalini', 'Milioni', 'magdalinimilioni@gmail.com', '6980292798', 30, 'parent', 'MI2026', '6980292798', null),
  ('Efi', 'Karakaxi', 'karakaxiefaki@gmail.com', '6987854722', 120, 'parent', 'KARA2026', '2114130089', null),
  ('Spiridoula', 'Sioula', 'spyridoulasioula2018@gmail.com', '6977274836', 55, 'parent', 'SI2026', '6939470329', null),
  ('Stilianos', 'Makrodimitris', 'makrodim88@yahoo.gr', '6949844429', 130, 'parent', 'MAK2026', '6977618476', null),
  ('Kon/na', 'Koumpoula', 'konsko@gmail.com', '6948000375', 40, 'parent', 'KOU2026', '6977354650', null),
  ('Lily', 'Ermi', 'lkastratos@gmail.com', '6976518410', 80, 'parent', 'ER2026', '6945435009', null),
  ('Despina', 'Tzina', 'tzinadesp@gmail.com', '6906060056', 120, 'parent', 'TZ2026', '6906060057', null),
  ('Dimitra', 'Kotsi', 'dimitrakts1992@gmail.com', '6942040964', 55, 'parent', 'KO2026', '6984343360', null),
  ('Roula', 'Stavrianou', 'xristosroula111@gmail.com', '6978458080', 80, 'parent', 'STA2026', '6978762776', null),
  ('Adelina', 'Marku', 'adelinarajta@gmail.com', '6994280990', 80, 'parent', 'MA2026', null, null),
  ('Valentina', 'Hajdinaj', 'valentinahajdinaj8@gmail.com', '6945250014', 80, 'parent', 'HA2026', null, null),
  ('Athanasia', 'Adoniadi', 'nansyantoniadi@hotmail.gr', '6948277758', 145, 'parent', 'AD2026', '6956655245', null),
  ('Agi', 'Koutoula', 'agathikoutoula@gmail.com', '6945758491', 30, 'parent', 'KOUT2026', '6983402414', null),
  ('Maria', 'Lyraraki', 'marialyraraki1@hotmail.com', '6909027141', 30, 'parent', 'LY2026', '6942596124', null),
  ('Vasilia', 'Koskina', 'basiliakoskina1986@yahoo.com', '6944127434', 30, 'parent', 'KOSK2026', '6948824695', null),
  ('Melpomeni', 'Konsta', 'konsmelp@yahoo.gr', '6982889470', 95, 'parent', 'KONSTA2026', '6983510907', null),
  ('Elena', 'Spiropoulou', 'elespiropoulou@gmail.com', '6909438525', 75, 'parent', 'SPI2026', '6978895275', null),
  ('Natasa', 'Manoula', 'kiriaki.manoula@gmail.com', '6948595291', 55, 'parent', 'MAN2026', '2112167852', null),
  ('Razvan', 'Mitreanu', 'razvan.mitreanu@gmail.com', '6973590068', 0, 'headteacher', 'MITR2026', null, null),
  ('Athina', 'Kefala', 'athenakefala37@gmail.com', '6983358514', 0, 'teacher', 'KEF2026', null, null);

create temporary table import_students (
  id uuid not null default gen_random_uuid(),
  user_connect_code text not null,
  name text not null,
  gender text not null
) on commit drop;

insert into import_students (user_connect_code, name, gender)
values
  ('PO2026', 'Ektoras Molyviatis', 'm'),
  ('PO2026', 'Phaedra Molyviati', 'f'),
  ('LI2026', 'Nikolas Galanis', 'm'),
  ('LI2026', 'George Galanis', 'm'),
  ('SIA2026', 'Orestis Raftopoulos', 'm'),
  ('SIA2026', 'Philip Raftopoulos', 'm'),
  ('AG2026', 'Pavlina Andrianopoulou', 'f'),
  ('ST2026', 'Marios Tsapelas', 'm'),
  ('MAR2026', 'Manos Krasanakis', 'm'),
  ('KA2026', 'Stathis Zografakis', 'm'),
  ('SK2026', 'Anastasia Makadasi', 'f'),
  ('SP2026', 'Anastasia Nikologianni', 'f'),
  ('KAA2026', 'Nikos Karagiannis', 'm'),
  ('KAA2026', 'George Karagiannis', 'm'),
  ('SID2026', 'Zoe', 'f'),
  ('ZO2026', 'Zoe Zouka', 'f'),
  ('ZO2026', 'Stavroula Zouka', 'f'),
  ('NA2026', 'Dimitra Marini', 'f'),
  ('GA2026', 'Jason Garoufalis', 'm'),
  ('KI2026', 'Lambrini', 'f'),
  ('MI2026', 'Catherine', 'f'),
  ('SI2026', 'Sofianos', 'm'),
  ('MAK2026', 'Dimitris Makrodimitris', 'm'),
  ('MAK2026', 'Maria Makrodimitri', 'f'),
  ('MAK2026', 'Panagiotis Makrodimitris', 'm'),
  ('KOU2026', 'Christianna', 'f'),
  ('ER2026', 'Nikolas Laliotis', 'm'),
  ('TZ2026', 'Themis', 'm'),
  ('TZ2026', 'Louiza', 'f'),
  ('KO2026', 'Kon/nos Pavlopoulos', 'm'),
  ('STA2026', 'Melina', 'f'),
  ('STA2026', 'Andrianos', 'm'),
  ('STA2026', 'Nefeli', 'f'),
  ('MA2026', 'Daniel Marku', 'm'),
  ('HA2026', 'Aris', 'm'),
  ('AD2026', 'Rebecca Magiati', 'f'),
  ('AD2026', 'Veronica Magiati', 'f'),
  ('KOUT2026', 'Chrisenia Valsami', 'f'),
  ('LY2026', 'Nefeli Kagianni', 'f'),
  ('KOSK2026', 'Kon/nos Nikolaidis', 'm'),
  ('KARA2026', 'Flora Psaromati', 'f'),
  ('KONSTA2026', 'Dimitra Berdeni', 'f'),
  ('KONSTA2026', 'Panagiotis Berdenis', 'm'),
  ('SPI2026', 'Emmanouela Legaki', 'f'),
  ('SPI2026', 'Kon/na Legaki', 'f'),
  ('MAN2026', 'Kiriaki Anastasiou', 'f'),
  ('MAN2026', 'Panagiota Anastasiou', 'f');

create temporary table import_classes (
  id uuid not null default gen_random_uuid(),
  class_ref text not null,
  teacher_connect_code text not null,
  name text not null,
  language text not null,
  days_hours text
) on commit drop;

insert into import_classes (
  class_ref,
  teacher_connect_code,
  name,
  language,
  days_hours
)
values
  ('JA1', 'KEF2026', 'JA1', 'english', 'Τρίτη - Πέμπτη 6:30 - 7:30'),
  ('JA2', 'MITR2026', 'JA2', 'english', 'Δευτέρα - Τετάρτη 4:00 - 5:00'),
  ('JB1', 'KEF2026', 'JB1', 'english', 'Τρίτη - Πέμπτη 5:30 - 6:30'),
  ('SA1', 'KEF2026', 'SA1', 'english', 'Τρίτη - Πέμπτη 7:30 - 8:30'),
  ('SA2', 'MITR2026', 'SA2', 'english', 'Δευτέρα - Τετάρτη 5:00 - 6:00'),
  ('SB1', 'MITR2026', 'SB1', 'english', 'Δευτέρα 6:00 - 7:00 & Τετάρτη 7:00 - 8:00'),
  ('SC1', 'MITR2026', 'SC1', 'english', 'Τρίτη - Πέμπτη 5:00 - 6:00'),
  ('SD1', 'MITR2026', 'SD1', 'english', 'Τρίτη - Πέμπτη 6:00 - 7:30'),
  ('Pre - Lower1', 'MITR2026', 'Pre - Lower1', 'english', 'Δευτέρα 7:00 - 8:30 & Παρασκευή 5:30 - 7:00'),
  ('Lower1', 'MITR2026', 'Lower1', 'english', 'Τρίτη - Πεμπτη 7:30 - 9:00'),
  ('Advanced1', 'MITR2026', 'Advanced1', 'english', 'Τετάρτη 8:00 - 10:00 & Παρασκευή 7:00 - 9:00'),
  ('Pre - Junior1', 'MITR2026', 'Pre - Junior1', 'english', 'Τετάρτη 6:00 - 7:00');

create temporary table import_enrollments (
  user_connect_code text not null,
  student_name text not null,
  class_ref text not null
) on commit drop;

insert into import_enrollments (
  user_connect_code,
  student_name,
  class_ref
)
values
  ('PO2026', 'Ektoras Molyviatis', 'Pre - Lower1'),
  ('PO2026', 'Phaedra Molyviati', 'Advanced1'),
  ('LI2026', 'Nikolas Galanis', 'Lower1'),
  ('LI2026', 'George Galanis', 'JB1'),
  ('SIA2026', 'Philip Raftopoulos', 'SB1'),
  ('SIA2026', 'Orestis Raftopoulos', 'Advanced1'),
  ('AG2026', 'Pavlina Andrianopoulou', 'Advanced1'),
  ('ST2026', 'Marios Tsapelas', 'Advanced1'),
  ('MAR2026', 'Manos Krasanakis', 'Lower1'),
  ('KA2026', 'Stathis Zografakis', 'SB1'),
  ('SK2026', 'Anastasia Makadasi', 'SC1'),
  ('SP2026', 'Anastasia Nikologianni', 'SD1'),
  ('KAA2026', 'Nikos Karagiannis', 'SC1'),
  ('KAA2026', 'George Karagiannis', 'SA1'),
  ('SID2026', 'Zoe', 'Pre - Lower1'),
  ('ZO2026', 'Zoe Zouka', 'SB1'),
  ('ZO2026', 'Stavroula Zouka', 'SB1'),
  ('NA2026', 'Dimitra Marini', 'Lower1'),
  ('GA2026', 'Jason Garoufalis', 'SA2'),
  ('KI2026', 'Lambrini', 'SC1'),
  ('MI2026', 'Catherine', 'JA1'),
  ('KARA2026', 'Flora Psaromati', 'Advanced1'),
  ('SI2026', 'Sofianos', 'SA2'),
  ('MAK2026', 'Dimitris Makrodimitris', 'JA1'),
  ('MAK2026', 'Maria Makrodimitri', 'SC1'),
  ('MAK2026', 'Panagiotis Makrodimitris', 'SA1'),
  ('KOU2026', 'Christianna', 'JB1'),
  ('ER2026', 'Nikolas Laliotis', 'SD1'),
  ('TZ2026', 'Louiza', 'JA2'),
  ('TZ2026', 'Themis', 'Pre - Lower1'),
  ('KO2026', 'Kon/nos Pavlopoulos', 'SA2'),
  ('STA2026', 'Melina', 'JB1'),
  ('STA2026', 'Andrianos', 'JB1'),
  ('MA2026', 'Daniel Marku', 'SD1'),
  ('HA2026', 'Aris', 'SD1'),
  ('AD2026', 'Veronica Magiati', 'SC1'),
  ('AD2026', 'Rebecca Magiati', 'SD1'),
  ('KOUT2026', 'Chrisenia Valsami', 'JA1'),
  ('LY2026', 'Nefeli Kagianni', 'JA1'),
  ('KOSK2026', 'Kon/nos Nikolaidis', 'JA2'),
  ('KONSTA2026', 'Dimitra Berdeni', 'SC1'),
  ('KONSTA2026', 'Panagiotis Berdenis', 'JA1'),
  ('SPI2026', 'Emmanouela Legaki', 'JA1'),
  ('SPI2026', 'Kon/na Legaki', 'SA1'),
  ('MAN2026', 'Panagiota Anastasiou', 'Pre - Junior1'),
  ('STA2026', 'Nefeli', 'Pre - Junior1'),
  ('MAN2026', 'Kiriaki Anastasiou', 'SA2');

create temporary table import_payments (
  user_connect_code text not null,
  january boolean not null,
  february boolean not null,
  march boolean not null,
  april boolean not null,
  may boolean not null,
  june boolean not null,
  july boolean not null,
  august boolean not null,
  september boolean not null,
  october boolean not null,
  november boolean not null,
  december boolean not null
) on commit drop;

insert into import_payments (
  user_connect_code,
  january,
  february,
  march,
  april,
  may,
  june,
  july,
  august,
  september,
  october,
  november,
  december
)
values
  ('PO2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false'),
  ('LI2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false'),
  ('SIA2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false'),
  ('AG2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false'),
  ('ST2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false'),
  ('MAR2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false'),
  ('KA2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false'),
  ('SK2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false'),
  ('SP2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false'),
  ('KAA2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false'),
  ('KONTA2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false'),
  ('SID2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false'),
  ('ZO2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false'),
  ('NA2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false'),
  ('GA2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false'),
  ('KI2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false'),
  ('MI2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'true', 'false', 'false', 'false'),
  ('KARA2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false'),
  ('SI2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false'),
  ('MAK2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'true', 'false', 'false', 'false'),
  ('KOU2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false'),
  ('ER2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false'),
  ('TZ2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false'),
  ('KO2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false'),
  ('STA2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false'),
  ('MA2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false'),
  ('HA2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false'),
  ('AD2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false'),
  ('KOUT2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'true', 'false', 'false', 'false'),
  ('LY2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'true', 'false', 'false', 'false'),
  ('KOSK2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false'),
  ('KONSTA2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false'),
  ('SPI2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'true', 'false', 'false', 'false'),
  ('MAN2026', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false', 'false');

-- Abort before touching public tables if an import-only reference is unresolved.
do $validation$
begin
  if exists (
    select 1
    from import_students student
    left join import_users parent
      on parent.connect_code = student.user_connect_code
    where parent.id is null
  ) then
    raise exception 'A student references a missing imported user';
  end if;

  if exists (
    select 1
    from import_classes class
    left join import_users teacher
      on teacher.connect_code = class.teacher_connect_code
    where teacher.id is null
  ) then
    raise exception 'A class references a missing imported teacher';
  end if;

  if exists (
    select 1
    from import_enrollments enrollment
    left join import_students student
      on student.user_connect_code = enrollment.user_connect_code
     and student.name = enrollment.student_name
    left join import_classes class
      on class.class_ref = enrollment.class_ref
    where student.id is null or class.id is null
  ) then
    raise exception 'An enrollment references a missing imported student or class';
  end if;

  if exists (
    select 1
    from import_payments payment
    left join import_users account
      on account.connect_code = payment.user_connect_code
    where account.id is null
  ) then
    raise exception 'A payment references a missing imported user';
  end if;
end
$validation$;

insert into public.users (
  id,
  name,
  surname,
  email,
  phone_number,
  payment,
  role,
  connect_code,
  emergency_contact,
  alternative_email
)
select
  id,
  name,
  surname,
  email,
  phone_number,
  payment,
  role,
  connect_code,
  emergency_contact,
  alternative_email
from import_users;

insert into public.students (
  id,
  user_id,
  parent_name,
  phone_number,
  name,
  gender
)
select
  student.id,
  parent.id,
  concat_ws(' ', parent.name, parent.surname),
  null,
  student.name,
  student.gender
from import_students student
join import_users parent
  on parent.connect_code = student.user_connect_code;

insert into public.classes (
  id,
  days_hours,
  online_link,
  teacher_in_charge,
  language,
  name,
  book_id,
  cefr_book_id
)
select
  class.id,
  class.days_hours,
  null,
  teacher.id,
  class.language,
  class.name,
  null,
  null
from import_classes class
join import_users teacher
  on teacher.connect_code = class.teacher_connect_code;

insert into public.students_language (
  student_id,
  parent_name,
  student_name,
  language,
  class_id
)
select
  student.id,
  concat_ws(' ', parent.name, parent.surname),
  student.name,
  class.language,
  class.id
from import_enrollments enrollment
join import_students student
  on student.user_connect_code = enrollment.user_connect_code
 and student.name = enrollment.student_name
join import_users parent
  on parent.connect_code = student.user_connect_code
join import_classes class
  on class.class_ref = enrollment.class_ref
on conflict (student_id) do update
set
  parent_name = excluded.parent_name,
  student_name = excluded.student_name,
  language = excluded.language,
  class_id = excluded.class_id;

insert into public.payments (
  user_id,
  user_name,
  january,
  february,
  march,
  april,
  may,
  june,
  july,
  august,
  september,
  october,
  november,
  december
)
select
  account.id,
  concat_ws(' ', account.name, account.surname),
  payment.january,
  payment.february,
  payment.march,
  payment.april,
  payment.may,
  payment.june,
  payment.july,
  payment.august,
  payment.september,
  payment.october,
  payment.november,
  payment.december
from import_payments payment
join import_users account
  on account.connect_code = payment.user_connect_code
on conflict (user_id) do update
set
  user_name = excluded.user_name,
  january = excluded.january,
  february = excluded.february,
  march = excluded.march,
  april = excluded.april,
  may = excluded.may,
  june = excluded.june,
  july = excluded.july,
  august = excluded.august,
  september = excluded.september,
  october = excluded.october,
  november = excluded.november,
  december = excluded.december;

commit;
