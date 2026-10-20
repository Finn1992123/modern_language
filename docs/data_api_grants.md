# Data API grants

New public tables must declare the privileges required by their API callers in
the migration that creates them. RLS policies do not grant table access.

- For authenticated read access, add `GRANT SELECT ON TABLE public.table_name TO authenticated`
  and the appropriate RLS policies.
- Grant writes only when the client performs them directly; use column-level
  grants when only specific fields may be edited.
- Tables used only inside existing SECURITY DEFINER RPCs do not need direct
  client table grants. Preserve their RPC authorization checks and EXECUTE grants.
- Backend Data API calls also require table privileges for `service_role`;
  bypassing RLS does not replace these privileges.
- Do not grant all public tables to `anon` or restore blanket default privileges.

`202610200001_explicit_data_api_grants.sql` applies the required grants to existing
installations. It is additive: it does not remove existing grants or change RLS.
Apply this migration through the normal deployment process or run its contents
in the intended project's Supabase SQL Editor.

The repository does not contain the initial schema for tables such as users,
students, payments, books, articles, and announcements. A completely empty
database still requires that baseline schema and its RLS policies before replaying
these migrations. This change does not make a full empty-database reset supported.

After deployment, verify with an authenticated account that profile, payments,
library, tense questions, grammar and reader screens load, and verify notification
sending with an authorized teacher account. Check both successful access and
denied access to another family's private data.
