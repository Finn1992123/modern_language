// node --test scripts/parent-deletion.test.mjs
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { PGlite } from '@electric-sql/pglite';

const migration = await readFile(new URL(
  '../supabase/migrations/202610120001_cascade_parent_deletion.sql', import.meta.url), 'utf8');

for (const missingLinks of [false, true]) {
  test(`parent deletion removes only owned records (missing base FKs: ${missingLinks})`, async () => {
    const db = new PGlite();
    try {
      await db.exec(`
        create table users (id int primary key);
        create table students (id int primary key, user_id int ${missingLinks ? '' : 'references users on delete restrict'});
        create table payments (user_id int ${missingLinks ? '' : 'references users on delete set null'});
        create table classes (id int primary key, teacher_id int references users on delete restrict);
        create table curriculum (class_id int references classes);
        create table students_language (id int primary key, student_id int
          ${missingLinks ? '' : 'references students on update cascade deferrable initially deferred'},
          class_id int references classes);
        create table students_grades (student_id int references students,
          student_language_id int references students_language);
        create table absences (student_language_id int references students_language);
        create table "juniorAchievements" (student_id int references students on delete cascade);
        create table achievements (student_id int references students on delete set null);
        create table personal_homework (student_id int references students, class_id int references classes);
        create table exercise_assignment_attempts (id int primary key, student_id int references students);
        create table exercise_assignment_attempt_items (attempt_id int references exercise_assignment_attempts);
        create table live_activity_participants (id int primary key, student_id int references students);
        create table live_activity_answers (participant_id int references live_activity_participants);
        create table user_access (user_id int references users);
        create table user_auth_connections (user_id int references users);
        create table account_deletion_requests (user_id int references users on delete set null);
        insert into users values (1), (2), (3);
        insert into students values (10, 1), (11, 1), (20, 2);
        insert into payments values (1), (2);
        insert into classes values (100, 3);
        insert into curriculum values (100);
        insert into students_language values (10, 10, 100), (11, 11, 100), (20, 20, 100);
        insert into students_grades select id, id from students;
        insert into absences select id from students;
        insert into "juniorAchievements" select id from students;
        insert into achievements select id from students;
        insert into personal_homework select id, 100 from students;
        insert into exercise_assignment_attempts select id, id from students;
        insert into exercise_assignment_attempt_items select id from students;
        insert into live_activity_participants select id, id from students;
        insert into live_activity_answers select id from students;
        insert into user_access values (1), (2);
        insert into user_auth_connections values (1), (2);
        insert into account_deletion_requests values (1), (2);
      `);
      await db.exec(migration);
      await db.exec(migration);
      assert.equal((await db.query('select count(*)::int as n from students')).rows[0].n, 3);
      if (!missingLinks) {
        const [fk] = (await db.query(`select confupdtype, condeferrable, condeferred
          from pg_constraint where conrelid = 'students_language'::regclass
          and confrelid = 'students'::regclass`)).rows;
        assert.deepEqual(fk, { confupdtype: 'c', condeferrable: true, condeferred: true });
      }
      await db.exec('begin; delete from users where id = 1; rollback;');
      assert.equal((await db.query('select count(*)::int as n from students')).rows[0].n, 3);
      await db.exec('delete from users where id = 1');
      for (const table of ['students', 'payments', 'students_language', 'students_grades',
        'absences', 'juniorAchievements', 'achievements', 'personal_homework',
        'exercise_assignment_attempts', 'exercise_assignment_attempt_items',
        'live_activity_participants', 'live_activity_answers', 'user_access',
        'user_auth_connections', 'account_deletion_requests', 'classes', 'curriculum']) {
        assert.equal((await db.query(`select count(*)::int as n from "${table}"`)).rows[0].n, 1, table);
      }
      assert.deepEqual((await db.query('select * from students')).rows, [{ id: 20, user_id: 2 }]);
      await assert.rejects(db.exec('delete from users where id = 3'), /foreign key constraint/);
    } finally {
      await db.close();
    }
  });
}
