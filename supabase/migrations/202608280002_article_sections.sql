alter table public.articles
add column if not exists article_id uuid default gen_random_uuid();

update public.articles
set article_id = gen_random_uuid()
where article_id is null;

alter table public.articles
alter column article_id set default gen_random_uuid(),
alter column article_id set not null;

create unique index if not exists articles_article_id_key
on public.articles(article_id);

create table if not exists public.article_sections (
  id uuid primary key default gen_random_uuid(),
  article_id uuid not null references public.articles(article_id) on delete cascade,
  title text not null,
  body text,
  image_url text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint article_sections_title_not_blank check (trim(title) <> '')
);

create index if not exists article_sections_article_order_idx
on public.article_sections(article_id, sort_order, created_at);

insert into public.article_sections (article_id, title, body, sort_order)
select article.article_id, 'Το άρθρο', article.text, 1
from public.articles article
where trim(coalesce(article.text, '')) <> ''
  and not exists (
    select 1
    from public.article_sections section
    where section.article_id = article.article_id
  );

alter table public.article_sections enable row level security;

drop policy if exists "Authenticated users can read article sections"
on public.article_sections;

create policy "Authenticated users can read article sections"
on public.article_sections
for select
to authenticated
using (true);

grant select on table public.article_sections to authenticated;

insert into storage.buckets (id, name, public)
values ('article-images', 'article-images', true)
on conflict (id) do update set public = excluded.public;
