// npm install --no-save --package-lock=false @electric-sql/pglite
// node --test scripts/multiple-student-classes.test.mjs
// PGLITE_MODULE may point to an installation outside the repository.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { pathToFileURL } from 'node:url';

const { PGlite } = await import(process.env.PGLITE_MODULE
  ? pathToFileURL(process.env.PGLITE_MODULE).href : '@electric-sql/pglite');
const read = (path) => readFile(new URL(`../supabase/${path}`, import.meta.url), 'utf8');
const migration = await read('migrations/202609280001_multiple_student_classes.sql');
const overviewMigration = await read('migrations/202609280002_student_language_overview.sql');
const template = await read('enroll_student_in_class.sql');
const id = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const parent = id(1), student = id(2), group = id(3), privateClass = id(4);
const enrollment = id(5), teacher = id(6), stranger = id(7);

async function fixture(indexOnly = false) {
  const db = new PGlite();
  await db.exec(`
    create role authenticated;
    create schema auth;
    create function auth.uid() returns uuid language sql as
      $$ select nullif(current_setting('test.auth_uid', true), '')::uuid $$;
    create table users (id uuid primary key, name text, surname text, role text);
    create table students (id uuid primary key, user_id uuid references users, name text);
    create table user_access (user_id uuid references users, auth_user_id uuid);
    create table classes (id uuid primary key, name text, language text,
      days_hours text, teacher_in_charge uuid references users);
    create table students_language (
      id uuid primary key default gen_random_uuid(),
      student_id uuid references students ${indexOnly ? '' : 'unique'},
      class_id uuid references classes, parent_name text, student_name text, language text);
    ${indexOnly ? 'create unique index legacy_student_key on students_language(student_id);' : ''}
    create table students_grades (
      student_language_id uuid references students_language, student_id uuid references students,
      created_at timestamptz default now(), reading numeric, vocabulary numeric,
      grammar numeric, writing numeric, listening numeric, speaking numeric,
      homework numeric, effort numeric, comments text);
    create table absences (student_language_id uuid references students_language);
    create table curriculum (class_id uuid references classes,
      created_at timestamptz default now(), for_date date default current_date,
      in_class text, homework text);
    create table personal_homework (id uuid primary key default gen_random_uuid(),
      student_id uuid references students, class_id uuid references classes,
      created_at timestamptz default now(), for_date date, homework text,
      removed_at timestamptz);
    insert into users values ('${parent}', 'Test', 'Parent', 'parent'),
      ('${teacher}', 'Test', 'Teacher', 'teacher');
    insert into students values ('${student}', '${parent}', 'Test Student');
    insert into user_access values ('${parent}', '${parent}'), ('${teacher}', '${teacher}');
    insert into classes values
      ('${group}', 'Group', 'english', 'Monday 17:00-19:00', '${teacher}'),
      ('${privateClass}', 'Private', 'english', 'Friday 17:00-18:00', '${teacher}');
    insert into students_language (id, student_id, class_id, language)
      values ('${enrollment}', '${student}', '${group}', 'english');
    insert into students_grades (student_language_id, student_id, reading)
      values ('${enrollment}', '${student}', 80);
    insert into absences values ('${enrollment}');
    insert into curriculum (class_id, homework) values
      ('${group}', 'Group homework'), ('${privateClass}', 'Private homework');
    select set_config('test.auth_uid', '${parent}', false);
  `);
  for (const file of [
    '202608260001_show_student_menu_without_grades.sql',
    '202605230001_get_student_grade_rows.sql',
    '202605290003_order_student_curriculum_by_created_at.sql',
    '202605290004_get_student_upcoming_curriculum_rows.sql',
  ]) await db.exec(await read(`migrations/${file}`));
  const teacherSql = await read('migrations/202605290001_teacher_menu_functions.sql');
  await db.exec(teacherSql.slice(
    teacherSql.indexOf('create or replace function public.get_teacher_class_students('),
    teacherSql.indexOf('create or replace function public.get_teacher_student_grade_averages(')));
  return db;
}

const menu = async (db) => (await db.query(
  'select * from get_student_language_averages($1)', [student])).rows;
