-- RainTrace initial schema: properties, inspections, findings.
--
-- Design notes
-- ------------
-- * UUID primary keys via gen_random_uuid() (core in PostgreSQL 13+; available
--   on every Supabase project, no extension required).
-- * All timestamps are timestamptz and stored in UTC. `observed_at` (when the
--   condition was seen) is intentionally distinct from `created_at` (when the
--   row was recorded / uploaded).
-- * AI output is separate from human-confirmed data. `category` and
--   `confirmed_summary` are the inspector-confirmed finding; the validated
--   model suggestion lives in `ai_suggestion` (jsonb) with `ai_model_id`,
--   `ai_prompt_version` and `ai_analyzed_at` for traceability. Re-running AI can
--   only rewrite the ai_* columns, never the confirmed ones.
-- * Category/status are text + CHECK constraints (not enum types) so the
--   taxonomy can evolve in a normal migration.
-- * Every foreign key column is indexed; columns used by RLS policies are
--   indexed too. `created_by` indexes are partial because pre-auth rows are
--   NULL.
-- * Row Level Security is enabled on all three tables. Access is owner-scoped
--   for `authenticated`; `anon` is revoked and has no policy (default deny);
--   `service_role` bypasses RLS and is reserved for trusted server-side work.
--   Authentication is not implemented yet, so app access must currently go
--   through the server-only service-role client (lib/supabase/admin.ts).

-- ---------------------------------------------------------------------------
-- Shared trigger: keep updated_at current
-- ---------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

comment on function public.set_updated_at() is
  'Sets updated_at to now() on UPDATE. Attached to all RainTrace tables.';

-- ---------------------------------------------------------------------------
-- properties
-- ---------------------------------------------------------------------------

create table public.properties (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  address_or_description text,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint properties_name_not_blank check (length(btrim(name)) > 0),
  constraint properties_name_length check (length(name) <= 200)
);

comment on table public.properties is
  'A managed site/building at which inspections take place.';
comment on column public.properties.name is
  'Required display name, e.g. "Ashworth Court - Block B".';
comment on column public.properties.address_or_description is
  'Optional human-readable address or description of the site.';
comment on column public.properties.created_by is
  'auth.users id of the creator; set to NULL if that user is deleted.';

create index properties_created_by_idx
  on public.properties (created_by)
  where created_by is not null;

create trigger properties_set_updated_at
  before update on public.properties
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- inspections
-- ---------------------------------------------------------------------------

create table public.inspections (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties (id) on delete cascade,
  title text not null,
  inspection_date timestamptz not null default now(),
  status text not null default 'draft',
  notes text,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint inspections_title_not_blank check (length(btrim(title)) > 0),
  constraint inspections_title_length check (length(title) <= 200),
  constraint inspections_status_valid
    check (status in ('draft', 'in_progress', 'completed'))
);

comment on table public.inspections is
  'A single inspection event for one property, grouping its findings.';
comment on column public.inspections.inspection_date is
  'When the inspection took place (UTC; editable for backdated records).';
comment on column public.inspections.status is
  'Lifecycle: draft -> in_progress -> completed.';
comment on column public.inspections.notes is
  'Optional free-text notes from the inspector.';

-- Covers the property_id foreign key and per-property history ordering.
create index inspections_property_id_inspection_date_idx
  on public.inspections (property_id, inspection_date desc);

-- Global inspection history ordering.
create index inspections_inspection_date_idx
  on public.inspections (inspection_date desc);

create index inspections_created_by_idx
  on public.inspections (created_by)
  where created_by is not null;

create trigger inspections_set_updated_at
  before update on public.inspections
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- findings
-- ---------------------------------------------------------------------------

