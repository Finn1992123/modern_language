-- New parent rows must not create empty student or payment placeholders.
-- Students and payments are inserted explicitly with their actual details.

begin;

drop trigger if exists create_student_after_user_insert
on public.users;

drop trigger if exists create_payment_after_user_insert
on public.users;

-- The trigger functions are intentionally retained: removing the triggers is
-- sufficient, and avoids breaking them if another table still depends on them.

commit;
