# Upstash → Supabase Postgres KV migration runbook

## 1) Apply SQL migration (kv_store + triggers)
Run this against your Supabase Postgres database:

```sql
create table if not exists kv_store (
  k text primary key,
  v jsonb not null,
  expires_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists portal_users (
  id bigserial primary key,
  email text not null,
  email_norm text not null unique,
  password_hash text not null,
  role text not null default 'user',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_kv_store_updated_at on kv_store;
create trigger trg_kv_store_updated_at
before update on kv_store
for each row execute function set_updated_at();

drop trigger if exists trg_portal_users_updated_at on portal_users;
create trigger trg_portal_users_updated_at
before update on portal_users
for each row execute function set_updated_at();
```

## 2) Configure environment variables
Required runtime variables:

- `DATABASE_URL` (Supabase **Transaction Pooler** endpoint recommended, usually port `6543`)
- `JWT_SECRET`

No `UPSTASH_*` variables are required by production runtime.

## 3) Run full migration (Upstash → Supabase)
The migration copies all `dfs:*` keys (string/set/hash/list/zset) with TTL and upserts portal users.

```bash
node scripts/migrate_upstash_to_supabase_full.js
```

Optional flags:

- `--cursor=<cursor>` start from a cursor manually.
- `--progress=<file>` use a custom resumable progress file.
- `--count=<n>` tune SCAN batch size.

The script writes progress to `scripts/.upstash-migration-progress.json` by default.

## 4) Smoke tests

### KV compatibility smoke test
```bash
node scripts/test_kv_store_basic.js
```
Expected:
- Prints `[test_kv_store_basic] ok`.

### Portal login smoke test
```bash
curl -i -X POST "https://<your-domain>/api/portal/login" \
  -H "content-type: application/json" \
  --data '{"email":"<existing-user-email>","password":"<existing-password>"}'
```
Expected:
- `HTTP/1.1 200` with JSON containing `token` and `user`.
- Wrong password returns `401` with `{"code":"INVALID_CREDENTIALS",...}`.

### KV-backed endpoint smoke test (representative store)
```bash
curl -i "https://<your-domain>/api/rep/customers" \
  -H "authorization: Bearer <rep-jwt>"
```
Expected:
- `HTTP/1.1 200` and JSON array response.

## 5) Post-migration checklist
- [ ] `/api` starts with only `DATABASE_URL` + `JWT_SECRET` (no Upstash env).
- [ ] `node scripts/test_kv_store_basic.js` passes.
- [ ] Existing portal users can log in with their historical passwords.
- [ ] Representative/customer KV endpoints still return data.
