alter table if exists portal_users
  add column if not exists tour_seen boolean not null default false,
  add column if not exists tour_seen_at timestamptz null;

create index if not exists idx_portal_users_tour_seen on portal_users(tour_seen);
