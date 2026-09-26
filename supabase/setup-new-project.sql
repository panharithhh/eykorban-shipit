-- EyKorBan PWA: the whole database in one file
--
-- Run once in a Supabase project: Dashboard → SQL Editor → New query → paste
-- this file → Run. It takes a few seconds.
--
-- Built by concatenating supabase/migrations/*.sql in order, then
-- supabase/seed.sql. When those change, rebuild this file from them rather
-- than editing it by hand.
--
-- What it does
--   0. Drops the four read-only sample tables from the earlier schema (users,
--      freelancer_profiles, project_cards, jobs), if they exist. Their rows are
--      the same demo people, work and jobs that step 2 recreates.
--   1. Creates the schema the PWA needs: 10 tables with Row Level Security,
--      the triggers that enforce the project lifecycle, and the
--      portfolio-images storage bucket.
--   2. Seeds demo data, including 10 demo sign-ins (password: password123).
--
-- Before you run it
--   * The app on `main` reads `users` and `project_cards`, which step 0
--     removes. Point the PWA code (branch `pwa` or `67`) at this project.
--   * It all runs in one transaction: if any statement fails, nothing is
--     changed. Running it a second time stops at "type user_role already
--     exists" for that reason, and leaves the database as it was.
--   * The demo accounts are for a class demo. Anyone who reads this file can
--     sign in as them, so delete them before real users arrive.

begin;

-- ════════════════════════════════════════════════════════════════════════════
-- 0. Remove the earlier sample schema (supabase/migrations/001_initial_schema.sql
--    on the team's main branch). A no-op on a fresh project.
-- ════════════════════════════════════════════════════════════════════════════

drop table if exists
  public.project_cards,
  public.freelancer_profiles,
  public.jobs,
  public.users
cascade;


-- ════════════════════════════════════════════════════════════════════════════
-- supabase/migrations/20260923000000_init.sql
-- ════════════════════════════════════════════════════════════════════════════

-- EyKorBan — initial schema
--
-- Scope: the domain the current UI actually renders (profiles, portfolio work,
-- job posts, reference taxonomies). The project-engagement lifecycle from
-- FR-020..FR-027 of doc/Freelance/Freelance.Requirement.md is deliberately NOT
-- modelled here — it has no UI yet. Add it in a later migration.
--
-- Security model: the browser talks to Postgres directly, so Row Level Security
-- is the backend. Ownership rules from NFR-004 are enforced here, not in React.

-- ─── Extensions ────────────────────────────────────────────────────────────

create extension if not exists "pgcrypto" with schema extensions;

-- ─── Enums ─────────────────────────────────────────────────────────────────

create type public.user_role as enum ('CLIENT', 'FREELANCER', 'ADMIN');
create type public.user_status as enum ('ACTIVE', 'SUSPENDED', 'PENDING_VERIFICATION');
create type public.portfolio_status as enum ('draft', 'published');
create type public.job_status as enum ('open', 'closed');

-- ─── Reference taxonomies ──────────────────────────────────────────────────
-- Text ids (not uuid) so they match the slugs the frontend already ships in
-- src/interface/category.ts and src/components/dropdown.tsx.

create table public.categories (
  id         text primary key,
  name       text not null,
  slug       text not null unique,
  sort_order integer not null default 0
);

create table public.industries (
  id         text primary key,
  name       text not null,
  sort_order integer not null default 0
);

-- ─── Profiles ──────────────────────────────────────────────────────────────
-- One row per auth.users row, created automatically by the trigger below.

create table public.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  name          text not null,
  username      text unique,
  role          public.user_role not null default 'CLIENT',
  email         text not null,
  avatar_url    text,
  status        public.user_status not null default 'ACTIVE',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  last_login_at timestamptz,

  constraint profiles_username_format
    check (username is null or username ~ '^[a-z0-9_]{3,30}$')
);

create index profiles_role_idx on public.profiles (role);
create index profiles_username_idx on public.profiles (username);

create table public.freelancer_profiles (
  user_id                uuid primary key references public.profiles (id) on delete cascade,
  tagline                text,
  bio                    text,
  skills                 text[] not null default '{}',
  hourly_rate            numeric(10, 2),
  currency               text not null default 'USD',
  public_profile_enabled boolean not null default true,
  website_url            text,
  linkedin_url           text,
  github_url             text,
  updated_at             timestamptz not null default now(),

  constraint freelancer_hourly_rate_non_negative
    check (hourly_rate is null or hourly_rate >= 0)
);

create table public.client_profiles (
  user_id         uuid primary key references public.profiles (id) on delete cascade,
  company_name    text,
  billing_address text,
  notes           text,
  updated_at      timestamptz not null default now()
);

-- ─── Portfolio work ────────────────────────────────────────────────────────
-- What the UI calls a "ProjectCard". Named portfolio_item to keep it distinct
-- from the future project-engagement table.

create table public.portfolio_items (
  id              uuid primary key default gen_random_uuid(),
  freelancer_id   uuid not null references public.profiles (id) on delete cascade,
  title           text not null,
  subtitle        text,
  description     text,
  cover_image_url text,
  images          text[] not null default '{}',
  category_id     text references public.categories (id) on delete set null,
  industry_id     text references public.industries (id) on delete set null,
  status          public.portfolio_status not null default 'draft',
  published_at    timestamptz,
  like_count      integer not null default 0,
  view_count      integer not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint portfolio_title_not_blank check (length(btrim(title)) > 0),
  constraint portfolio_counts_non_negative check (like_count >= 0 and view_count >= 0),
  -- FR-010: a published item must carry a publish timestamp for recent-first ordering.
  constraint portfolio_published_has_timestamp
    check (status <> 'published' or published_at is not null)
);

create index portfolio_items_published_idx
  on public.portfolio_items (published_at desc) where status = 'published';
create index portfolio_items_freelancer_idx on public.portfolio_items (freelancer_id);
create index portfolio_items_category_idx on public.portfolio_items (category_id);
create index portfolio_items_industry_idx on public.portfolio_items (industry_id);

-- ─── Job opportunities ─────────────────────────────────────────────────────

create table public.jobs (
  id           uuid primary key default gen_random_uuid(),
  client_id    uuid not null references public.profiles (id) on delete cascade,
  title        text not null,
  description  text not null,
  category_id  text references public.categories (id) on delete set null,
  industry_id  text references public.industries (id) on delete set null,
  status       public.job_status not null default 'open',
  published_at timestamptz not null default now(),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  constraint jobs_title_not_blank check (length(btrim(title)) > 0)
);

create index jobs_open_idx on public.jobs (published_at desc) where status = 'open';
create index jobs_client_idx on public.jobs (client_id);
create index jobs_category_idx on public.jobs (category_id);
create index jobs_industry_idx on public.jobs (industry_id);

-- ─── Triggers ──────────────────────────────────────────────────────────────

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

create trigger freelancer_profiles_set_updated_at
  before update on public.freelancer_profiles
  for each row execute function public.set_updated_at();

create trigger client_profiles_set_updated_at
  before update on public.client_profiles
  for each row execute function public.set_updated_at();

create trigger jobs_set_updated_at
  before update on public.jobs
  for each row execute function public.set_updated_at();

-- Stamp published_at the first time an item is published (FR-010), and clear it
-- when it goes back to draft (FR-011 unpublish).
create or replace function public.sync_portfolio_published_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();

  if new.status = 'published' and new.published_at is null then
    new.published_at = now();
  elsif new.status = 'draft' then
    new.published_at = null;
  end if;

  return new;
end;
$$;

create trigger portfolio_items_sync_published_at
  before insert or update on public.portfolio_items
  for each row execute function public.sync_portfolio_published_at();

-- Every new auth user gets a profile row. Reads name/username/role out of the
-- metadata the signup form sends, and falls back to sane defaults.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  meta_role public.user_role;
begin
  begin
    meta_role := coalesce(
      (new.raw_user_meta_data ->> 'role')::public.user_role,
      'CLIENT'
    );
  exception when others then
    meta_role := 'CLIENT';
  end;

  insert into public.profiles (id, name, username, role, email, avatar_url)
  values (
    new.id,
    coalesce(nullif(btrim(new.raw_user_meta_data ->> 'name'), ''), split_part(new.email, '@', 1)),
    nullif(btrim(new.raw_user_meta_data ->> 'username'), ''),
    meta_role,
    new.email,
    nullif(btrim(new.raw_user_meta_data ->> 'avatar_url'), '')
  )
  on conflict (id) do nothing;

  if meta_role = 'FREELANCER' then
    insert into public.freelancer_profiles (user_id)
    values (new.id)
    on conflict (user_id) do nothing;
  else
    insert into public.client_profiles (user_id)
    values (new.id)
    on conflict (user_id) do nothing;
  end if;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ─── Row Level Security ────────────────────────────────────────────────────

alter table public.categories          enable row level security;
alter table public.industries          enable row level security;
alter table public.profiles            enable row level security;
alter table public.freelancer_profiles enable row level security;
alter table public.client_profiles     enable row level security;
alter table public.portfolio_items     enable row level security;
alter table public.jobs                enable row level security;

-- Taxonomies: read-only reference data for everyone, writable only via the
-- service role (which bypasses RLS entirely).
create policy "categories are readable by everyone"
  on public.categories for select using (true);

create policy "industries are readable by everyone"
  on public.industries for select using (true);

-- Profiles: public directory (Hire Creatives and portfolio author bylines need
-- them without an account). Each user writes only their own row.
create policy "profiles are readable by everyone"
  on public.profiles for select using (true);

create policy "users insert their own profile"
  on public.profiles for insert to authenticated
  with check (auth.uid() = id);

create policy "users update their own profile"
  on public.profiles for update to authenticated
  using (auth.uid() = id) with check (auth.uid() = id);

-- Freelancer profiles: visible when the freelancer opted in, always visible to
-- the owner so they can edit a hidden profile.
create policy "public freelancer profiles are readable"
  on public.freelancer_profiles for select
  using (public_profile_enabled or auth.uid() = user_id);

create policy "freelancers insert their own profile"
  on public.freelancer_profiles for insert to authenticated
  with check (auth.uid() = user_id);

create policy "freelancers update their own profile"
  on public.freelancer_profiles for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Client profiles hold billing details — owner only, never public (NFR-003).
create policy "clients read their own profile"
  on public.client_profiles for select to authenticated
  using (auth.uid() = user_id);

create policy "clients insert their own profile"
  on public.client_profiles for insert to authenticated
  with check (auth.uid() = user_id);

create policy "clients update their own profile"
  on public.client_profiles for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Portfolio work: published items are public (FR-001); drafts are owner-only
-- (FR-009). Writes are owner-only (NFR-004) — enforced here so a forged request
-- fails at the database, not at a hidden button.
create policy "published work is readable by everyone"
  on public.portfolio_items for select
  using (status = 'published' or auth.uid() = freelancer_id);

create policy "freelancers create their own work"
  on public.portfolio_items for insert to authenticated
  with check (auth.uid() = freelancer_id);

create policy "freelancers update their own work"
  on public.portfolio_items for update to authenticated
  using (auth.uid() = freelancer_id) with check (auth.uid() = freelancer_id);

create policy "freelancers delete their own work"
  on public.portfolio_items for delete to authenticated
  using (auth.uid() = freelancer_id);

-- Jobs: open jobs are public (FR-017); a client sees and manages their own
-- closed ones (FR-018).
create policy "open jobs are readable by everyone"
  on public.jobs for select
  using (status = 'open' or auth.uid() = client_id);

create policy "clients create their own jobs"
  on public.jobs for insert to authenticated
  with check (auth.uid() = client_id);

create policy "clients update their own jobs"
  on public.jobs for update to authenticated
  using (auth.uid() = client_id) with check (auth.uid() = client_id);

create policy "clients delete their own jobs"
  on public.jobs for delete to authenticated
  using (auth.uid() = client_id);

-- ─── Storage ───────────────────────────────────────────────────────────────
-- Image-only MVP: portfolio covers and gallery images live here. Each user owns
-- the folder named after their uid, e.g. portfolio-images/<uid>/cover.webp

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'portfolio-images',
  'portfolio-images',
  true,
  5242880, -- 5 MB
  array['image/jpeg', 'image/png', 'image/webp', 'image/avif', 'image/gif']
)
on conflict (id) do nothing;

create policy "portfolio images are publicly readable"
  on storage.objects for select
  using (bucket_id = 'portfolio-images');

create policy "users upload to their own folder"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'portfolio-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "users update their own images"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'portfolio-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "users delete their own images"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'portfolio-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ════════════════════════════════════════════════════════════════════════════
-- supabase/migrations/20260924000000_projects.sql
-- ════════════════════════════════════════════════════════════════════════════

-- EyKorBan — project engagement lifecycle
--
-- Implements STORY-014 … STORY-019 (FR-020 … FR-027): the on-platform object
-- both actors revolve around, with an activity timeline, deliverables, and
-- escrow-simulated payment states.
--
-- SIMULATION: no money moves. payment_status and the fee columns exist so the
-- interface can present a trustworthy middleman model; there is no processor
-- behind them.

-- ─── Enums ─────────────────────────────────────────────────────────────────

-- enquiry → active → delivered → completed, with two terminal exits.
create type public.project_status as enum (
  'enquiry', 'active', 'delivered', 'completed', 'cancelled', 'declined'
);

create type public.payment_status as enum (
  'unfunded', 'held', 'released', 'returned'
);

create type public.project_event_type as enum (
  'created', 'accepted', 'declined', 'funded', 'delivered',
  'revision_requested', 'approved', 'released', 'completed', 'cancelled'
);

-- ─── Projects ──────────────────────────────────────────────────────────────

create table public.projects (
  id             uuid primary key default gen_random_uuid(),
  client_id      uuid not null references public.profiles (id) on delete cascade,
  freelancer_id  uuid not null references public.profiles (id) on delete cascade,

  title          text not null,
  scope          text not null,
  budget         numeric(12, 2) not null,
  currency       text not null default 'USD',
  deadline       date,

  status         public.project_status not null default 'enquiry',
  payment_status public.payment_status not null default 'unfunded',

  -- FR-020: every project is linked to the CTA context it came from. Exactly
  -- one of these is set; free-floating creation is out of scope for the MVP.
  source_portfolio_item_id uuid references public.portfolio_items (id) on delete set null,
  source_job_id            uuid references public.jobs (id) on delete set null,

  -- NFR-008: the 10% fee is computed by the database, so the figure the client
  -- is shown cannot drift from the figure that was agreed.
  platform_fee numeric(12, 2)
    generated always as (round(budget * 0.10, 2)) stored,
  client_total numeric(12, 2)
    generated always as (budget + round(budget * 0.10, 2)) stored,

  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  -- FR-022: the dashboard orders by this.
  last_activity_at timestamptz not null default now(),

  constraint projects_title_not_blank check (length(btrim(title)) > 0),
  constraint projects_scope_not_blank check (length(btrim(scope)) > 0),
  constraint projects_budget_non_negative check (budget >= 0),
  constraint projects_parties_differ check (client_id <> freelancer_id),
  -- FR-020 AC-1: reachable only from a portfolio item or a job.
  constraint projects_has_one_source check (
    (source_portfolio_item_id is not null)::int
    + (source_job_id is not null)::int = 1
  )
);

create index projects_client_idx on public.projects (client_id, last_activity_at desc);
create index projects_freelancer_idx on public.projects (freelancer_id, last_activity_at desc);

-- ─── Deliverables ──────────────────────────────────────────────────────────

create table public.deliverables (
  id           uuid primary key default gen_random_uuid(),
  project_id   uuid not null references public.projects (id) on delete cascade,
  submitted_by uuid not null references public.profiles (id) on delete cascade,
  note         text not null,
  -- Image-only MVP, same rule as portfolio work.
  images       text[] not null default '{}',
  created_at   timestamptz not null default now(),

  constraint deliverables_note_not_blank check (length(btrim(note)) > 0)
);

create index deliverables_project_idx on public.deliverables (project_id, created_at desc);

-- ─── Timeline ──────────────────────────────────────────────────────────────

create table public.project_events (
  id         uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  actor_id   uuid references public.profiles (id) on delete set null,
  type       public.project_event_type not null,
  note       text,
  created_at timestamptz not null default now()
);

-- FR-023 AC-2: chronological with stable ordering when timestamps tie.
create index project_events_timeline_idx
  on public.project_events (project_id, created_at, id);

-- ─── Lifecycle enforcement ─────────────────────────────────────────────────

/*
  State transitions are validated here rather than in the client.

  RLS answers "may this person touch this row?"; it cannot answer "is this a
  legal move, made by the right party?". A client must not accept their own
  enquiry, and a completed project must not reopen. Putting that in a trigger
  means a forged request fails at the database, matching how ownership is
  handled everywhere else in this schema.
*/
create or replace function public.enforce_project_transition()
returns trigger
language plpgsql
as $$
declare
  actor uuid := auth.uid();
