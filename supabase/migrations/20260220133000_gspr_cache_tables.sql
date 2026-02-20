create extension if not exists pgcrypto;

-- Replace legacy GSPR cache shape with MDR Annex-I derived cache tables.
drop table if exists public.gspr_impacts;
drop table if exists public.gspr_links;
drop table if exists public.gspr_requirements;

create table if not exists public.gspr_requirements (
  id uuid primary key default gen_random_uuid(),
  reg_slug text not null,
  source_version_id uuid references public.legal_versions(id) on delete set null,
  gspr_code text not null,
  title text,
  requirement_text text not null,
  requirement_hash text not null,
  sort_order int not null default 0,
  source_section_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (reg_slug, source_version_id, gspr_code)
);

create index if not exists idx_gspr_req_reg_slug on public.gspr_requirements(reg_slug);
create index if not exists idx_gspr_req_source_version_id on public.gspr_requirements(source_version_id);
create index if not exists idx_gspr_req_code on public.gspr_requirements(gspr_code);

create table if not exists public.gspr_assessments (
  id uuid primary key default gen_random_uuid(),
  td_id text not null,
  gspr_code text not null,
  status text not null default 'open',
  justification text,
  evidence_refs jsonb,
  updated_by uuid,
  updated_at timestamptz not null default now(),
  unique (td_id, gspr_code)
);

create index if not exists idx_gspr_assess_td on public.gspr_assessments(td_id);
create index if not exists idx_gspr_assess_code on public.gspr_assessments(gspr_code);

alter table public.gspr_requirements enable row level security;
alter table public.gspr_assessments enable row level security;

-- gspr_requirements: authenticated read, service role write.
drop policy if exists "auth read gspr_requirements" on public.gspr_requirements;
create policy "auth read gspr_requirements"
on public.gspr_requirements
for select
to authenticated
using (true);

drop policy if exists "service write gspr_requirements" on public.gspr_requirements;
create policy "service write gspr_requirements"
on public.gspr_requirements
for all
to service_role
using (true)
with check (true);

-- gspr_assessments: authenticated read/write (app-layer portal permissions), service role full access.
drop policy if exists "auth read gspr_assessments" on public.gspr_assessments;
create policy "auth read gspr_assessments"
on public.gspr_assessments
for select
to authenticated
using (true);

drop policy if exists "auth write gspr_assessments" on public.gspr_assessments;
create policy "auth write gspr_assessments"
on public.gspr_assessments
for insert
to authenticated
with check (true);

drop policy if exists "auth update gspr_assessments" on public.gspr_assessments;
create policy "auth update gspr_assessments"
on public.gspr_assessments
for update
to authenticated
using (true)
with check (true);

drop policy if exists "service all gspr_assessments" on public.gspr_assessments;
create policy "service all gspr_assessments"
on public.gspr_assessments
for all
to service_role
using (true)
with check (true);
