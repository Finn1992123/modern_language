-- Reader game: passages, highlight-only questions and completions.

create table if not exists public.reader_passages (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  level_code text not null check (
    level_code in (
      'junior_a',
      'junior_b',
      'senior_a',
      'senior_b',
      'senior_c',
      'senior_d',
      'pre_lower',
      'lower',
      'advanced',
      'proficiency'
    )
  ),
  title text not null,
  body text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  check (slug ~ '^[a-z0-9_]+$'),
  check (length(trim(title)) > 0),
  check (length(trim(body)) > 0)
);

create index if not exists reader_passages_active_level_idx
on public.reader_passages(level_code, created_at)
where is_active = true;

create table if not exists public.reader_questions (
  id uuid primary key default gen_random_uuid(),
  passage_id uuid not null references public.reader_passages(id)
    on delete cascade,
  sort_order integer not null,
  question text not null,
  accepted_answers text[] not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (passage_id, sort_order),
  check (length(trim(question)) > 0),
  check (cardinality(accepted_answers) > 0)
);

create index if not exists reader_questions_active_passage_idx
on public.reader_questions(passage_id, sort_order)
where is_active = true;

alter table public.reader_passages enable row level security;
alter table public.reader_questions enable row level security;

drop policy if exists reader_passages_read_authenticated
on public.reader_passages;
create policy reader_passages_read_authenticated
on public.reader_passages for select to authenticated
using (is_active = true);

drop policy if exists reader_questions_read_authenticated
on public.reader_questions;
create policy reader_questions_read_authenticated
on public.reader_questions for select to authenticated
using (
  is_active = true
  and exists (
    select 1
    from public.reader_passages passage
    where passage.id = passage_id
      and passage.is_active = true
  )
);

create table if not exists public.reader_completions (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete cascade,
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  passage_id uuid not null references public.reader_passages(id)
    on delete cascade,
  level_code text not null,
  question_count integer not null check (question_count > 0),
  created_at timestamptz not null default now()
);

create index if not exists reader_completions_student_idx
on public.reader_completions(student_id, created_at desc);

alter table public.reader_completions enable row level security;

drop policy if exists reader_completions_read_own
on public.reader_completions;
create policy reader_completions_read_own
on public.reader_completions for select to authenticated
using (auth_user_id = auth.uid());

