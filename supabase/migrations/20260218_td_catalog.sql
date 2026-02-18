-- TD catalog backing tables
create table if not exists public.td_catalog (
  td_key text primary key,
  product_group text null,
  title text null,
  mdr_classification text null,
  active boolean not null default true,
  source_row jsonb null,
  updated_at timestamptz not null default now()
);

create index if not exists idx_td_catalog_active on public.td_catalog (active);

create table if not exists public.td_catalog_meta (
  id integer generated always as identity primary key,
  source_hash text not null,
  source_updated_at timestamptz not null default now(),
  row_count integer not null,
  last_build_ms integer null,
  last_error text null
);

create index if not exists idx_td_catalog_meta_updated_at on public.td_catalog_meta (source_updated_at desc);