begin
  new.updated_at := now();

  if new.status is distinct from old.status then
    new.last_activity_at := now();

    -- Terminal states are terminal.
    if old.status in ('completed', 'cancelled', 'declined') then
      raise exception 'Project is already % and cannot change.', old.status
        using errcode = 'check_violation';
    end if;

    case
      -- FR-021: only the addressed freelancer responds to an enquiry.
      when old.status = 'enquiry' and new.status in ('active', 'declined') then
        if actor is not null and actor <> old.freelancer_id then
          raise exception 'Only the freelancer can respond to this enquiry.'
            using errcode = 'check_violation';
        end if;

      -- FR-024: only the freelancer delivers, and only from active.
      when old.status = 'active' and new.status = 'delivered' then
        if actor is not null and actor <> old.freelancer_id then
          raise exception 'Only the freelancer can submit a deliverable.'
            using errcode = 'check_violation';
        end if;

      -- FR-025: the client approves or sends it back for revision.
      when old.status = 'delivered' and new.status in ('completed', 'active') then
        if actor is not null and actor <> old.client_id then
          raise exception 'Only the client can approve or request a revision.'
            using errcode = 'check_violation';
        end if;

      -- FR-027: either actor may cancel before completion.
      when new.status = 'cancelled' and old.status in ('enquiry', 'active', 'delivered') then
        null;

      else
        raise exception 'Cannot move a project from % to %.', old.status, new.status
          using errcode = 'check_violation';
    end case;
  end if;

  -- FR-026 AC-3: approval releases the held funds. FR-027 AC-4: cancelling a
  -- funded project returns them. Derived here so the two can never disagree.
  if new.status = 'completed' and old.payment_status = 'held' then
    new.payment_status := 'released';
  elsif new.status = 'cancelled' and old.payment_status = 'held' then
    new.payment_status := 'returned';
  end if;

  return new;