create table public.findings (
  id uuid primary key default gen_random_uuid(),
  inspection_id uuid not null references public.inspections (id) on delete cascade,
  category text,
  confirmed_summary text,
  photo_path text not null,
  location_description text,
  latitude numeric(9, 6),
  longitude numeric(9, 6),
  observed_at timestamptz not null default now(),
  ai_suggestion jsonb,
  ai_model_id text,
  ai_prompt_version text,
  ai_analyzed_at timestamptz,
  review_status text not null default 'pending',
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint findings_review_status_valid
    check (review_status in ('pending', 'confirmed', 'corrected', 'rejected')),
  constraint findings_confirmed_fields_required
    check (
      review_status not in ('confirmed', 'corrected')
      or (category is not null and confirmed_summary is not null)
    ),
  constraint findings_category_valid
    check (
      category is null
      or category in (
        'standing_water',
        'visible_water_flow',
        'possible_drain_obstruction',
        'water_on_walkway_or_road',
        'water_staining_or_dampness',
        'no_clear_water_related_issue',
        'uncertain'
      )
    ),
  constraint findings_summary_not_blank
    check (confirmed_summary is null or length(btrim(confirmed_summary)) > 0),
  constraint findings_summary_length
    check (confirmed_summary is null or length(confirmed_summary) <= 2000),
  constraint findings_location_description_not_blank
    check (location_description is null or length(btrim(location_description)) > 0),
  constraint findings_latitude_range
    check (latitude is null or latitude between -90 and 90),
  constraint findings_longitude_range
    check (longitude is null or longitude between -180 and 180),
  constraint findings_coordinates_paired
    check ((latitude is null) = (longitude is null)),
  constraint findings_location_present
    check (latitude is not null or location_description is not null),
  constraint findings_photo_path_not_url
    check (length(btrim(photo_path)) > 0 and photo_path !~* '^[a-z][a-z0-9+.-]*://'),
  constraint findings_ai_suggestion_object
    check (ai_suggestion is null or jsonb_typeof(ai_suggestion) = 'object'),
  constraint findings_ai_metadata_present
    check (ai_suggestion is null or (ai_model_id is not null and ai_analyzed_at is not null))
);

comment on table public.findings is
  'A photo-backed observation within an inspection. Confirmed fields are human-owned; ai_* fields hold the model suggestion.';
comment on column public.findings.category is
  'Inspector-confirmed visual category. NULL until the finding is confirmed.';
comment on column public.findings.confirmed_summary is
  'Inspector-confirmed description. NULL until the finding is confirmed.';
comment on column public.findings.photo_path is
  'Supabase Storage object path (e.g. findings/<inspection>/<uuid>.jpg); never a public URL.';
comment on column public.findings.location_description is
  'Manual location text, used when coordinates were not captured.';
comment on column public.findings.observed_at is
  'When the condition was observed (UTC); distinct from created_at.';
comment on column public.findings.ai_suggestion is
  'Validated model suggestion (category, summary, visible_evidence, uncertainty_note, needs_human_review). Never the confirmed finding.';
comment on column public.findings.ai_model_id is
  'Model identifier used for ai_suggestion, e.g. Qwen/Qwen3-VL-4B-Instruct.';
comment on column public.findings.ai_prompt_version is
  'Version tag for the prompt/schema used to produce ai_suggestion.';
comment on column public.findings.ai_analyzed_at is
  'When the AI suggestion was produced (UTC).';
comment on column public.findings.review_status is
  'pending: awaiting inspector review; confirmed: accepted as-is; corrected: edited by inspector; rejected: dismissed and excluded from reports. Confirmed and corrected findings are the ones included in reports.';

create index findings_inspection_id_idx
  on public.findings (inspection_id);

-- Category + date filtering for the history view.
create index findings_category_observed_at_idx
  on public.findings (category, observed_at desc);

-- Date-range / recency scanning across all findings.
create index findings_observed_at_idx
  on public.findings (observed_at desc);

-- Report generation only reads confirmed findings; keep this index small.
create index findings_report_observed_at_idx
  on public.findings (observed_at desc)
  where review_status in ('confirmed', 'corrected');

create index findings_created_by_idx
  on public.findings (created_by)
  where created_by is not null;

create trigger findings_set_updated_at
  before update on public.findings
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table public.properties enable row level security;
alter table public.inspections enable row level security;
alter table public.findings enable row level security;

-- One owner policy per table. `for all` covers select/insert/update/delete;
-- USING filters existing rows, WITH CHECK validates new/updated rows. Wrapping
-- auth.uid() in a subquery keeps it evaluated once per query, not per row.

create policy properties_owner_all on public.properties
  for all
  to authenticated
  using ((select auth.uid()) = created_by)
  with check ((select auth.uid()) = created_by);

create policy inspections_owner_all on public.inspections
  for all
  to authenticated
  using ((select auth.uid()) = created_by)
  with check ((select auth.uid()) = created_by);

create policy findings_owner_all on public.findings
  for all
  to authenticated
  using ((select auth.uid()) = created_by)
  with check ((select auth.uid()) = created_by);

-- ---------------------------------------------------------------------------
-- Privileges (least privilege; RLS still applies on top)
-- ---------------------------------------------------------------------------

grant select, insert, update, delete
  on public.properties, public.inspections, public.findings
  to authenticated, service_role;

-- Supabase's default privileges also grant TRUNCATE/REFERENCES/TRIGGER to
-- authenticated on new tables in `public`. None of these are used by the Data
-- API and TRUNCATE is not subject to RLS, so drop them.
revoke truncate, references, trigger
  on public.properties, public.inspections, public.findings
  from authenticated;

revoke all
  on public.properties, public.inspections, public.findings
  from anon;
