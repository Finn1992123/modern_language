-- Existing installations do not replay edited historical migrations.
-- Grant only the direct Data API access used by the app and notification worker.
-- RLS policies continue to determine which rows authenticated users can access.
begin;

grant select on table
  public.user_access,
  public.users,
  public.students,
  public.payments,
  public.books,
  public.articles,
  public.article_sections,
  public.cefr_books,
  public.vocabulary_words,
  public.tense_questions,
  public.study_gram_topics,
  public.study_gram_questions,
  public.reader_passages,
  public.reader_questions
to authenticated;

-- Profile writes already have column-level grants in the original migrations.
-- Other writes go through SECURITY DEFINER RPCs with explicit EXECUTE grants.
-- The notification worker uses service_role for these direct API operations.
grant select on table public.announcements to service_role;
grant update (push_sent_at) on public.announcements to service_role;
grant select, delete on table public.push_notification_devices to service_role;

commit;
