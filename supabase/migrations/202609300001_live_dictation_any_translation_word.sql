-- Accept any shared word from translation_gr or accepted_words in live dictation.
-- The submission RPC already checks both columns with this matcher.
-- Preserve existing whole-answer spelling tolerance and optional prefixes.
create or replace function public.live_dictation_answer_matches(typed text, correct text)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  normalized_typed text := public.live_normalize_answer(typed);
  candidate text := public.live_normalize_answer(correct);
  optional_prefixes constant text[] := array[
    'ο', 'η', 'το', 'οι', 'τα', 'του', 'τησ', 'των', 'τον', 'την', 'τη', 'τουσ', 'τισ',
    'ενασ', 'μια', 'μιασ', 'ενα', 'ενοσ', 'εναν',
    'με', 'σε', 'απο', 'για', 'στο', 'στον', 'στη', 'στην', 'στα', 'στουσ', 'στισ',
    'στου', 'στησ', 'στων'
  ];
begin
  if normalized_typed = '' or candidate = '' then return false; end if;
  -- Any shared whole word is sufficient, including articles and prepositions.
  -- Split punctuation before normalization so adjacent alternatives stay separate.
  if exists (
    select 1
    from regexp_split_to_table(lower(coalesce(typed, '')), '[^a-z0-9α-ωάέήίόύώϊΐϋΰ]+') given(word)
    join regexp_split_to_table(lower(coalesce(correct, '')), '[^a-z0-9α-ωάέήίόύώϊΐϋΰ]+') accepted(word)
      on public.live_normalize_answer(given.word) = public.live_normalize_answer(accepted.word)
    where public.live_normalize_answer(given.word) <> ''
  ) then return true; end if;
  loop
    if public.live_answer_within_tolerance(normalized_typed, candidate) then return true; end if;
    -- Only drop complete, leading function words from the expected answer.
    -- Never drop negation or reduce a single-word answer to an empty string.
    exit when position(' ' in candidate) = 0
      or not (split_part(candidate, ' ', 1) = any(optional_prefixes));
    candidate := substr(candidate, position(' ' in candidate) + 1);
  end loop;
  return false;
end;
$$;
