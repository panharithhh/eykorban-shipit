-- A project always pairs a client with a freelancer.
--
-- The portfolio path of the insert policy checked that the caller was the
-- project's client_id, but not that the caller was a client. A freelancer
-- could name themselves as the client on another freelancer's work and open
-- a project between two freelancers. The job path already checked the
-- caller's role; this gives the portfolio path the same check.

drop policy if exists "projects start from a real source, addressed to its owner"
  on public.projects;

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
      and exists (
        select 1 from public.profiles p
        where p.id = auth.uid() and p.role = 'CLIENT'
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