end;
$$;

create trigger projects_enforce_transition
  before update on public.projects
  for each row execute function public.enforce_project_transition();

create trigger projects_set_updated_at_on_insert
  before insert on public.projects
  for each row execute function public.set_updated_at();

-- Any deliverable counts as activity, so the dashboard reorders.
create or replace function public.touch_project_activity()
returns trigger
language plpgsql
as $$
begin
  update public.projects
  set last_activity_at = now()
  where id = new.project_id;
  return new;
end;
$$;

create trigger deliverables_touch_project
  after insert on public.deliverables
  for each row execute function public.touch_project_activity();

create trigger project_events_touch_project
  after insert on public.project_events
  for each row execute function public.touch_project_activity();

-- ─── Row Level Security ────────────────────────────────────────────────────
--
-- FR-022 AC-1 / FR-023 AC-4: a project is visible only to its two actors. This
-- is the whole privacy model — not a filter in a React component.

alter table public.projects       enable row level security;
alter table public.deliverables   enable row level security;
alter table public.project_events enable row level security;

create policy "projects are visible to their two actors"
  on public.projects for select to authenticated
  using (auth.uid() = client_id or auth.uid() = freelancer_id);

-- FR-006 / FR-019: the client starts the project from a CTA.
create policy "clients create their own projects"
  on public.projects for insert to authenticated
  with check (auth.uid() = client_id);

