create extension if not exists "pgcrypto";

create table if not exists portal_users (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  email_norm text not null unique,
  password_hash text not null,
  role text not null default 'user',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_portal_users_role on portal_users(role);

create or replace function portal_users_set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_portal_users_updated_at on portal_users;
create trigger trg_portal_users_updated_at
before update on portal_users
for each row execute function portal_users_set_updated_at();
