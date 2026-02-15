alter table if exists portal_users
  drop constraint if exists portal_users_email_unique;

alter table if exists portal_users
  add constraint portal_users_email_unique unique (email);

alter table if exists portal_users
  drop constraint if exists portal_users_email_not_legacy_or_example;

alter table if exists portal_users
  add constraint portal_users_email_not_legacy_or_example
  check (
    lower(email) !~ '^legacy\.'
    and position('example.com' in lower(email)) = 0
  );