-- Either actor may write; which writes are legal is the trigger's job.
create policy "involved actors update their projects"
  on public.projects for update to authenticated
  using (auth.uid() = client_id or auth.uid() = freelancer_id)
  with check (auth.uid() = client_id or auth.uid() = freelancer_id);

create policy "deliverables are visible to the project's actors"
  on public.deliverables for select to authenticated
  using (
    exists (
      select 1 from public.projects p
      where p.id = project_id
        and (auth.uid() = p.client_id or auth.uid() = p.freelancer_id)
    )
  );

create policy "the freelancer submits deliverables"
  on public.deliverables for insert to authenticated
  with check (
    auth.uid() = submitted_by
    and exists (
      select 1 from public.projects p
      where p.id = project_id and p.freelancer_id = auth.uid()
    )
  );

create policy "timeline is visible to the project's actors"
  on public.project_events for select to authenticated
  using (
    exists (
      select 1 from public.projects p
      where p.id = project_id
        and (auth.uid() = p.client_id or auth.uid() = p.freelancer_id)
    )
  );

create policy "involved actors append to the timeline"
  on public.project_events for insert to authenticated
  with check (
    auth.uid() = actor_id
    and exists (
      select 1 from public.projects p
      where p.id = project_id
        and (auth.uid() = p.client_id or auth.uid() = p.freelancer_id)
    )
  );

-- ════════════════════════════════════════════════════════════════════════════
-- supabase/migrations/20260926000000_harden_trigger_functions.sql
-- ════════════════════════════════════════════════════════════════════════════

-- Fixes two findings from the Supabase security advisor, both introduced by the
-- earlier migrations in this project.

/*
  1. handle_new_user() was reachable as an RPC.

  It is SECURITY DEFINER because it must insert into public.profiles on behalf
  of a brand-new auth user. But PostgREST exposes every function in the public
  schema at /rest/v1/rpc/<name>, so it was also callable directly by anon and
  authenticated callers — a definer-rights function exposed to the internet.

  The trigger on auth.users runs as the table owner and does not need EXECUTE
  granted to API roles, so revoking it closes the endpoint without affecting
  signup.
*/
revoke execute on function public.handle_new_user() from anon, authenticated, public;

/*
  2. Mutable search_path on the trigger functions.

  Without a fixed search_path, an unqualified name inside a function resolves
  against whatever the caller's search_path happens to be, which is the classic
  route to hijacking a definer-rights function.
*/
alter function public.handle_new_user() set search_path = public, pg_temp;
alter function public.set_updated_at() set search_path = public, pg_temp;
alter function public.sync_portfolio_published_at() set search_path = public, pg_temp;
alter function public.enforce_project_transition() set search_path = public, pg_temp;
alter function public.touch_project_activity() set search_path = public, pg_temp;

-- ════════════════════════════════════════════════════════════════════════════
-- supabase/migrations/20260926010000_private_email_and_job_projects.sql
-- ════════════════════════════════════════════════════════════════════════════

-- Two fixes, both found while wiring job detail pages (STORY-012).

/* ───────────────────────────────────────────────────────────────────────────
   1. Every user's email was readable by anyone (NFR-003, STORY-012 AC-6).

   public.profiles has a `using (true)` select policy so that bylines and the
   creative directory work without an account. But RLS filters rows, not
   columns — so that policy also published the email column. Any anonymous
   request to /rest/v1/profiles?select=email returned every address, and the
   Find Work page was shipping client emails in its own network payload.

   That is the disintermediation leak S5 was written to prevent: scrape the
   address, take the work off-platform.

   Column privileges fix it at the source. A signed-in user reads their own
   email from their auth session, which is the canonical copy anyway.
   ─────────────────────────────────────────────────────────────────────────── */