create or replace function public.submit_reader_completion(
  input_student_id uuid,
  input_class_id uuid,
  input_passage_id uuid,
  input_level_code text,
  input_question_count integer
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_completion_id uuid;
  actual_question_count integer;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if not exists (
    select 1
    from public.reader_passages passage
    where passage.id = input_passage_id
      and passage.level_code = input_level_code
      and passage.is_active = true
  ) then
    raise exception 'invalid passage or level';
  end if;

  select count(*)::integer
  into actual_question_count
  from public.reader_questions question
  where question.passage_id = input_passage_id
    and question.is_active = true;

  if input_question_count <> actual_question_count
     or actual_question_count = 0 then
    raise exception 'invalid question count';
  end if;

  if not exists (
    select 1
    from public.students student
    join public.students_language student_language
      on student_language.student_id = student.id
    join public.user_access access
      on access.user_id = student.user_id
    where student.id = input_student_id
      and student_language.class_id = input_class_id
      and access.auth_user_id = auth.uid()
  ) then
    raise exception 'student or class access denied';
  end if;

  insert into public.reader_completions (
    student_id,
    class_id,
    auth_user_id,
    passage_id,
    level_code,
    question_count
  )
  values (
    input_student_id,
    input_class_id,
    auth.uid(),
    input_passage_id,
    input_level_code,
    input_question_count
  )
  returning id into new_completion_id;

  return new_completion_id;
end;
$$;

revoke all on function public.submit_reader_completion(
  uuid, uuid, uuid, text, integer
) from public;
grant execute on function public.submit_reader_completion(
  uuid, uuid, uuid, text, integer
) to authenticated;

-- Starter content: one passage and multiple questions for every level.
-- Add more active passages with the same level_code to make "Άλλο κείμενο"
-- select a different random text.
insert into public.reader_passages (slug, level_code, title, body)
values
(
  'junior_a_lucys_cat',
  'junior_a',
  'Lucy''s Cat',
  'Lucy has a small white cat. Its name is Snowy. Every morning, Snowy drinks milk in the kitchen. In the afternoon, it sleeps on Lucy''s blue chair. Lucy loves playing with Snowy after school.'
),
(
  'junior_b_school_garden',
  'junior_b',
  'The School Garden',
  'Our school has a beautiful garden behind the library. The students visit it every Friday. They water the flowers and pick up dry leaves. Mr Green teaches them how plants grow. The children like the garden because they can learn outdoors.'
),
(
  'senior_a_weekend_trip',
  'senior_a',
  'A Weekend Trip',
  'Last Saturday, Alex and his family travelled to a village near the mountains. They stayed in a small hotel beside a river. In the morning, they followed a forest path and took photographs of wild birds. Alex enjoyed the walk most because he had never seen an eagle before.'
),
(
  'senior_b_library_project',
  'senior_b',
  'The Library Project',
  'Maya''s class wanted to improve the school library, so they organised a book fair. Families donated novels, comics and dictionaries. The students sold homemade cakes to raise money for new shelves. By the end of the day, they had collected enough money to buy three large bookcases.'
),
(
  'senior_c_city_bicycles',
  'senior_c',
  'Bicycles in the City',
  'Many residents complained about traffic and air pollution in Brookfield. In response, the town council created protected bicycle lanes across the city centre. Six months later, more people were cycling to work and local shops reported more customers. The council now plans to connect the lanes to nearby schools.'
),
(
  'senior_d_coral_team',
  'senior_d',
  'The Coral Team',
  'A group of teenage divers has started restoring a damaged coral reef near their island. Under the supervision of marine scientists, they attach small healthy coral fragments to special underwater frames. The work requires patience because the fragments grow slowly. The team also visits schools to explain why reducing plastic waste protects marine life.'
),
(
  'pre_lower_sleep',
  'pre_lower',
  'Why Sleep Matters',
  'Researchers have found that sleep plays an essential role in learning. While we sleep, the brain organises information gathered during the day and strengthens important memories. Teenagers often sleep less than they need because of homework, social activities and late-night screen use. Experts recommend establishing a regular bedtime and keeping digital devices outside the bedroom.'
),
(
  'lower_rooftop_farms',
  'lower',
  'Farming Above the Streets',
  'Rooftop farms are becoming increasingly common in crowded cities where unused land is scarce. These gardens can reduce the distance food travels before reaching consumers and help cool buildings during hot weather. However, creating one requires careful planning because roofs must support the weight of soil and water. Despite the challenges, many communities value rooftop farms as shared green spaces.'
),
(
  'advanced_citizen_science',
  'advanced',
  'Science Beyond the Laboratory',
  'Citizen-science projects invite members of the public to contribute to professional research. Volunteers might classify images of distant galaxies, record local bird populations or measure air quality. Although individual observations may occasionally contain errors, the enormous volume of collected data can reveal patterns that small research teams would otherwise miss. Participants also gain a clearer understanding of how scientific evidence is produced.'
),
(
  'proficiency_languages',
  'proficiency',
  'Languages and Perception',
  'The claim that language determines thought has largely been replaced by a more nuanced view: linguistic categories can guide attention without imprisoning the mind. Speakers of languages that use absolute directions, for instance, may develop an unusually precise awareness of orientation. Such findings do not prove that other speakers are incapable of the same skill. Rather, they suggest that repeatedly encoding particular distinctions makes certain habits of perception more readily accessible.'
),
(
  'junior_a_bens_dog',
  'junior_a',
  'Ben''s Dog',
  'Ben has a friendly brown dog called Max. Max likes running in the garden. He carries a red ball in his mouth. After lunch, Ben and Max walk to the park. At night, Max sleeps next to Ben''s bed.'
),
(
  'junior_b_rainy_picnic',
  'junior_b',
  'The Rainy Picnic',
  'Nina and her friends planned a picnic in the park on Sunday. In the morning, dark clouds filled the sky and it began to rain. They moved the picnic to Nina''s living room. They ate sandwiches, played games and had a wonderful afternoon.'
),
(
  'senior_a_lost_wallet',
  'senior_a',
  'The Lost Wallet',
  'On his way home, Daniel found a wallet near the bus stop. There was some money and a library card inside it. He took the wallet to the library, where a librarian contacted its owner. The owner thanked Daniel and gave him a book as a reward.'
),
(
  'senior_b_recycling_day',
  'senior_b',
  'Recycling Day',
  'The students at West Hill School collected old paper, glass bottles and metal cans for a month. On Recycling Day, volunteers weighed everything in the playground. Class 2B collected the largest amount, so they won a trip to the science museum. The project kept more than five hundred kilograms of waste out of landfill.'
),
(
  'senior_c_community_theatre',
  'senior_c',
  'The Community Theatre',
  'When the town''s old theatre was threatened with closure, local residents formed a volunteer group to save it. They repaired the seats, painted the entrance and invited young musicians to perform. Ticket sales gradually increased, allowing the theatre to remain open without financial support from the council.'
),
(
  'senior_d_rooftop_bees',
  'senior_d',
  'Bees Above the City',
  'Several hotels have installed beehives on their rooftops to support declining bee populations. The insects find food in parks, gardens and window boxes throughout the city. Trained beekeepers inspect the hives regularly and collect a small quantity of honey. Guests can taste this honey at breakfast, but conservation remains the main purpose of the project.'
),
(
  'pre_lower_music_memory',
  'pre_lower',
  'Music and Memory',
  'Learning to play an instrument may strengthen several mental skills. Musicians must read symbols, control precise movements and listen carefully at the same time. Studies suggest that regular practice can improve attention and memory, although progress depends more on consistent effort than natural talent. Even short daily sessions can be valuable.'
),
(
  'lower_repair_cafes',
  'lower',
  'Repair Cafés',
  'At repair cafés, people bring broken household objects and work with volunteers to fix them. The events reduce waste by extending the life of items that might otherwise be thrown away. Visitors also learn practical skills and meet people from their neighbourhood. Not every object can be repaired, but the advice is always free.'
),
(
  'advanced_urban_trees',
  'advanced',
  'The Hidden Value of Urban Trees',
  'Urban trees provide benefits that extend far beyond their appearance. Their leaves filter certain pollutants, while their shade lowers surface temperatures and reduces the demand for air conditioning. Yet trees planted in cities face compacted soil, limited water and damage from construction. Long-term planting programmes therefore require careful species selection and sustained maintenance rather than occasional campaigns.'
),
(
  'proficiency_useful_uncertainty',
  'proficiency',
  'The Value of Uncertainty',
  'Public debate often treats uncertainty as evidence that experts know very little. In research, however, acknowledging uncertainty is a sign of precision rather than weakness. Scientists estimate the limits of their conclusions so that later decisions can reflect both the strength of the evidence and the consequences of being wrong. Concealing those limits may create temporary confidence, but it ultimately undermines informed judgement.'
)
on conflict (slug) do update set
  level_code = excluded.level_code,
  title = excluded.title,
  body = excluded.body,
  is_active = true;

insert into public.reader_questions (
  passage_id,
  sort_order,
  question,
  accepted_answers
)
values
(
  (select id from public.reader_passages where slug = 'junior_a_lucys_cat'),
  1,
  'What colour is Lucy''s cat?',
  array['a small white cat', 'white']
),
(
  (select id from public.reader_passages where slug = 'junior_a_lucys_cat'),
  2,
  'Where does Snowy sleep?',
  array['on Lucy''s blue chair', 'Lucy''s blue chair']
),
(
  (select id from public.reader_passages where slug = 'junior_b_school_garden'),
  1,
  'Where is the school garden?',
  array['behind the library']
),
(
  (select id from public.reader_passages where slug = 'junior_b_school_garden'),
  2,
  'When do the students visit the garden?',
  array['every Friday']
),
(
  (select id from public.reader_passages where slug = 'senior_a_weekend_trip'),
  1,
  'Where did the family stay?',
  array['in a small hotel beside a river', 'a small hotel beside a river']
),
(
  (select id from public.reader_passages where slug = 'senior_a_weekend_trip'),
  2,
  'Why did Alex enjoy the walk most?',
  array['because he had never seen an eagle before', 'he had never seen an eagle before']
),
(
  (select id from public.reader_passages where slug = 'senior_b_library_project'),
  1,
  'Why did the students sell homemade cakes?',
  array['to raise money for new shelves']
),
(
  (select id from public.reader_passages where slug = 'senior_b_library_project'),
  2,
  'What could they buy with the money?',
  array['three large bookcases']
),
(
  (select id from public.reader_passages where slug = 'senior_c_city_bicycles'),
  1,
  'Why did the council create bicycle lanes?',
  array['traffic and air pollution', 'residents complained about traffic and air pollution']
),
(
  (select id from public.reader_passages where slug = 'senior_c_city_bicycles'),
  2,
  'Where does the council plan to extend the lanes?',
  array['to nearby schools', 'nearby schools']
),
(
  (select id from public.reader_passages where slug = 'senior_d_coral_team'),
  1,
  'Who supervises the teenage divers?',
  array['marine scientists']
),
(
  (select id from public.reader_passages where slug = 'senior_d_coral_team'),
  2,
  'Why does the restoration require patience?',
  array['because the fragments grow slowly', 'the fragments grow slowly']
),
(
  (select id from public.reader_passages where slug = 'pre_lower_sleep'),
  1,
  'What does the brain do while we sleep?',
  array['organises information gathered during the day and strengthens important memories']
),
(
  (select id from public.reader_passages where slug = 'pre_lower_sleep'),
  2,
  'Where should teenagers keep digital devices at night?',
  array['outside the bedroom']
),
(
  (select id from public.reader_passages where slug = 'lower_rooftop_farms'),
  1,
  'How can rooftop gardens help buildings in hot weather?',
  array['help cool buildings during hot weather', 'cool buildings']
),
(
  (select id from public.reader_passages where slug = 'lower_rooftop_farms'),
  2,
  'Why must rooftop farms be planned carefully?',
  array['because roofs must support the weight of soil and water', 'roofs must support the weight of soil and water']
),
(
  (select id from public.reader_passages where slug = 'advanced_citizen_science'),
  1,
  'What can the large volume of data reveal?',
  array['patterns that small research teams would otherwise miss']
),
(
  (select id from public.reader_passages where slug = 'advanced_citizen_science'),
  2,
  'What do participants understand more clearly?',
  array['how scientific evidence is produced']
),
(
  (select id from public.reader_passages where slug = 'proficiency_languages'),
  1,
  'What has replaced the claim that language determines thought?',
  array['a more nuanced view', 'a more nuanced view: linguistic categories can guide attention without imprisoning the mind']
),
(
  (select id from public.reader_passages where slug = 'proficiency_languages'),
  2,
  'What may make habits of perception more accessible?',
  array['repeatedly encoding particular distinctions']
),
(
  (select id from public.reader_passages where slug = 'junior_a_bens_dog'),
  1,
  'What colour is Max?',
  array['brown', 'a friendly brown dog']
),
(
  (select id from public.reader_passages where slug = 'junior_a_bens_dog'),
  2,
  'Where does Max sleep?',
  array['next to Ben''s bed', 'Ben''s bed']
),
(
  (select id from public.reader_passages where slug = 'junior_b_rainy_picnic'),
  1,
  'Why did the friends move their picnic?',
  array['it began to rain', 'because it began to rain']
),
(
  (select id from public.reader_passages where slug = 'junior_b_rainy_picnic'),
  2,
  'Where did they have the picnic?',
  array['Nina''s living room']
),
(
  (select id from public.reader_passages where slug = 'senior_a_lost_wallet'),
  1,
  'Where did Daniel find the wallet?',
  array['near the bus stop']
),
(
  (select id from public.reader_passages where slug = 'senior_a_lost_wallet'),
  2,
  'How did the librarian identify the owner?',
  array['a library card', 'There was some money and a library card inside it']
),
(
  (select id from public.reader_passages where slug = 'senior_b_recycling_day'),
  1,
  'Why did Class 2B win a trip?',
  array['collected the largest amount', 'they collected the largest amount']
),
(
  (select id from public.reader_passages where slug = 'senior_b_recycling_day'),
  2,
  'How much waste did the project keep out of landfill?',
  array['more than five hundred kilograms']
),
(
  (select id from public.reader_passages where slug = 'senior_c_community_theatre'),
  1,
  'Who formed the group that saved the theatre?',
  array['local residents']
),
(
  (select id from public.reader_passages where slug = 'senior_c_community_theatre'),
  2,
  'What allowed the theatre to stay open?',
  array['Ticket sales gradually increased', 'ticket sales']
),
(
  (select id from public.reader_passages where slug = 'senior_d_rooftop_bees'),
  1,
  'Where do the bees find food?',
  array['in parks, gardens and window boxes throughout the city', 'parks, gardens and window boxes throughout the city']
),
(
  (select id from public.reader_passages where slug = 'senior_d_rooftop_bees'),
  2,
  'What is the main aim of the beehive project?',
  array['conservation', 'conservation remains the main purpose of the project']
),
(
  (select id from public.reader_passages where slug = 'pre_lower_music_memory'),
  1,
  'Which two mental skills may regular practice improve?',
  array['attention and memory']
),
(
  (select id from public.reader_passages where slug = 'pre_lower_music_memory'),
  2,
  'What is more important for progress than natural talent?',
  array['consistent effort']
),
(
  (select id from public.reader_passages where slug = 'lower_repair_cafes'),
  1,
  'How do repair cafés reduce waste?',
  array['by extending the life of items that might otherwise be thrown away', 'extending the life of items that might otherwise be thrown away']
),
(
  (select id from public.reader_passages where slug = 'lower_repair_cafes'),
  2,
  'How much does the advice cost?',
  array['free', 'the advice is always free']
),
(
  (select id from public.reader_passages where slug = 'advanced_urban_trees'),
  1,
  'How do trees reduce the need for air conditioning?',
  array['their shade lowers surface temperatures', 'shade lowers surface temperatures']
),
(
  (select id from public.reader_passages where slug = 'advanced_urban_trees'),
  2,
  'What do long-term planting programmes require?',
  array['careful species selection and sustained maintenance']
),
(
  (select id from public.reader_passages where slug = 'proficiency_useful_uncertainty'),
  1,
  'What does acknowledging uncertainty indicate in research?',
  array['a sign of precision rather than weakness', 'precision rather than weakness']
),
(
  (select id from public.reader_passages where slug = 'proficiency_useful_uncertainty'),
  2,
  'What may happen when the limits of conclusions are hidden?',
  array['it ultimately undermines informed judgement', 'undermines informed judgement']
)
on conflict (passage_id, sort_order) do update set
  question = excluded.question,
  accepted_answers = excluded.accepted_answers,
  is_active = true;
