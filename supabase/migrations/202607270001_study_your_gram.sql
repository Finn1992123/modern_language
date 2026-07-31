-- Study your gram: editable theory, question bank and student attempts.

create table if not exists public.study_gram_topics (
  slug text primary key,
  title text not null unique,
  sort_order integer not null unique,
  theory jsonb not null default '[]'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  check (slug ~ '^[a-z0-9_]+$'),
  check (jsonb_typeof(theory) = 'array')
);

create table if not exists public.study_gram_questions (
  id uuid primary key default gen_random_uuid(),
  topic_slug text not null references public.study_gram_topics(slug)
    on update cascade on delete cascade,
  sort_order integer not null,
  prompt text not null,
  verb_hint text not null,
  accepted_answers text[] not null,
  highlight_phrases text[] not null default '{}',
  explanation text not null default '',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (topic_slug, sort_order),
  check (position('{{gap}}' in prompt) > 0),
  check (cardinality(accepted_answers) > 0)
);

create index if not exists study_gram_questions_active_topic_idx
on public.study_gram_questions(topic_slug, sort_order)
where is_active = true;

alter table public.study_gram_topics enable row level security;
alter table public.study_gram_questions enable row level security;

drop policy if exists study_gram_topics_read_authenticated
on public.study_gram_topics;
create policy study_gram_topics_read_authenticated
on public.study_gram_topics for select to authenticated
using (is_active = true);

drop policy if exists study_gram_questions_read_authenticated
on public.study_gram_questions;
create policy study_gram_questions_read_authenticated
on public.study_gram_questions for select to authenticated
using (
  is_active = true
  and exists (
    select 1
    from public.study_gram_topics t
    where t.slug = topic_slug and t.is_active = true
  )
);

create table if not exists public.study_gram_attempts (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete cascade,
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  topic_slugs text[] not null,
  correct_answers integer not null check (correct_answers >= 0),
  total_questions integer not null check (total_questions > 0),
  created_at timestamptz not null default now(),
  check (cardinality(topic_slugs) > 0),
  check (correct_answers <= total_questions)
);

create index if not exists study_gram_attempts_student_idx
on public.study_gram_attempts(student_id, created_at desc);

alter table public.study_gram_attempts enable row level security;

drop policy if exists study_gram_attempts_read_own
on public.study_gram_attempts;
create policy study_gram_attempts_read_own
on public.study_gram_attempts for select to authenticated
using (auth_user_id = auth.uid());