revoke select on public.profiles from anon, authenticated;

grant select (
  id, name, username, role, avatar_url, status, created_at, updated_at
) on public.profiles to anon, authenticated;

-- last_login_at is left ungranted too: when someone last signed in is
-- personal activity, and nothing in the interface displays it.

/* ───────────────────────────────────────────────────────────────────────────
   2. STORY-012: a freelancer starts a project from an open job.

   The original insert policy allowed only `auth.uid() = client_id`, so the
   job path was blocked. It was also looser than it looked: a client could name
   any freelancer and cite any portfolio item. The replacement binds the
   counterpart to the source, so neither side can address a project to someone
   the source does not actually belong to.
   ─────────────────────────────────────────────────────────────────────────── */

drop policy if exists "clients create their own projects" on public.projects;

create policy "projects start from a real source, addressed to its owner"
  on public.projects for insert to authenticated
  with check (
    -- STORY-004: a client, from a published portfolio item, to its author.
    (
      auth.uid() = client_id
      and source_portfolio_item_id is not null
      and exists (
        select 1 from public.portfolio_items w
        where w.id = source_portfolio_item_id
          and w.freelancer_id = projects.freelancer_id
          and w.status = 'published'
      )
    )
    or
    -- STORY-012: a freelancer, from an open job, to the client who posted it.
    (
      auth.uid() = freelancer_id
      and source_job_id is not null
      and exists (
        select 1 from public.jobs j
        where j.id = source_job_id
          and j.client_id = projects.client_id
          and j.status = 'open'
      )
      and exists (
        select 1 from public.profiles p
        where p.id = auth.uid() and p.role = 'FREELANCER'
      )
    )
  );

/* ───────────────────────────────────────────────────────────────────────────
   3. Who answers an enquiry depends on who sent it.

   FR-021 was written for the portfolio path, where the client asks and the
   freelancer answers. On the job path the freelancer asks, so the client must
   be the one to accept — otherwise a freelancer could accept their own pitch.
   The initiator is derivable from the source, so no new column is needed.
   ─────────────────────────────────────────────────────────────────────────── */

create or replace function public.enforce_project_transition()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  actor uuid := auth.uid();
  -- The party who did not start the project is the one who responds.
  responder uuid := case
    when old.source_job_id is not null then old.client_id
    else old.freelancer_id
  end;
begin
  new.updated_at := now();

  if new.status is distinct from old.status then
    new.last_activity_at := now();

    if old.status in ('completed', 'cancelled', 'declined') then
      raise exception 'Project is already % and cannot change.', old.status
        using errcode = 'check_violation';
    end if;

    case
      when old.status = 'enquiry' and new.status in ('active', 'declined') then
        if actor is not null and actor <> responder then
          raise exception 'Only the % can respond to this enquiry.',
            case when responder = old.client_id then 'client' else 'freelancer' end
            using errcode = 'check_violation';
        end if;

      when old.status = 'active' and new.status = 'delivered' then
        if actor is not null and actor <> old.freelancer_id then
          raise exception 'Only the freelancer can submit a deliverable.'
            using errcode = 'check_violation';
        end if;

      when old.status = 'delivered' and new.status in ('completed', 'active') then
        if actor is not null and actor <> old.client_id then
          raise exception 'Only the client can approve or request a revision.'
            using errcode = 'check_violation';
        end if;

      when new.status = 'cancelled' and old.status in ('enquiry', 'active', 'delivered') then
        null;

      else
        raise exception 'Cannot move a project from % to %.', old.status, new.status
          using errcode = 'check_violation';
    end case;
  end if;

  if new.status = 'completed' and old.payment_status = 'held' then
    new.payment_status := 'released';
  elsif new.status = 'cancelled' and old.payment_status = 'held' then
    new.payment_status := 'returned';
  end if;

  return new;
end;
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- supabase/seed.sql
-- ════════════════════════════════════════════════════════════════════════════

-- EyKorBan — demo seed
--
-- Ports src/mock-data/mock-data.ts into the database, including real, loggable
-- auth accounts so signed-in states can be exercised without signing up ten
-- times. Every demo account uses the password: password123
--
-- Safe to re-run: it deletes the fixed demo ids first.
-- DEMO DATA ONLY — do not run against production.

-- ─── Reference taxonomies ──────────────────────────────────────────────────
-- Mirrors CATEGORIES in src/interface/category.ts (minus the synthetic "all"
-- entry, which is a filter affordance, not a category).

insert into public.categories (id, name, slug, sort_order) values
  ('it-software',       'IT & Software',          'it-software',         1),
  ('uiux',              'UI/UX Design',           'ui-ux-design',        2),
  ('web-dev',           'Web Development',        'web-development',     3),
  ('mobile-dev',        'Mobile Development',     'mobile-development',  4),
  ('graphic-design',    'Graphic Design',         'graphic-design',      5),
  ('branding',          'Branding & Identity',    'branding-identity',   6),
  ('digital-marketing', 'Digital Marketing',      'digital-marketing',   7),
  ('writing',           'Writing & Translation',  'writing-translation', 8),
  ('video-animation',   'Video & Animation',      'video-animation',     9),
  ('data-analytics',    'Data & Analytics',       'data-analytics',     10),
  ('consulting',        'Consulting',             'consulting',         11)
on conflict (id) do update
  set name = excluded.name, slug = excluded.slug, sort_order = excluded.sort_order;

-- Mirrors DEFAULT_INDUSTRY_OPTIONS in src/components/dropdown.tsx.
insert into public.industries (id, name, sort_order) values
  ('tech',          'Technology & Software',        1),
  ('fintech',       'Fintech & Finance',            2),
  ('ecommerce',     'E-Commerce & Retail',          3),
  ('healthcare',    'Healthcare & Life Sciences',   4),
  ('education',     'Education & EdTech',           5),
  ('real-estate',   'Real Estate & Architecture',   6),
  ('entertainment', 'Media & Entertainment',        7)
on conflict (id) do update
  set name = excluded.name, sort_order = excluded.sort_order;

