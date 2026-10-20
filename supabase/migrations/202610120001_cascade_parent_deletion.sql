-- Deleting public.users removes the family's owned records atomically.
-- Shared classes, curriculum, assignments and auth identities are not owned by
-- the family: never follow references from an owned row to those tables.
begin;

do $migration$
declare
  relation record;
  foreign_key record;
  definition text;
  column_number smallint;
begin
  -- The base schema predates the migrations in this repository. Ensure the
  -- essential ownership links exist, even if that schema omitted a FK.
  for relation in
    select * from (values
      ('students', 'user_id', 'users'),
      ('payments', 'user_id', 'users'),
      ('students_language', 'student_id', 'students')
    ) as links(table_name, column_name, parent_table)
  loop
    select attnum into strict column_number from pg_attribute
    where attrelid = format('public.%I', relation.table_name)::regclass
      and attname = relation.column_name and not attisdropped;

    if not exists (
      select 1 from pg_constraint
      where contype = 'f'
        and conrelid = format('public.%I', relation.table_name)::regclass
        and confrelid = format('public.%I', relation.parent_table)::regclass
        and conkey = array[column_number]
    ) then
      execute format(
        'alter table public.%I add foreign key (%I) references public.%I(id) on delete cascade',
        relation.table_name, relation.column_name, relation.parent_table);
    end if;
  end loop;

  -- Discover actual constraint names, including the legacy grades, absences
  -- and achievement tables. Descendants include attempt items/live answers.
  -- Only the explicit user_id ownership links may start at public.users;
  -- teacher/creator references must retain their existing deletion behavior.
  for foreign_key in
    with recursive owned_tables(oid) as (
      select 'public.students'::regclass::oid
      union
      select c.conrelid from pg_constraint c
      join owned_tables owned on owned.oid = c.confrelid
      join pg_class t on t.oid = c.conrelid
      join pg_namespace n on n.oid = t.relnamespace
      where c.contype = 'f' and n.nspname = 'public'
    )
    select c.oid, c.conrelid::regclass as table_name, c.conname,
           pg_get_constraintdef(c.oid) as definition
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where c.contype = 'f' and n.nspname = 'public'
      and c.confdeltype <> 'c'
      and (
        c.confrelid in (select oid from owned_tables)
        or (
          c.confrelid = 'public.users'::regclass
          and t.relname in ('students', 'payments', 'user_access',
            'user_auth_connections', 'account_deletion_requests')
          and c.conkey = array[(select attnum from pg_attribute
            where attrelid = c.conrelid and attname = 'user_id'
              and not attisdropped)]
        )
      )
  loop
    -- Preserve ON UPDATE, match mode, deferrability and validation status.
    definition := regexp_replace(foreign_key.definition,
      ' ON DELETE (NO ACTION|RESTRICT|CASCADE|SET NULL|SET DEFAULT)( \([^)]*\))?', '');
    definition := regexp_replace(definition,
      '( REFERENCES [^(]+\([^)]*\))', '\1 ON DELETE CASCADE');
    execute format('alter table %s drop constraint %I, add constraint %I %s',
      foreign_key.table_name, foreign_key.conname, foreign_key.conname, definition);
  end loop;
end;
$migration$;

commit;
