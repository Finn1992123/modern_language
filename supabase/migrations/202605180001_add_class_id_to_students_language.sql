alter table public.students_language
add column if not exists class_id uuid;

alter table public.students_language
drop constraint if exists students_language_class_id_fkey;

alter table public.students_language
add constraint students_language_class_id_fkey
foreign key (class_id)
references public.classes(id)
on update cascade
on delete set null;

create index if not exists students_language_class_id_idx
on public.students_language(class_id);