-- ─── Reset demo rows ───────────────────────────────────────────────────────
-- Deleting the auth users cascades to profiles, portfolio items and jobs.

delete from auth.users
where id in (
  '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002',
  '00000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000004',
  '00000000-0000-4000-8000-000000000005', '00000000-0000-4000-8000-000000000006',
  '00000000-0000-4000-8000-000000000007', '00000000-0000-4000-8000-000000000008',
  '00000000-0000-4000-8000-000000000009', '00000000-0000-4000-8000-000000000010'
);

-- ─── Demo auth accounts ────────────────────────────────────────────────────
-- Writing straight into auth.users is a seeding shortcut, not an app pattern.
-- The public.handle_new_user() trigger picks these up and creates the matching
-- public.profiles row, exactly as a real signup would.

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, last_sign_in_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, recovery_token, email_change, email_change_token_new
)
select
  '00000000-0000-0000-0000-000000000000',
  demo.id, 'authenticated', 'authenticated', demo.email,
  extensions.crypt('password123', extensions.gen_salt('bf')),
  demo.created_at, demo.created_at, demo.updated_at, demo.last_login_at,
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object(
    'name', demo.name,
    'username', demo.username,
    'role', demo.role,
    'avatar_url', demo.avatar_url
  ),
  '', '', '', ''
from (values
  ('00000000-0000-4000-8000-000000000001'::uuid, 'Alex Vance',      'alexvance',      'FREELANCER', 'alex.vance@example.com',     'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150&auto=format&fit=crop&q=80', '2026-01-15T08:30:00Z'::timestamptz, '2026-09-18T10:00:00Z'::timestamptz, '2026-09-19T09:15:00Z'::timestamptz),
  ('00000000-0000-4000-8000-000000000002'::uuid, 'Sarah Chen',      'sarahchen',      'FREELANCER', 'sarah.chen@example.com',     'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=150&auto=format&fit=crop&q=80', '2026-02-10T11:20:00Z'::timestamptz, '2026-09-17T15:00:00Z'::timestamptz, '2026-09-19T11:45:00Z'::timestamptz),
  ('00000000-0000-4000-8000-000000000003'::uuid, 'Marcus Aurelius', 'marcus_design',  'FREELANCER', 'marcus.a@example.com',       'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150&auto=format&fit=crop&q=80', '2026-03-01T09:10:00Z'::timestamptz, '2026-09-16T12:00:00Z'::timestamptz, '2026-09-18T16:30:00Z'::timestamptz),
  ('00000000-0000-4000-8000-000000000004'::uuid, 'David Kim',       'davidkim_cloud', 'FREELANCER', 'david.kim@example.com',      'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=150&auto=format&fit=crop&q=80', '2026-01-20T14:40:00Z'::timestamptz, '2026-09-15T09:00:00Z'::timestamptz, '2026-09-19T08:00:00Z'::timestamptz),
  ('00000000-0000-4000-8000-000000000005'::uuid, 'Elena Rostova',   'elena_arts',     'FREELANCER', 'elena.rostova@example.com',  'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150&auto=format&fit=crop&q=80', '2026-04-12T16:15:00Z'::timestamptz, '2026-09-14T17:00:00Z'::timestamptz, '2026-09-17T20:10:00Z'::timestamptz),
  ('00000000-0000-4000-8000-000000000006'::uuid, 'Liam O''Connor',  'liam_dev',       'FREELANCER', 'liam.oconnor@example.com',   'https://images.unsplash.com/photo-1522075469751-3a6694fb2f61?w=150&auto=format&fit=crop&q=80', '2026-02-28T10:05:00Z'::timestamptz, '2026-09-13T11:00:00Z'::timestamptz, '2026-09-19T10:20:00Z'::timestamptz),
  ('00000000-0000-4000-8000-000000000007'::uuid, 'Maya Patel',      'mayapatel_ui',   'FREELANCER', 'maya.patel@example.com',     'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=150&auto=format&fit=crop&q=80', '2026-03-18T13:25:00Z'::timestamptz, '2026-09-12T14:00:00Z'::timestamptz, '2026-09-19T12:00:00Z'::timestamptz),
  ('00000000-0000-4000-8000-000000000008'::uuid, 'Carlos Mendez',   'carlos_growth',  'FREELANCER', 'carlos.mendez@example.com',  'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=150&auto=format&fit=crop&q=80', '2026-05-05T08:00:00Z'::timestamptz, '2026-09-11T08:00:00Z'::timestamptz, '2026-09-15T14:30:00Z'::timestamptz),
  ('00000000-0000-4000-8000-000000000009'::uuid, 'Sophia Nguyen',   'sophianguyen',   'CLIENT',     'sophia.nguyen@example.com',  'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?w=150&auto=format&fit=crop&q=80', '2026-01-10T07:45:00Z'::timestamptz, '2026-09-10T12:30:00Z'::timestamptz, '2026-09-18T18:00:00Z'::timestamptz),
  ('00000000-0000-4000-8000-000000000010'::uuid, 'Oliver Wright',   'oliverwright',   'ADMIN',      'admin.oliver@eykorban.com',  'https://images.unsplash.com/photo-1519085360753-af0119f7cbe7?w=150&auto=format&fit=crop&q=80', '2025-12-01T09:00:00Z'::timestamptz, '2026-09-09T15:30:00Z'::timestamptz, '2026-09-19T13:00:00Z'::timestamptz)
) as demo (id, name, username, role, email, avatar_url, created_at, updated_at, last_login_at);

-- Email/password sign-in needs a matching identity row.
insert into auth.identities (
  id, provider_id, user_id, identity_data, provider,
  last_sign_in_at, created_at, updated_at
)
select
  gen_random_uuid(), u.id::text, u.id,
  jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
  'email', u.created_at, u.created_at, u.updated_at
from auth.users u
where u.id between '00000000-0000-4000-8000-000000000001' and '00000000-0000-4000-8000-000000000010';

-- ─── Profile details the signup trigger cannot know ────────────────────────

