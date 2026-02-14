alter table if exists portal_users
  alter column password_hash drop not null;

alter table if exists portal_users
  drop constraint if exists portal_users_password_hash_min_length;

alter table if exists portal_users
  add constraint portal_users_password_hash_min_length
  check (password_hash is null or length(password_hash) >= 50);
