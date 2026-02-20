create extension if not exists pgcrypto;

create table if not exists public.legal_documents (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  celex text,
  eli_uri text,
  title text not null,
  current_version_id uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.legal_versions (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.legal_documents(id) on delete cascade,
  version_label text not null,
  consolidation_date date,
  source_url text,
  fetched_at timestamptz not null default now(),
  content_hash text not null,
  unique(document_id, version_label)
);

alter table public.legal_documents
  drop constraint if exists legal_documents_current_version_id_fkey;
alter table public.legal_documents
  add constraint legal_documents_current_version_id_fkey
  foreign key (current_version_id) references public.legal_versions(id) on delete set null;

create table if not exists public.legal_sections (
  id uuid primary key default gen_random_uuid(),
  version_id uuid not null references public.legal_versions(id) on delete cascade,
  section_type text not null,
  section_key text not null,
  heading text,
  content_html text,
  content_text text,
  content_hash text not null,
  sort_order int,
  unique(version_id, section_key)
);

create table if not exists public.legal_changes (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.legal_documents(id) on delete cascade,
  from_version_id uuid references public.legal_versions(id) on delete set null,
  to_version_id uuid references public.legal_versions(id) on delete set null,
  synced_by uuid,
  synced_at timestamptz not null default now(),
  status text not null,
  meta jsonb not null default '{}'::jsonb
);

create table if not exists public.legal_section_changes (
  id uuid primary key default gen_random_uuid(),
  change_id uuid not null references public.legal_changes(id) on delete cascade,
  section_key text not null,
  section_type text,
  change_type text not null,
  old_hash text,
  new_hash text,
  diff_summary text,
  diff_detail jsonb not null default '{}'::jsonb
);

create table if not exists public.gspr_requirements (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  title text not null,
  text text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.gspr_links (
  id uuid primary key default gen_random_uuid(),
  gspr_id uuid not null references public.gspr_requirements(id) on delete cascade,
  document_slug text not null,
  section_key text not null,
  note text,
  unique(gspr_id, document_slug, section_key)
);

create table if not exists public.gspr_impacts (
  id uuid primary key default gen_random_uuid(),
  change_id uuid not null references public.legal_changes(id) on delete cascade,
  gspr_id uuid not null references public.gspr_requirements(id) on delete cascade,
  section_key text not null,
  impact_type text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_legal_sections_version_type_sort on public.legal_sections(version_id, section_type, sort_order);
create index if not exists idx_legal_section_changes_change_type on public.legal_section_changes(change_id, change_type);
create index if not exists idx_gspr_links_doc_section on public.gspr_links(document_slug, section_key);
create index if not exists idx_legal_versions_document_id on public.legal_versions(document_id);
create index if not exists idx_legal_changes_document_id on public.legal_changes(document_id);

alter table public.legal_documents enable row level security;
alter table public.legal_versions enable row level security;
alter table public.legal_sections enable row level security;
alter table public.legal_changes enable row level security;
alter table public.legal_section_changes enable row level security;
alter table public.gspr_requirements enable row level security;
alter table public.gspr_links enable row level security;
alter table public.gspr_impacts enable row level security;

drop policy if exists "auth read legal_documents" on public.legal_documents;
create policy "auth read legal_documents" on public.legal_documents for select to authenticated using (true);
drop policy if exists "auth read legal_versions" on public.legal_versions;
create policy "auth read legal_versions" on public.legal_versions for select to authenticated using (true);
drop policy if exists "auth read legal_sections" on public.legal_sections;
create policy "auth read legal_sections" on public.legal_sections for select to authenticated using (true);
drop policy if exists "auth read legal_changes" on public.legal_changes;
create policy "auth read legal_changes" on public.legal_changes for select to authenticated using (true);
drop policy if exists "auth read legal_section_changes" on public.legal_section_changes;
create policy "auth read legal_section_changes" on public.legal_section_changes for select to authenticated using (true);
drop policy if exists "auth read gspr_requirements" on public.gspr_requirements;
create policy "auth read gspr_requirements" on public.gspr_requirements for select to authenticated using (true);
drop policy if exists "auth read gspr_links" on public.gspr_links;
create policy "auth read gspr_links" on public.gspr_links for select to authenticated using (true);
drop policy if exists "auth read gspr_impacts" on public.gspr_impacts;
create policy "auth read gspr_impacts" on public.gspr_impacts for select to authenticated using (true);

insert into public.legal_documents (slug, celex, title)
values ('mdr-2017-745', '32017R0745', 'Regulation (EU) 2017/745 (MDR)')
on conflict (slug) do update set celex = excluded.celex, title = excluded.title;
