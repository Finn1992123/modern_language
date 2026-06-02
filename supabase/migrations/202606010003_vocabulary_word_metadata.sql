create table if not exists public.cefr_books (
  id integer primary key,
  name text not null,
  language text,
  level text,
  created_at timestamptz not null default now()
);

alter table public.cefr_books enable row level security;

drop policy if exists cefr_books_select_authenticated
on public.cefr_books;

create policy cefr_books_select_authenticated
on public.cefr_books
for select
to authenticated
using (true);

alter table public.classes
add column if not exists cefr_book_id integer references public.cefr_books(id);

create table if not exists public.vocabulary_words (
  id uuid primary key default gen_random_uuid(),
  cefr_book_id integer not null references public.cefr_books(id),
  book_name text,
  language text,
  level text,
  unit text,
  unit_order integer,
  word text not null,
  translation_gr text,
  accepted_words text,
  part_of_speech text,
  example_sentence text,
  is_active boolean not null default true,
  is_important boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.vocabulary_words enable row level security;

drop policy if exists vocabulary_words_select_authenticated
on public.vocabulary_words;

create policy vocabulary_words_select_authenticated
on public.vocabulary_words
for select
to authenticated
using (true);

alter table public.vocabulary_words
add column if not exists cefr_book_id integer references public.cefr_books(id),
add column if not exists book_name text,
add column if not exists unit_order integer,
add column if not exists translation_gr text,
add column if not exists accepted_words text,
add column if not exists part_of_speech text,
add column if not exists example_sentence text,
add column if not exists is_active boolean not null default true,
add column if not exists is_important boolean not null default false;

create index if not exists classes_cefr_book_id_idx
on public.classes(cefr_book_id);

create index if not exists vocabulary_words_cefr_book_id_idx
on public.vocabulary_words(cefr_book_id);

create index if not exists vocabulary_words_cefr_book_unit_idx
on public.vocabulary_words(cefr_book_id, unit);

create index if not exists vocabulary_words_active_cefr_book_unit_idx
on public.vocabulary_words(cefr_book_id, is_active, unit_order, unit);

create index if not exists vocabulary_words_important_idx
on public.vocabulary_words(cefr_book_id, is_important)
where is_important = true;