create or replace function public.submit_study_gram_attempt(
  input_student_id uuid,
  input_class_id uuid,
  input_topic_slugs text[],
  input_correct_answers integer,
  input_total_questions integer
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_attempt_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if cardinality(input_topic_slugs) is null
     or cardinality(input_topic_slugs) = 0 then
    raise exception 'select at least one topic';
  end if;
  if input_total_questions <> cardinality(input_topic_slugs) * 12 then
    raise exception 'every selected topic must contain 12 questions';
  end if;
  if input_correct_answers < 0
     or input_correct_answers > input_total_questions then
    raise exception 'invalid score';
  end if;
  if exists (
    select 1
    from unnest(input_topic_slugs) selected_slug
    where not exists (
      select 1 from public.study_gram_topics t
      where t.slug = selected_slug and t.is_active = true
    )
  ) then
    raise exception 'invalid or inactive topic';
  end if;
  if not exists (
    select 1
    from public.students s
    join public.students_language sl on sl.student_id = s.id
    join public.user_access ua on ua.user_id = s.user_id
    where s.id = input_student_id
      and sl.class_id = input_class_id
      and ua.auth_user_id = auth.uid()
  ) then
    raise exception 'student or class access denied';
  end if;

  insert into public.study_gram_attempts (
    student_id, class_id, auth_user_id, topic_slugs,
    correct_answers, total_questions
  )
  values (
    input_student_id, input_class_id, auth.uid(), input_topic_slugs,
    input_correct_answers, input_total_questions
  )
  returning id into new_attempt_id;
  return new_attempt_id;
end;
$$;

revoke all on function public.submit_study_gram_attempt(
  uuid, uuid, text[], integer, integer
) from public;
grant execute on function public.submit_study_gram_attempt(
  uuid, uuid, text[], integer, integer
) to authenticated;

-- Each theory line contains normal and highlighted text fragments. This lets the
-- Flutter screen render highlights without storing HTML.
insert into public.study_gram_topics (slug, title, sort_order, theory)
values
('present_simple', 'Present Simple', 1, '[
  {"label":"Affirmative","parts":[{"text":"I/you/we/they play, but he/she/it play"},{"text":"s","highlight":true},{"text":"."}]},
  {"label":"Negative","parts":[{"text":"I/you/we/they don''t play, but he/she/it "},{"text":"doesn''t","highlight":true},{"text":" play."}]},
  {"label":"Question","parts":[{"text":"Do I/you/we/they play? "},{"text":"Does","highlight":true},{"text":" he/she/it play?"}]},
  {"label":"Use","parts":[{"text":"Habits, routines and facts. Keywords: always, usually, often, every day."}]}
]'::jsonb),
('present_continuous', 'Present Continuous', 2, '[
  {"label":"Form","parts":[{"text":"am/is/are + verb-"},{"text":"ing","highlight":true},{"text":": I am playing, she is playing, they are playing."}]},
  {"label":"Negative / Question","parts":[{"text":"She "},{"text":"isn''t","highlight":true},{"text":" playing. "},{"text":"Are","highlight":true},{"text":" they playing?"}]},
  {"label":"Use","parts":[{"text":"Actions happening now or temporary situations. Keywords: now, at the moment, today."}]}
]'::jsonb),
('present_perfect', 'Present Perfect', 3, '[
  {"label":"Form","parts":[{"text":"have/has + "},{"text":"past participle","highlight":true},{"text":": I have played, she has played."}]},
  {"label":"Negative / Question","parts":[{"text":"He hasn''t finished. "},{"text":"Have","highlight":true},{"text":" you finished?"}]},
  {"label":"Use","parts":[{"text":"Past actions connected to now. Keywords: already, just, yet, ever, never, since, for."}]}
]'::jsonb),
('present_perfect_continuous', 'Present Perfect Continuous', 4, '[
  {"label":"Form","parts":[{"text":"have/has "},{"text":"been","highlight":true},{"text":" + verb-ing: They have been studying."}]},
  {"label":"Use","parts":[{"text":"An action that began in the past and is still continuing. Keywords: since, for, all day."}]}
]'::jsonb),
('past_simple', 'Past Simple', 5, '[
  {"label":"Affirmative","parts":[{"text":"Regular verb + "},{"text":"-ed","highlight":true},{"text":" or irregular 2nd form: played, went."}]},
  {"label":"Negative / Question","parts":[{"text":"She "},{"text":"didn''t","highlight":true},{"text":" play. "},{"text":"Did","highlight":true},{"text":" she play?"}]},
  {"label":"Use","parts":[{"text":"Finished actions in the past. Keywords: yesterday, ago, last week, in 2020."}]}
]'::jsonb),
('past_continuous', 'Past Continuous', 6, '[
  {"label":"Form","parts":[{"text":"was/were + verb-"},{"text":"ing","highlight":true},{"text":": I was playing, they were playing."}]},
  {"label":"Use","parts":[{"text":"An action in progress at a specific past time, often interrupted by another action."}]}
]'::jsonb),
('past_perfect', 'Past Perfect', 7, '[
  {"label":"Form","parts":[{"text":"had + "},{"text":"past participle","highlight":true},{"text":": She had left."}]},
  {"label":"Use","parts":[{"text":"The earlier of two past actions. Keywords: before, after, by the time, already."}]}
]'::jsonb),
('past_perfect_continuous', 'Past Perfect Continuous', 8, '[
  {"label":"Form","parts":[{"text":"had "},{"text":"been","highlight":true},{"text":" + verb-ing: We had been waiting."}]},
  {"label":"Use","parts":[{"text":"Duration of an ongoing action before another past event. Keywords: for, since, all day."}]}
]'::jsonb),
('future_simple', 'Future Simple', 9, '[
  {"label":"Form","parts":[{"text":"will + "},{"text":"base verb","highlight":true},{"text":": I will play. I won''t play. Will you play?"}]},
  {"label":"Use","parts":[{"text":"Predictions, promises and spontaneous decisions. Keywords: tomorrow, probably, I think."}]}
]'::jsonb),
('future_continuous', 'Future Continuous', 10, '[
  {"label":"Form","parts":[{"text":"will "},{"text":"be","highlight":true},{"text":" + verb-ing: I will be working."}]},
  {"label":"Use","parts":[{"text":"An action that will be in progress at a specific future time."}]}
]'::jsonb),
('future_perfect', 'Future Perfect', 11, '[
  {"label":"Form","parts":[{"text":"will "},{"text":"have","highlight":true},{"text":" + past participle: She will have finished."}]},
  {"label":"Use","parts":[{"text":"An action completed before a future deadline. Keywords: by, by the time."}]}
]'::jsonb),
('future_perfect_continuous', 'Future Perfect Continuous', 12, '[
  {"label":"Form","parts":[{"text":"will have "},{"text":"been","highlight":true},{"text":" + verb-ing."}]},
  {"label":"Use","parts":[{"text":"Duration of an action up to a future point. Keywords: for + period, by + future time."}]}
]'::jsonb),
('be_going_to', 'Be going to', 13, '[
  {"label":"Form","parts":[{"text":"am/is/are "},{"text":"going to","highlight":true},{"text":" + base verb."}]},
  {"label":"Use","parts":[{"text":"Plans and intentions, or predictions based on present evidence."}]}
]'::jsonb),
('passive_voice', 'Passive voice', 14, '[
  {"label":"Form","parts":[{"text":"correct tense of "},{"text":"be","highlight":true},{"text":" + past participle: The room is cleaned."}]},
  {"label":"Use","parts":[{"text":"Use the passive when the action or result is more important than the person doing it."}]}
]'::jsonb),
('reported_speech', 'Reported Speech', 15, '[
  {"label":"Backshift","parts":[{"text":"Present → past, past → past perfect, will → "},{"text":"would","highlight":true},{"text":"."}]},
  {"label":"Example","parts":[{"text":"“I am tired.” → She said (that) she "},{"text":"was","highlight":true},{"text":" tired."}]}
]'::jsonb),
('modals', 'Modals', 16, '[
  {"label":"Form","parts":[{"text":"modal + "},{"text":"base verb","highlight":true},{"text":": can swim, must study, should go."}]},
  {"label":"Rule","parts":[{"text":"No -s in the third person and no “to” after most modal verbs."}]}
]'::jsonb),
('modal_perfect', 'Modal Perfect', 17, '[
  {"label":"Form","parts":[{"text":"modal + "},{"text":"have","highlight":true},{"text":" + past participle: should have studied."}]},
  {"label":"Use","parts":[{"text":"Past possibility, deduction, criticism or regret."}]}
]'::jsonb),
('conditionals', 'Conditionals', 18, '[
  {"label":"Zero / First","parts":[{"text":"If + present, present / "},{"text":"will","highlight":true},{"text":" + base verb."}]},
  {"label":"Second / Third","parts":[{"text":"If + past, would + base / If + past perfect, "},{"text":"would have","highlight":true},{"text":" + participle."}]}
]'::jsonb),
('mixed_review', 'Mixed review', 19, '[
  {"label":"Tip","parts":[{"text":"Look carefully at time expressions and decide whether the action is a habit, in progress, completed or hypothetical."}]}
]'::jsonb)
on conflict (slug) do update set
  title = excluded.title,
  sort_order = excluded.sort_order,
  theory = excluded.theory,
  is_active = true;

-- The requested list contains 18 standalone phenomena. "Mixed review" is kept
-- inactive as a prepared extension and does not appear until explicitly enabled.
update public.study_gram_topics set is_active = false where slug = 'mixed_review';

create or replace function pg_temp.seed_gram_questions(
  input_topic text,
  input_prompts text[],
  input_hints text[],
  input_answers text[],
  input_highlights text[]
)
returns void
language plpgsql
as $$
begin
  if cardinality(input_prompts) <> 12
     or cardinality(input_hints) <> 12
     or cardinality(input_answers) <> 12
     or cardinality(input_highlights) <> 12 then
    raise exception '% must have exactly 12 questions', input_topic;
  end if;

  insert into public.study_gram_questions (
    topic_slug, sort_order, prompt, verb_hint,
    accepted_answers, highlight_phrases
  )
  select
    input_topic,
    n,
    input_prompts[n],
    input_hints[n],
    string_to_array(input_answers[n], '|'),
    case when input_highlights[n] = '' then '{}'::text[]
         else string_to_array(input_highlights[n], '|') end
  from generate_series(1, 12) n
  on conflict (topic_slug, sort_order) do update set
    prompt = excluded.prompt,
    verb_hint = excluded.verb_hint,
    accepted_answers = excluded.accepted_answers,
    highlight_phrases = excluded.highlight_phrases,
    is_active = true;
end;
$$;

select pg_temp.seed_gram_questions(
  'present_simple',
  array[
    'Maria {{gap}} football every day.','Tom usually {{gap}} coffee in the morning.',
    'My friends {{gap}} English on Mondays.','The sun {{gap}} in the east.',
    'Anna never {{gap}} late for school.','We {{gap}} our grandparents every weekend.',
    'He {{gap}} his homework after dinner.','They don''t {{gap}} television on weekdays.',
    'Does Peter {{gap}} to work by bus?','My sister {{gap}} two languages.',
    'I often {{gap}} a book before bed.','The shop {{gap}} at nine o''clock.'
  ],
  array['play','drink','study','rise','arrive','visit','do','watch','go','speak','read','open'],
  array['plays','drinks','study','rises','arrives','visit','does','watch','go','speaks','read','opens'],
  array['every day','usually','on Mondays','in the east','never','every weekend','after dinner','don''t|on weekdays','Does','two languages','often','at nine o''clock']
);

select pg_temp.seed_gram_questions(
  'present_continuous',
  array[
    'Maria {{gap}} football now.','Listen! The baby {{gap}}.',
    'We {{gap}} for our exam at the moment.','I {{gap}} dinner right now.',
    'They {{gap}} in Athens this month.','Look! It {{gap}}.',
    'Why {{gap}} you laughing?','Tom isn''t {{gap}} today.',
    'The children {{gap}} in the garden.','She {{gap}} a blue jacket today.',
    'I {{gap}} on a new project this week.','The bus {{gap}} now.'
  ],
  array['play','cry','study','cook','stay','snow','be','work','run','wear','work','come'],
  array['is playing','is crying','are studying','am cooking','are staying','is snowing','are','working','are running','is wearing','am working','is coming'],
  array['now','Listen','at the moment','right now','this month','Look','Why','isn''t|today','in the garden','today','this week','now']
);

select pg_temp.seed_gram_questions(
  'present_perfect',
  array[
    'Maria {{gap}} her homework already.','I {{gap}} sushi in my life.',
    'They {{gap}}.','{{gap}} London?',
    'Tom {{gap}} me yet.','We {{gap}} here since 2020.',
    'She {{gap}} that film three times.','The train {{gap}}.',
    'My parents {{gap}} a new car.','{{gap}} him?',
    'It {{gap}} a lot this week.','I {{gap}} my keys!'
  ],
  array['finish','eat','arrive','visit','call','live','see','leave','buy','know','rain','lose'],
  array['has finished','have never eaten','have just arrived','Have you ever visited','has not called|hasn''t called','have lived','has seen','has already left','have bought','How long have you known','has rained','have lost'],
  array['already','never','just','ever','yet','since 2020','three times','already','','How long','this week','']
);

select pg_temp.seed_gram_questions(
  'present_perfect_continuous',
  array[
    'Maria {{gap}} for two hours.','It {{gap}} since this morning.',
    'They {{gap}} all day.','I {{gap}} English for five years.',
    'Tom {{gap}} hard recently.','{{gap}} for the bus?',
    'We {{gap}} for the bus for thirty minutes.','She {{gap}} too much lately.',
    'The children {{gap}} outside since noon.','He {{gap}} the house all morning.',
    'You {{gap}} that game for hours.','My eyes hurt because I {{gap}}.'
  ],
  array['study','rain','work','learn','train','wait','wait','work','play','paint','play','read'],
  array['has been studying','has been raining','have been working','have been learning','has been training','How long have you been waiting','have been waiting','has been working','have been playing','has been painting','have been playing','have been reading'],
  array['for two hours','since this morning','all day','for five years','recently','How long','for thirty minutes','lately','since noon','all morning','for hours','']
);

select pg_temp.seed_gram_questions(
  'past_simple',
  array[
    'Maria {{gap}} football yesterday.','We {{gap}} Rome last summer.',
    'Tom {{gap}} a new laptop two days ago.','I {{gap}} her at the party.',
    'They {{gap}} home late last night.','She {{gap}} me an email this morning.',
    'The film {{gap}} at ten o''clock.','He didn''t {{gap}} breakfast.',
    'Did you {{gap}} the museum?','My parents {{gap}} in 2010.',
    'I {{gap}} my keys on Monday.','The children {{gap}} in the park.'
  ],
  array['play','visit','buy','meet','come','send','finish','eat','enjoy','marry','lose','run'],
  array['played','visited','bought','met','came','sent','finished','eat','enjoy','married','lost','ran'],
  array['yesterday','last summer','two days ago','at the party','last night','this morning','at ten o''clock','didn''t','Did','in 2010','on Monday','']
);

select pg_temp.seed_gram_questions(
  'past_continuous',
  array[
    'Maria {{gap}} when I called.','At eight o''clock, we {{gap}} dinner.',
    'They {{gap}} while it was raining.','I {{gap}} when the alarm rang.',
    'Tom {{gap}} all afternoon.','{{gap}} at midnight?',
    'The children {{gap}} when their mother arrived.','She {{gap}} while he was cooking.',
    'It {{gap}} heavily at that moment.','We {{gap}} home when we saw the accident.',
    'He wasn''t {{gap}} during the lesson.','The dog {{gap}} under the table.'
  ],
  array['study','have','drive','sleep','work','do','play','read','rain','walk','listen','hide'],
  array['was studying','were having','were driving','was sleeping','was working','What were you doing','were playing','was reading','was raining','were walking','listening','was hiding'],
  array['when I called','At eight o''clock','while','when the alarm rang','all afternoon','at midnight','when their mother arrived','while','at that moment','when','wasn''t|during','']
);

select pg_temp.seed_gram_questions(
  'past_perfect',
  array[
    'The train {{gap}} before we arrived.','She {{gap}} the test by noon.',
    'I was hungry because I {{gap}} breakfast.','They {{gap}} when we called.',
    'After he {{gap}} his work, he went home.','We couldn''t enter because we {{gap}} the key.',
    'By the time I woke up, everyone {{gap}}.','Tom knew the city because he {{gap}} there before.',
    'She {{gap}} snow before that trip.','The film {{gap}} when we reached the cinema.',
    'He apologised after he {{gap}} his mistake.','I recognised her because we {{gap}} before.'
  ],
  array['leave','complete','not eat','go','finish','lose','leave','live','see','start','realise','meet'],
  array['had left','had completed','had not eaten','had already gone','had finished','had lost','had left','had lived','had never seen','had started','had realised','had met'],
  array['before','by noon','because','already','After','because','By the time','before','never|before','when','after','before']
);

select pg_temp.seed_gram_questions(
  'past_perfect_continuous',
  array[
    'We {{gap}} for an hour before the bus came.','He was tired because he {{gap}} all day.',
    'It {{gap}} for hours when the sun appeared.','They {{gap}} for months before they moved.',
    'Maria {{gap}} since morning, so she took a break.','{{gap}} before dinner?',
    'The ground was wet because it {{gap}}.','Tom {{gap}} there for ten years before he resigned.',
    'Her eyes were red because she {{gap}}.','We {{gap}} all morning when the machine broke.',
    'The children {{gap}} for hours before bedtime.','I {{gap}} English for a year before the course ended.'
  ],
  array['wait','work','rain','plan','study','drive','rain','work','cry','clean','play','learn'],
  array['had been waiting','had been working','had been raining','had been planning','had been studying','How long had you been driving','had been raining','had been working','had been crying','had been cleaning','had been playing','had been learning'],
  array['for an hour|before','all day','for hours|when','for months|before','since morning','How long|before','because','for ten years|before','because','all morning|when','for hours|before','for a year|before']
);

select pg_temp.seed_gram_questions(
  'future_simple',
  array[
    'I think Maria {{gap}} the match.','I {{gap}} you tomorrow.',
    'Don''t worry; I {{gap}} you.','They probably {{gap}} late.',
    'I''m thirsty. I {{gap}} some water.','{{gap}} the door, please?',
    'Perhaps it {{gap}} tonight.','I promise I {{gap}} anyone.',
    'The meeting {{gap}} at ten.','We {{gap}} without you.',
    'I''m sure she {{gap}} the exam.','One day people {{gap}} on Mars.'
  ],
  array['win','call','help','arrive','get','open','snow','tell','start','leave','pass','live'],
  array['will win','will call','will help','will arrive','will get','Will you open','will snow','will not tell|won''t tell','will start','will not leave|won''t leave','will pass','will live'],
  array['I think','tomorrow','Don''t worry','probably','','please','Perhaps','I promise','','not','I''m sure','One day']
);

select pg_temp.seed_gram_questions(
  'future_continuous',
  array[
    'This time tomorrow, we {{gap}} to Paris.','At nine tonight, she {{gap}}.',
    'Don''t call at six; I {{gap}} dinner.','Next week they {{gap}} in Madrid.',
    'At noon, Tom {{gap}} his exam.','{{gap}} the car this evening?',
    'In an hour, the children {{gap}}.','This weekend I {{gap}} at home.',
    'At this time next year, he {{gap}} at university.','We {{gap}} over the Atlantic at midnight.',
    'She {{gap}} when you arrive.','They {{gap}} the match tomorrow afternoon.'
  ],
  array['fly','study','cook','stay','take','use','sleep','relax','study','travel','work','watch'],
  array['will be flying','will be studying','will be cooking','will be staying','will be taking','Will you be using','will be sleeping','will be relaxing','will be studying','will be travelling|will be traveling','will be working','will be watching'],
  array['This time tomorrow','At nine tonight','at six','Next week','At noon','this evening','In an hour','This weekend','this time next year','at midnight','when you arrive','tomorrow afternoon']
);

select pg_temp.seed_gram_questions(
  'future_perfect',
  array[
    'By Friday, I {{gap}} the report.','They {{gap}} by the time we arrive.',
    'By next year, she {{gap}} university.','Tom {{gap}} the book by tomorrow.',
    'By six o''clock, we {{gap}} the work.','{{gap}} by noon?',
    'The train {{gap}} before we reach the station.','By 2030, they {{gap}} the bridge.',
    'She {{gap}} all the emails by lunchtime.','In two hours, I {{gap}} the exam.',
    'By then, the children {{gap}} to bed.','We {{gap}} dinner before the film starts.'
  ],
  array['complete','leave','finish','read','do','arrive','depart','build','answer','finish','go','eat'],
  array['will have completed','will have left','will have finished','will have read','will have done','Will you have arrived','will have departed','will have built','will have answered','will have finished','will have gone','will have eaten'],
  array['By Friday','by the time','By next year','by tomorrow','By six o''clock','by noon','before','By 2030','by lunchtime','In two hours','By then','before']
);

select pg_temp.seed_gram_questions(
  'future_perfect_continuous',
  array[
    'By June, she {{gap}} here for ten years.','Next month, we {{gap}} here for a year.',
    'By noon, I {{gap}} for six hours.','In May, Tom {{gap}} for thirty years.',
    'By the time you arrive, they {{gap}} for two hours.','Next week, it {{gap}} for a month.',
    'By 2030, he {{gap}} English for fifteen years.','At five, we {{gap}} all day.',
    'By midnight, she {{gap}} for twelve hours.','In December, I {{gap}} this project for a year.',
    'By dinner, the children {{gap}} for five hours.','Next summer, they {{gap}} around Europe for six months.'
  ],
  array['teach','live','work','drive','wait','rain','study','travel','sleep','develop','play','travel'],
  array['will have been teaching','will have been living','will have been working','will have been driving','will have been waiting','will have been raining','will have been studying','will have been travelling|will have been traveling','will have been sleeping','will have been developing','will have been playing','will have been travelling|will have been traveling'],
  array['By June|for ten years','Next month|for a year','By noon|for six hours','In May|for thirty years','By the time|for two hours','Next week|for a month','By 2030|for fifteen years','At five|all day','By midnight|for twelve hours','In December|for a year','By dinner|for five hours','Next summer|for six months']
);

select pg_temp.seed_gram_questions(
  'be_going_to',
  array[
    'Maria {{gap}} football this afternoon.','Look at those clouds! It {{gap}}.',
    'We {{gap}} a new car next month.','I {{gap}} medicine at university.',
    'They {{gap}} the kitchen this weekend.','{{gap}} us tonight?',
    'Be careful! You {{gap}} that glass.','She {{gap}} the invitation.',
    'My parents {{gap}} abroad next year.','The team {{gap}} hard for the final.',
    'I {{gap}} a cake for her birthday.','Those boxes {{gap}}.'
  ],
  array['play','rain','buy','study','paint','join','drop','accept','travel','train','make','fall'],
  array['is going to play','is going to rain','are going to buy','am going to study','are going to paint','Is Tom going to join','are going to drop','is not going to accept|isn''t going to accept','are going to travel','is going to train','am going to make','are going to fall'],
  array['this afternoon','Look at those clouds','next month','','this weekend','tonight','Be careful','not','next year','for the final','birthday','']
);

select pg_temp.seed_gram_questions(
  'passive_voice',
  array[
    'The classrooms {{gap}} every morning.','The museum {{gap}} in 1890.',
    'English {{gap}} all over the world.','The emails {{gap}} yesterday.',
    'The bridge {{gap}} next year.','The work {{gap}}.',
    'This book {{gap}} by George Orwell.','The room {{gap}} at the moment.',
    'The results {{gap}} tomorrow.','My bike {{gap}} last night.',
    'Dinner must {{gap}} before eight.','The windows {{gap}} every month.'
  ],
  array['clean','build','speak','send','complete','finish','write','paint','announce','steal','prepare','wash'],
  array['are cleaned','was built','is spoken','were sent','will be completed','has already been finished','was written','is being painted','will be announced','was stolen','be prepared','are washed'],
  array['every morning','in 1890','all over the world','yesterday','next year','already','by George Orwell','at the moment','tomorrow','last night','must','every month']
);

select pg_temp.seed_gram_questions(
  'reported_speech',
  array[
    '“I am tired,” Anna said. Anna said that she {{gap}} tired.','“I have lost my keys,” Tom said. Tom said that he {{gap}} his keys.',
    '“I will call you,” she said. She said that she {{gap}} me.','“We are studying,” they said. They said that they {{gap}}.',
    '“I saw Maria,” he said. He said that he {{gap}} Maria.','“I can swim,” John said. John said that he {{gap}} swim.',
    '“I may be late,” she said. She said that she {{gap}} late.','“I must leave,” Tom said. Tom said that he {{gap}} leave.',
    '“I don''t like coffee,” Eva said. Eva said that she {{gap}} coffee.','“We went home,” they said. They said that they {{gap}} home.',
    '“I am working now,” he said. He said that he {{gap}} then.','“I have never been here,” she said. She said that she {{gap}} there.'
  ],
  array['be','lose','call','study','see','can','may','must','not like','go','work','never be'],
  array['was','had lost','would call','were studying','had seen','could','might be','had to','did not like|didn''t like','had gone','was working','had never been'],
  array['said that','said that','said that','said that','said that','said that','said that','said that','said that','said that','now|then','never|here|there']
);

select pg_temp.seed_gram_questions(
  'modals',
  array[
    'You {{gap}} wear a seat belt. It is the law.','{{gap}} you swim when you were five?',
    'You look tired. You {{gap}} rest.','Students {{gap}} use phones during the exam.',
    '{{gap}} I borrow your pen, please?','It {{gap}} rain later; take an umbrella.',
    'You {{gap}} be quiet in the library.','We {{gap}} hurry; we have plenty of time.',
    'She {{gap}} speak three languages.','You {{gap}} eat so much sugar.',
    '{{gap}} you help me with this box?','Visitors {{gap}} touch the paintings.'
  ],
  array['must','can','should','must not','may','might','must','not need','can','should not','could','must not'],
  array['must','Could','should','must not|mustn''t','May','might','must','need not|needn''t','can','should not|shouldn''t','Could','must not|mustn''t'],
  array['the law','when you were five','tired','during the exam','please','later','in the library','plenty of time','three languages','so much sugar','','Visitors']
);

select pg_temp.seed_gram_questions(
  'modal_perfect',
  array[
    'You failed the test. You {{gap}} harder.','She isn''t here. She {{gap}} the bus.',
    'Tom knew the answer. He {{gap}} the book.','I''m not sure, but they {{gap}} home.',
    'You {{gap}} me; I was worried.','The ground is wet. It {{gap}} last night.',
    'He {{gap}} the truth, but he chose not to.','We bought too much food. We {{gap}} so much.',
    'She got full marks. She {{gap}} very hard.','They arrived early; they {{gap}} a taxi.',
    'I {{gap}} that email; it was private.','The door is open. Someone {{gap}} it.'
  ],
  array['study','miss','read','go','call','rain','tell','not buy','work','take','not read','open'],
  array['should have studied','must have missed','must have read','might have gone|may have gone','should have called','must have rained','could have told','should not have bought|shouldn''t have bought','must have worked','might have taken|may have taken','should not have read|shouldn''t have read','must have opened'],
  array['failed','isn''t here','knew the answer','not sure','worried','ground is wet','chose not to','too much','full marks','early','private','door is open']
);

select pg_temp.seed_gram_questions(
  'conditionals',
  array[
    'If you heat ice, it {{gap}}.','If it rains tomorrow, we {{gap}} home.',
    'If I had more time, I {{gap}} Japanese.','If she had studied, she {{gap}} the exam.',
    'Unless you hurry, you {{gap}} the bus.','If I were you, I {{gap}} to him.',
    'If they arrive early, {{gap}} me.','Water boils if you {{gap}} it to 100°C.',
    'If Tom knew the answer, he {{gap}} us.','If we had left earlier, we {{gap}} the train.',
    'I will help you if you {{gap}} me.','If she were taller, she {{gap}} basketball.'
  ],
  array['melt','stay','learn','pass','miss','talk','call','heat','tell','catch','ask','play'],
  array['melts','will stay','would learn','would have passed','will miss','would talk','call','heat','would tell','would have caught','ask','would play'],
  array['If','tomorrow','If','had studied','Unless','If I were you','If','100°C','If','had left earlier','if','If']
);

-- Be going to is a separate requested topic. The prepared mixed-review row is
-- excluded, leaving exactly the 18 phenomena requested for the first release.