async function enroll(db, classId, schedule = null) {
  await db.exec(template
    .replace('target_student_id uuid := null', `target_student_id uuid := '${student}'`)
    .replace('target_class_id uuid := null', `target_class_id uuid := '${classId}'`)
    .replace('attendance_schedule text := null',
      `attendance_schedule text := ${schedule === null ? 'null' : `'${schedule.replaceAll("'", "''")}'`}`));
}

for (const indexOnly of [false, true]) {
  test(`multiple classes preserve the released API (${indexOnly ? 'index' : 'constraint'})`, async () => {
    const db = await fixture(indexOnly);
    try {
      const before = await menu(db);
      await db.exec(migration);
      assert.deepEqual(await menu(db), before, 'existing student results unchanged');
      await db.exec(migration); // Safe to re-run.
      await enroll(db, privateClass);
      let rows = await menu(db);
      assert.equal(rows.length, 2, 'same language may have two classes');
      assert.deepEqual(rows[0], before[0], 'original grades and schedule unchanged');
      assert.deepEqual(Object.keys(rows[1]), Object.keys(before[0]), 'same RPC fields');
      assert.equal(rows[1].reading, null, 'ungraded enrollment is visible');
      assert.equal(rows[1].days_hours, 'Friday 17:00-18:00');
      await enroll(db, group, '  Monday 17:00-18:00  ');
      rows = await menu(db);
      assert.equal(rows.length, 2, 'repeat import is idempotent');
      assert.equal(rows[0].days_hours, 'Monday 17:00-18:00');
      assert.equal(rows[0].reading, before[0].reading);
      assert.equal((await db.query('select id from students_language where class_id = $1', [group])).rows[0].id, enrollment);
      assert.equal((await db.query('select count(*)::int as n from absences')).rows[0].n, 1);
      await enroll(db, group, '   ');
      assert.equal((await menu(db))[0].days_hours, before[0].days_hours, 'blank falls back');
      await db.exec(`insert into students_grades (student_language_id, student_id, reading)
        select id, student_id, 40 from students_language where class_id = '${privateClass}'`);
      for (const [classId, score, homework] of [
        [group, 80, 'Group homework'], [privateClass, 40, 'Private homework'],
      ]) {
        const grades = (await db.query('select * from get_student_grade_rows($1, $2)', [student, classId])).rows;
        assert.equal(grades.length, 1);
        assert.equal(Number(grades[0].reading), score, 'grades isolated by class');
        for (const rpc of ['get_student_curriculum_rows', 'get_student_upcoming_curriculum_rows']) {
          const work = (await db.query(`select * from ${rpc}($1, $2)`, [student, classId])).rows;
          assert.equal(work.length, 1);
          assert.equal(work[0].homework, homework, 'homework isolated by class');
        }
      }
      await assert.rejects(db.query(`insert into students_language (student_id, class_id)
        values ($1, $2)`, [student, group]), /duplicate key/);
      await db.query("select set_config('test.auth_uid', $1, false)", [stranger]);
      assert.deepEqual(await menu(db), [], 'unrelated parent cannot read student');
      for (const rpc of ['get_student_grade_rows', 'get_student_curriculum_rows']) {
        assert.deepEqual((await db.query(`select * from ${rpc}($1, $2)`, [student, group])).rows, []);
      }
      assert.deepEqual((await db.query('select * from get_teacher_class_students($1)', [group])).rows, []);
      await db.query("select set_config('test.auth_uid', $1, false)", [teacher]);
      for (const classId of [group, privateClass]) {
        const roster = (await db.query('select * from get_teacher_class_students($1)', [classId])).rows;
        assert.equal(roster.length, 1);
        assert.equal(roster[0].student_id, student);
      }
    } finally {
      await db.close();
    }
  });
}

test('unexpected dependent foreign key aborts without removing data', async () => {
  const db = await fixture();
  try {
    await db.exec('create table legacy_dependency (student_id uuid references students_language(student_id))');
    await assert.rejects(db.exec(migration), /depend/);
    await db.exec('rollback');
    assert.equal((await menu(db)).length, 1);
    await assert.rejects(db.query(`insert into students_language (student_id, class_id)
      values ($1, $2)`, [student, privateClass]), /duplicate key/);
  } finally {
    await db.close();
  }
});

test('one language summary combines actual marks and paginates all enrolled classes', async () => {
  const db = await fixture();
  const french = id(8), unjoined = id(9), ungraded = id(10), otherStudent = id(11);
  try {
    await db.exec(migration);
    await enroll(db, privateClass, 'Friday 17:00-18:00');
    const oldMenu = await menu(db);
    await db.exec(overviewMigration);
    await db.exec(overviewMigration);
    assert.deepEqual(await menu(db), oldMenu, 'legacy RPC stays class-based');
    await db.exec(`
      insert into classes values
        ('${french}', 'French', 'french', null, '${teacher}'),
        ('${unjoined}', 'Other English', 'english', null, '${teacher}'),
        ('${ungraded}', 'No grades', ' ENGLISH ', null, '${teacher}');
      insert into students values ('${otherStudent}', '${parent}', 'Sibling');
      insert into students_language (student_id, class_id) values
        ('${student}', '${french}'), ('${student}', '${ungraded}'),
        ('${otherStudent}', '${group}');
      update students_grades set vocabulary = 20;
      insert into students_grades (student_language_id, student_id, reading, vocabulary)
        select id, student_id,
          case class_id when '${group}' then 100 when '${privateClass}' then 30 else 99 end,
          case class_id when '${privateClass}' then 100 else null end
        from students_language where class_id <> '${ungraded}';
      insert into curriculum (class_id, homework) values
        ('${french}', 'French homework'), ('${unjoined}', 'Not enrolled');
      insert into personal_homework (student_id, class_id, for_date, homework, removed_at) values
        ('${student}', '${group}', current_date - 2, 'Still active overdue work', null),
        ('${student}', '${privateClass}', current_date + 2, 'Private personal work', null),
        ('${student}', '${privateClass}', current_date, 'Removed work', now()),
        ('${student}', '${french}', current_date, 'French personal work', null),
        ('${otherStudent}', '${group}', current_date, 'Sibling private work', null);
    `);
    const summaries = (await db.query('select * from get_student_language_summaries($1)', [student])).rows;
    assert.equal(summaries.length, 2, 'one card per language, not per class');
    const english = summaries.find(row => row.language === 'english');
    assert.equal(english.classes.length, 3, 'includes ungraded enrollment');
    assert.equal(Number(english.reading), 70, 'uses every grade, not mean of class means');
    assert.equal(Number(english.vocabulary), 60, 'null marks excluded');
    assert.equal(Number(english.overall), 66, 'overall uses actual non-null marks');
    assert.equal(summaries.find(row => row.language === 'french').reading, '99.00');

    const grades = (await db.query('select * from get_student_language_grade_rows($1, $2)', [student, 'English'])).rows;
    assert.equal(grades.length, 3, 'excludes other language and sibling grades');
    const upcoming = (await db.query('select * from get_student_language_upcoming_curriculum_rows($1, $2)', [student, 'english'])).rows;
    assert.deepEqual(upcoming.map(row => row.homework).sort(), ['Group homework', 'Private homework']);
    const personal = (await db.query('select * from get_student_language_personal_homework_rows($1, $2)', [student, 'english'])).rows;
    assert.deepEqual(personal.map(row => row.homework), ['Still active overdue work', 'Private personal work']);

    // More than a page, interleaved across classes, with equal timestamps to
    // exercise stable combined pagination rather than per-class offsets.
    await db.exec(`
      insert into students_grades (student_language_id, student_id, reading, comments, created_at)
        select sl.id, sl.student_id, n, 'Grade ' || n, '2030-01-01'::timestamptz
        from generate_series(1, 24) n join students_language sl
          on sl.student_id = '${student}'
          and sl.class_id = case when n % 2 = 0 then '${group}'::uuid else '${privateClass}'::uuid end;
      insert into curriculum (class_id, homework, created_at)
        select case when n % 2 = 0 then '${group}'::uuid else '${privateClass}'::uuid end,
          'Homework ' || n, '2030-01-01'::timestamptz from generate_series(1, 24) n;
    `);
    for (const rpc of ['get_student_language_grade_rows', 'get_student_language_curriculum_rows']) {
      const full = (await db.query(`select * from ${rpc}($1, $2, 50, 0)`, [student, 'english'])).rows;
      const pages = [];
      for (let offset = 0; offset < full.length; offset += 10) {
        pages.push(...(await db.query(`select * from ${rpc}($1, $2, 10, $3)`, [student, 'english', offset])).rows);
      }
      assert.deepEqual(pages, full, `${rpc} has no missing or duplicated rows across pages`);
      assert.ok(full.some(row => row.class_name === 'Group'));
      assert.ok(full.some(row => row.class_name === 'Private'));
    }
    await db.query("select set_config('test.auth_uid', $1, false)", [stranger]);
    assert.deepEqual((await db.query('select * from get_student_language_summaries($1)', [student])).rows, []);
    for (const rpc of ['get_student_language_grade_rows', 'get_student_language_curriculum_rows',
      'get_student_language_upcoming_curriculum_rows', 'get_student_language_personal_homework_rows']) {
      assert.deepEqual((await db.query(`select * from ${rpc}($1, $2)`, [student, 'english'])).rows, [], rpc);
    }
  } finally {
    await db.close();
  }
});
