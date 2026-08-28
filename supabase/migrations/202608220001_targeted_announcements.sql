alter table public.announcements
add column if not exists notification_id uuid default gen_random_uuid();

update public.announcements
set notification_id = gen_random_uuid()
where notification_id is null;

alter table public.announcements
alter column notification_id set default gen_random_uuid(),
alter column notification_id set not null;

create unique index if not exists announcements_notification_id_key
on public.announcements(notification_id);

alter table public.announcements
add column if not exists audience_type text not null default 'all';

alter table public.announcements
drop constraint if exists announcements_audience_type_check;

alter table public.announcements
add constraint announcements_audience_type_check
check (audience_type in ('all', 'class'));

alter table public.announcements
add column if not exists class_id uuid references public.classes(id) on delete cascade;

alter table public.announcements
add column if not exists created_by_auth_user_id uuid references auth.users(id) on delete set null;

alter table public.announcements
add column if not exists push_sent_at timestamptz;

alter table public.announcements
drop constraint if exists announcements_audience_target_check;

alter table public.announcements
add constraint announcements_audience_target_check
check (
  (audience_type = 'all' and class_id is null)
  or (audience_type = 'class' and class_id is not null)
);

create index if not exists announcements_class_created_idx
on public.announcements(class_id, created_at desc);

create or replace function public.get_announcement_target_classes()
returns table (
  id uuid,
  name text,
  language text,
  days_hours text
)
language sql
security definer
set search_path = public
as $$
  with current_headteacher as (
    select u.id
    from public.users u
    join public.user_access ua on ua.user_id = u.id
    where ua.auth_user_id = auth.uid()
      and lower(coalesce(u.role, '')) = 'headteacher'
  )
  select c.id, c.name, c.language, c.days_hours
  from public.classes c
  where exists (select 1 from current_headteacher)
  order by c.name, c.language, c.days_hours;
$$;

