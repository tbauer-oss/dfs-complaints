create extension if not exists pgcrypto;

create table if not exists public.td_catalog (
  id uuid primary key default gen_random_uuid(),
  source text not null default 'dfs_products.csv',
  source_hash text not null,
  generated_at timestamptz not null default now(),
  items_json jsonb not null,
  active boolean not null default true
);

alter table public.td_catalog add column if not exists id uuid default gen_random_uuid();
alter table public.td_catalog add column if not exists source text default 'dfs_products.csv';
alter table public.td_catalog add column if not exists source_hash text;
alter table public.td_catalog add column if not exists generated_at timestamptz default now();
alter table public.td_catalog add column if not exists items_json jsonb;
alter table public.td_catalog add column if not exists active boolean default true;

update public.td_catalog
set source = coalesce(source, 'dfs_products.csv'),
    source_hash = coalesce(source_hash, md5(random()::text || clock_timestamp()::text)),
    generated_at = coalesce(generated_at, now()),
    items_json = coalesce(items_json, '[]'::jsonb),
    active = coalesce(active, true)
where source is null or source_hash is null or generated_at is null or items_json is null or active is null;

alter table public.td_catalog alter column source set not null;
alter table public.td_catalog alter column source_hash set not null;
alter table public.td_catalog alter column generated_at set not null;
alter table public.td_catalog alter column items_json set not null;
alter table public.td_catalog alter column active set not null;

create unique index if not exists ux_td_catalog_single_active
  on public.td_catalog (active)
  where active = true;

create index if not exists idx_td_catalog_generated_at_desc
  on public.td_catalog (generated_at desc);