update public.profiles p
set status = 'PENDING_VERIFICATION'
where p.id = '00000000-0000-4000-8000-000000000008';

update public.profiles p
set created_at    = u.created_at,
    last_login_at = u.last_sign_in_at
from auth.users u
where u.id = p.id
  and u.id between '00000000-0000-4000-8000-000000000001' and '00000000-0000-4000-8000-000000000010';

insert into public.freelancer_profiles (
  user_id, tagline, bio, skills, hourly_rate, currency,
  public_profile_enabled, website_url, linkedin_url, github_url
) values
  ('00000000-0000-4000-8000-000000000001',
   'Full-stack engineer for data-heavy web platforms',
   'I design and build web platforms that turn messy data into clear dashboards. Eight years shipping React and Node products for analytics and enterprise teams, from first prototype to production scale.',
   array['React', 'TypeScript', 'Node.js', 'PostgreSQL', 'Data Viz'], 85, 'USD', true,
   'https://alexvance.dev', null, 'https://github.com/alexvance'),
  ('00000000-0000-4000-8000-000000000002',
   'Mobile designer and developer for fintech',
   'I make money apps people actually trust. I work across product design and native development, so the handoff between Figma and Swift or Kotlin never gets lost.',
   array['Swift', 'Kotlin', 'React Native', 'Fintech UX'], 95, 'USD', true,
   null, 'https://linkedin.com/in/sarahchen', null),
  ('00000000-0000-4000-8000-000000000003',
   'Brand identity designer for creative studios',
   'Identity systems with a point of view. I help studios and agencies find a visual voice, then document it so the whole team can use it.',
   array['Branding', 'Logo Design', 'Typography', 'Art Direction'], 70, 'USD', true,
   'https://marcus.design', null, null),
  ('00000000-0000-4000-8000-000000000004',
   'Cloud architect moving teams to AWS and GCP',
   'I plan and run cloud migrations with zero-downtime cutovers, then leave teams with infrastructure as code they can own.',
   array['AWS', 'Terraform', 'Kubernetes', 'DevOps'], 110, 'USD', true,
   null, 'https://linkedin.com/in/davidkim', null),
  ('00000000-0000-4000-8000-000000000005',
   'Editorial designer with a Bauhaus streak',
   'Grids, bold type and primary colours. I design magazines, reports and editorial systems for print and screen.',
   array['Editorial Design', 'Layout', 'Print', 'Illustration'], 65, 'USD', true,
   'https://elenarostova.art', null, null),
  ('00000000-0000-4000-8000-000000000006',
   'Creative developer for luxury e-commerce',
   'I build storefronts that feel like the brand: smooth motion, fast pages and checkout flows that convert.',
   array['Shopify', 'Next.js', 'GSAP', 'Three.js'], 80, 'USD', true,
   null, null, 'https://github.com/liamdev'),
  ('00000000-0000-4000-8000-000000000007',
   'UI/UX designer for AI and developer tools',
   'I simplify complex tools. Most of my work is design systems and interaction design for AI products and developer platforms.',
   array['Figma', 'Design Systems', 'Prototyping', 'User Research'], 90, 'USD', true,
   'https://mayapatel.design', null, null),
  ('00000000-0000-4000-8000-000000000008',
   'Growth marketer turning data into campaigns',
   'Campaign strategy backed by numbers. I run SEO, paid acquisition and reporting for early-stage brands.',
   array['SEO', 'Paid Ads', 'Analytics', 'Copywriting'], 60, 'USD', true,
   null, 'https://linkedin.com/in/carlosmendez', null)
on conflict (user_id) do update set
  tagline                = excluded.tagline,
  bio                    = excluded.bio,
  skills                 = excluded.skills,
  hourly_rate            = excluded.hourly_rate,
  currency               = excluded.currency,
  public_profile_enabled = excluded.public_profile_enabled,
  website_url            = excluded.website_url,
  linkedin_url           = excluded.linkedin_url,
  github_url             = excluded.github_url;

-- ─── Portfolio work ────────────────────────────────────────────────────────
-- Industry ids are new here: the mock ProjectCard had no industry, so the
-- industry filter on the home page had nothing to filter on.