create or replace function public.create_announcement(
  input_header text,
  input_text text,
  input_audience_type text,
  input_class_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  staff_id uuid;
  new_notification_id uuid;
  normalized_header text := trim(coalesce(input_header, ''));
  normalized_text text := trim(coalesce(input_text, ''));
  normalized_audience text := lower(trim(coalesce(input_audience_type, '')));
begin
  select u.id
  into staff_id
  from public.users u
  join public.user_access ua on ua.user_id = u.id
  where ua.auth_user_id = auth.uid()
    and lower(coalesce(u.role, '')) = 'headteacher'
  order by ua.created_at
  limit 1;

  if staff_id is null then
    raise exception 'Only a headteacher can create announcements';
  end if;

  if normalized_header = '' or char_length(normalized_header) > 120 then
    raise exception 'Announcement title must contain 1 to 120 characters';
  end if;

  if normalized_text = '' or char_length(normalized_text) > 4000 then
    raise exception 'Announcement text must contain 1 to 4000 characters';
  end if;

  if normalized_audience = 'all' then
    input_class_id := null;
  elsif normalized_audience = 'class' then
    if input_class_id is null then
      raise exception 'A class is required';
    end if;

    if not exists (
      select 1
      from public.classes c
      where c.id = input_class_id
    ) then
      raise exception 'You cannot send an announcement to this class';
    end if;
  else
    raise exception 'Invalid announcement audience';
  end if;

  insert into public.announcements (
    notification_id,
    header,
    text,
    audience_type,
    class_id,
    created_by_auth_user_id
  ) values (
    gen_random_uuid(),
    normalized_header,
    normalized_text,
    normalized_audience,
    input_class_id,
    auth.uid()
  )
  returning notification_id into new_notification_id;

  return new_notification_id;
end;
$$;

create or replace function public.get_visible_announcements(
  input_notification_id uuid default null
)
returns table (
  notification_id uuid,
  created_at timestamptz,
  header text,
  text text,
  audience_type text,
  class_id uuid,
  class_name text
)
language sql
security definer
set search_path = public
as $$
  select
    a.notification_id,
    a.created_at,
    a.header,
    a.text,
    a.audience_type,
    a.class_id,
    c.name as class_name
  from public.announcements a
  left join public.classes c on c.id = a.class_id
  where auth.uid() is not null
    and exists (
      select 1
      from public.user_access linked_access
      where linked_access.auth_user_id = auth.uid()
    )
    and (input_notification_id is null or a.notification_id = input_notification_id)
    and (
      a.audience_type = 'all'
      or exists (
        select 1
        from public.user_access ua
        join public.users u on u.id = ua.user_id
        where ua.auth_user_id = auth.uid()
          and (
            lower(coalesce(u.role, '')) = 'headteacher'
            or (
              lower(coalesce(u.role, '')) = 'teacher'
              and exists (
                select 1
                from public.classes teacher_class
                where teacher_class.id = a.class_id
                  and teacher_class.teacher_in_charge = u.id
              )
            )
            or exists (
              select 1
              from public.students student
              join public.students_language student_language
                on student_language.student_id = student.id
              where student.user_id = u.id
                and student_language.class_id = a.class_id
            )
          )
      )
    )
  order by a.created_at desc;
$$;

create table if not exists public.push_notification_devices (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  token text not null unique,
  platform text not null check (platform in ('android', 'ios')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists push_notification_devices_auth_user_idx
on public.push_notification_devices(auth_user_id);

alter table public.push_notification_devices enable row level security;

create or replace function public.register_push_notification_device(
  input_token text,
  input_platform text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_token text := trim(coalesce(input_token, ''));
  normalized_platform text := lower(trim(coalesce(input_platform, '')));
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not exists (
    select 1
    from public.user_access ua
    where ua.auth_user_id = auth.uid()
  ) then
    raise exception 'No linked user';
  end if;

  if normalized_token = '' then
    raise exception 'A device token is required';
  end if;

  if normalized_platform not in ('android', 'ios') then
    raise exception 'Invalid device platform';
  end if;

  insert into public.push_notification_devices (
    auth_user_id,
    token,
    platform
  ) values (
    auth.uid(),
    normalized_token,
    normalized_platform
  )
  on conflict (token) do update
  set auth_user_id = auth.uid(),
      platform = excluded.platform,
      updated_at = now();
end;
$$;

create or replace function public.unregister_push_notification_device(
  input_token text
)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.push_notification_devices
  where auth_user_id = auth.uid()
    and token = trim(coalesce(input_token, ''));
$$;

create or replace function public.get_announcement_recipient_tokens(
  input_notification_id uuid
)
returns table (token text)
language sql
security definer
set search_path = public
as $$
  select distinct device.token
  from public.announcements announcement
  join public.push_notification_devices device
    on announcement.notification_id = input_notification_id
  where announcement.audience_type = 'all'
     or exists (
       select 1
       from public.user_access ua
       join public.students student on student.user_id = ua.user_id
       join public.students_language student_language
         on student_language.student_id = student.id
       where ua.auth_user_id = device.auth_user_id
         and student_language.class_id = announcement.class_id
     );
$$;

revoke all on table public.announcements from anon, authenticated;
revoke all on table public.push_notification_devices from anon, authenticated;

revoke all on function public.get_announcement_target_classes() from public;
revoke all on function public.create_announcement(text, text, text, uuid) from public;
revoke all on function public.get_visible_announcements(uuid) from public;
revoke all on function public.register_push_notification_device(text, text) from public;
revoke all on function public.unregister_push_notification_device(text) from public;
revoke all on function public.get_announcement_recipient_tokens(uuid) from public;

grant execute on function public.get_announcement_target_classes() to authenticated;
grant execute on function public.create_announcement(text, text, text, uuid) to authenticated;
grant execute on function public.get_visible_announcements(uuid) to authenticated;
grant execute on function public.register_push_notification_device(text, text) to authenticated;
grant execute on function public.unregister_push_notification_device(text) to authenticated;
grant execute on function public.get_announcement_recipient_tokens(uuid) to service_role;
