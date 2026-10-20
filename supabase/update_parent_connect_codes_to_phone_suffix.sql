-- Sets every family account's connect code to the last 5 digits of its phone.
-- The update is atomic and aborts if a phone is invalid or a code is duplicated.

begin;

create temporary table parent_connect_code_updates (
  user_id uuid primary key,
  user_name text,
  email text,
  old_connect_code text,
  phone_digits text,
  new_connect_code text
) on commit drop;

insert into parent_connect_code_updates (
  user_id,
  user_name,
  email,
  old_connect_code,
  phone_digits,
  new_connect_code
)
select
  u.id,
  concat_ws(' ', u.name, u.surname),
  u.email,
  u.connect_code,
  regexp_replace(coalesce(u.phone_number::text, ''), '[^0-9]', '', 'g'),
  right(regexp_replace(coalesce(u.phone_number::text, ''), '[^0-9]', '', 'g'), 5)
from public.users u
where lower(trim(coalesce(u.role, ''))) in (
  'parent',
  'student',
  'mother',
  'father',
  'guardian'
);

do $validation$
declare
  invalid_phones text;
  duplicate_codes text;
  external_conflicts text;
begin
  select string_agg(
    format('%s (%s)', coalesce(user_name, 'χωρίς όνομα'), coalesce(email, user_id::text)),
    ', '
    order by user_name
  )
  into invalid_phones
  from parent_connect_code_updates
  where length(phone_digits) < 5;

  if invalid_phones is not null then
    raise exception 'Phone number has fewer than 5 digits: %', invalid_phones;
  end if;

  select string_agg(
    format('%s -> %s', duplicate.new_connect_code, duplicate.accounts),
    '; '
    order by duplicate.new_connect_code
  )
  into duplicate_codes
  from (
    select
      updates.new_connect_code,
      string_agg(
        format('%s (%s)', coalesce(updates.user_name, 'χωρίς όνομα'), coalesce(updates.email, updates.user_id::text)),
        ', '
        order by updates.user_name
      ) as accounts
    from parent_connect_code_updates updates
    group by updates.new_connect_code
    having count(*) > 1
  ) duplicate;

  if duplicate_codes is not null then
    raise exception 'Duplicate last-5-digit connect code(s): %', duplicate_codes;
  end if;

  select string_agg(
    format(
      '%s -> %s (%s)',
      updates.new_connect_code,
      coalesce(other.name, 'χωρίς όνομα'),
      coalesce(other.email, other.id::text)
    ),
    '; '
    order by updates.new_connect_code
  )
  into external_conflicts
  from parent_connect_code_updates updates
  join public.users other
    on upper(trim(other.connect_code)) = upper(trim(updates.new_connect_code))
   and other.id <> updates.user_id
  where not exists (
    select 1
    from parent_connect_code_updates target
    where target.user_id = other.id
  );

  if external_conflicts is not null then
    raise exception 'New connect code(s) already belong to another account: %', external_conflicts;
  end if;
end
$validation$;

-- Use unique temporary values first so code swaps cannot violate the unique index.
update public.users u
set connect_code = concat('__PHONE5_TMP__', replace(u.id::text, '-', ''))
from parent_connect_code_updates updates
where u.id = updates.user_id
  and upper(trim(coalesce(u.connect_code, ''))) <>
      upper(trim(updates.new_connect_code));

update public.users u
set connect_code = updates.new_connect_code
from parent_connect_code_updates updates
where u.id = updates.user_id;

commit;

-- Verification: every row should show matches_phone = true.
select
  concat_ws(' ', u.name, u.surname) as user_name,
  u.email,
  u.phone_number,
  u.connect_code,
  u.connect_code = right(
    regexp_replace(coalesce(u.phone_number::text, ''), '[^0-9]', '', 'g'),
    5
  ) as matches_phone
from public.users u
where lower(trim(coalesce(u.role, ''))) in (
  'parent',
  'student',
  'mother',
  'father',
  'guardian'
)
order by u.surname, u.name;