insert into public.portfolio_items (
  id, freelancer_id, title, subtitle, cover_image_url, category_id, industry_id,
  status, published_at, like_count, view_count, created_at
) values
  ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000001',
   'Aether Data Platform v2.0', 'Enterprise Web Platform',
   'https://images.unsplash.com/photo-1551288049-bebda4e38f71?w=800&auto=format&fit=crop&q=80',
   'web-dev', 'tech', 'published', '2026-09-18T09:00:00Z', 428, 12400, '2026-09-18T09:00:00Z'),
  ('10000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000002',
   'Nexus Pay — Wealth & Transfers', 'iOS & Android App',
   'https://images.unsplash.com/photo-1563986768609-322da13575f3?w=800&auto=format&fit=crop&q=80',
   'mobile-dev', 'fintech', 'published', '2026-09-17T14:30:00Z', 812, 28100, '2026-09-17T14:30:00Z'),
  ('10000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000003',
   'Kroma Creative Studio Identity', 'Brand Architecture',
   'https://images.unsplash.com/photo-1600132806370-bf17e65e942f?w=800&auto=format&fit=crop&q=80',
   'branding', 'entertainment', 'published', '2026-09-16T11:15:00Z', 540, 15300, '2026-09-16T11:15:00Z'),
  ('10000000-0000-4000-8000-000000000004', '00000000-0000-4000-8000-000000000004',
   'Cloud Infrastructure Migration', 'DevOps & IT Consulting',
   'https://images.unsplash.com/photo-1558494949-ef010cbdcc31?w=800&auto=format&fit=crop&q=80',
   'it-software', 'tech', 'published', '2026-09-15T08:45:00Z', 1200, 34700, '2026-09-15T08:45:00Z'),
  ('10000000-0000-4000-8000-000000000005', '00000000-0000-4000-8000-000000000005',
   'Bauhaus Redux Editorial System', 'Print & Poster Design',
   'https://images.unsplash.com/photo-1541701494587-cb58502866ab?w=800&auto=format&fit=crop&q=80',
   'graphic-design', 'entertainment', 'published', '2026-09-14T16:20:00Z', 389, 9800, '2026-09-14T16:20:00Z'),
  ('10000000-0000-4000-8000-000000000006', '00000000-0000-4000-8000-000000000006',
   'Maison Vesper Fragrances', 'Shopify & Headless Commerce',
   'https://images.unsplash.com/photo-1592945403244-b3fbafd7f539?w=800&auto=format&fit=crop&q=80',
   'web-dev', 'ecommerce', 'published', '2026-09-13T10:05:00Z', 714, 22600, '2026-09-13T10:05:00Z'),
  ('10000000-0000-4000-8000-000000000007', '00000000-0000-4000-8000-000000000007',
   'Synapse Studio — Node AI', 'Complex App UX',
   'https://images.unsplash.com/photo-1581291518857-4e27b48ff24e?w=800&auto=format&fit=crop&q=80',
   'uiux', 'tech', 'published', '2026-09-12T13:40:00Z', 960, 31000, '2026-09-12T13:40:00Z'),
  ('10000000-0000-4000-8000-000000000008', '00000000-0000-4000-8000-000000000008',
   'Q3 Growth Campaign Report', 'Digital Marketing & Analytics',
   'https://images.unsplash.com/photo-1460925895917-afdab827c52f?w=800&auto=format&fit=crop&q=80',
   'digital-marketing', 'ecommerce', 'published', '2026-09-11T07:50:00Z', 1500, 41200, '2026-09-11T07:50:00Z'),
  ('10000000-0000-4000-8000-000000000009', '00000000-0000-4000-8000-000000000009',
   'Wanderlust Travel App Redesign', 'Mobile UX Case Study',
   'https://images.unsplash.com/photo-1488646953014-85cb44e25828?w=800&auto=format&fit=crop&q=80',
   'uiux', 'entertainment', 'published', '2026-09-10T12:10:00Z', 623, 18900, '2026-09-10T12:10:00Z'),
  ('10000000-0000-4000-8000-000000000010', '00000000-0000-4000-8000-000000000010',
   'Verdant Botanicals Brand Launch', 'Product Copy & Content',
   'https://images.unsplash.com/photo-1544716278-ca5e3f4abd8c?w=800&auto=format&fit=crop&q=80',
   'writing', 'ecommerce', 'published', '2026-09-09T15:25:00Z', 275, 7600, '2026-09-09T15:25:00Z'),
  -- A draft, so the owner-only draft path (FR-009) has something to show.
  ('10000000-0000-4000-8000-000000000011', '00000000-0000-4000-8000-000000000001',
   'Helios Reporting Suite (work in progress)', 'Analytics Dashboard',
   'https://images.unsplash.com/photo-1551288049-bebda4e38f71?w=800&auto=format&fit=crop&q=80',
   'data-analytics', 'tech', 'draft', null, 0, 0, '2026-09-20T09:00:00Z');

-- ─── Job opportunities ─────────────────────────────────────────────────────

insert into public.jobs (
  id, client_id, title, description, category_id, industry_id, status, published_at, created_at
) values
  ('20000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000009',
   'Landing page for a fintech savings app',
   'We are launching a round-up savings app and need a high-converting landing page with a clear signup flow. Design and build in React; copy is ready.',
   'web-dev', 'fintech', 'open', '2026-09-19T08:00:00Z', '2026-09-19T08:00:00Z'),
  ('20000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000009',
   'Brand identity for an organic skincare line',
   'New skincare brand looking for a full identity: logo, colour palette, typography and packaging direction for five products. Earthy, calm and premium.',
   'branding', 'ecommerce', 'open', '2026-09-18T13:30:00Z', '2026-09-18T13:30:00Z'),
  ('20000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000009',
   'iOS app redesign for a telehealth startup',
   'Our booking and video-visit flows are dated and confusing for older patients. We need a redesign focused on accessibility, then help implementing it in SwiftUI.',
   'mobile-dev', 'healthcare', 'open', '2026-09-17T10:15:00Z', '2026-09-17T10:15:00Z'),
  ('20000000-0000-4000-8000-000000000004', '00000000-0000-4000-8000-000000000009',
   'Attendance dashboard for a school network',
   'Build a dashboard that shows attendance trends across twelve schools, with filters by grade and term. Data comes from a CSV export updated weekly.',
   'data-analytics', 'education', 'open', '2026-09-16T09:00:00Z', '2026-09-16T09:00:00Z'),
  ('20000000-0000-4000-8000-000000000005', '00000000-0000-4000-8000-000000000009',
   'Explainer video for a property listing platform',
   'A 60-second animated explainer showing how buyers find and book viewings on our platform. Script is drafted; we need storyboard, animation and voice-over.',
   'video-animation', 'real-estate', 'open', '2026-09-15T16:45:00Z', '2026-09-15T16:45:00Z'),
  ('20000000-0000-4000-8000-000000000006', '00000000-0000-4000-8000-000000000009',
   'Design system audit for a SaaS product',
   'Our Figma library has drifted from the code. Audit components, document the gaps and propose a cleaned-up set of tokens and core components.',
   'uiux', 'tech', 'open', '2026-09-14T11:20:00Z', '2026-09-14T11:20:00Z'),
  ('20000000-0000-4000-8000-000000000007', '00000000-0000-4000-8000-000000000009',
   'SEO content plan for an online bookstore',
   'Plan and write twelve long-form articles around reading lists and gift guides, with keyword research and internal linking recommendations.',
   'writing', 'ecommerce', 'open', '2026-09-12T07:30:00Z', '2026-09-12T07:30:00Z'),
  ('20000000-0000-4000-8000-000000000008', '00000000-0000-4000-8000-000000000009',
   'Podcast cover art and social templates',
   'Cover art for a weekly film podcast plus editable templates for episode announcements on Instagram and YouTube.',
   'graphic-design', 'entertainment', 'closed', '2026-09-10T15:00:00Z', '2026-09-10T15:00:00Z');

commit;
