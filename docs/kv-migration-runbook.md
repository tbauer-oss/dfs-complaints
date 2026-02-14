# Upstash → Supabase Postgres migration runbook

## 1) Required environment variables

```bash
export DATABASE_URL='postgresql://...'
export UPSTASH_REDIS_REST_URL='https://<upstash-host>'
export UPSTASH_REDIS_REST_TOKEN='<token>'
```

## 2) Apply DB migrations

```bash
npx prisma migrate deploy
```

This applies `kv_store`, `portal_users`, and the password-hash safety constraint (`password_hash IS NULL OR length(password_hash) >= 50`).

## 3) Inventory Upstash keys

```bash
node scripts/list_upstash_keys.js
```

Scans `dfs:*` with Upstash REST `SCAN` and reports counts by prefix (`dfs:portal:user:`, `dfs:user:`, `dfs:reps:`, `dfs:wiki:`, `dfs:td:`, ...).

## 4) Migrate Upstash KV → Supabase kv_store (pipeline)

```bash
node scripts/migrate_upstash_to_supabase_kv_pipeline.js
```

- Uses `SCAN` (`count=1000`) and Upstash `/pipeline` batches (`GET` batch size `100`).
- Parses JSON strings where possible, otherwise keeps raw string values.
- Writes to `kv_store` via `createKvRedisCompat` so existing upsert behavior is reused.

## 5) Migrate portal users from KV → portal_users

```bash
node scripts/migrate_portal_users_from_kv.js
```

Notes:
- Default source is Supabase `kv_store` keys `dfs:portal:user:*`.
- Optional fallback source: `node scripts/migrate_portal_users_from_kv.js --source-upstash`.
- Hash safety: empty hash values are converted to `NULL` and **never** overwrite a non-empty existing hash.
- Role and active flags are migrated; roles can come from user objects and known role key patterns.
- Script prints inserted/updated/skipped counts and missing-hash count.

## 6) Verification SQL helpers

### Users with missing hashes
```sql
select id, email, role, is_active, created_at, updated_at
from portal_users
where password_hash is null or length(trim(password_hash)) = 0
order by updated_at desc;
```

### Count portal keys in kv_store
```sql
select count(*) as portal_kv_keys
from kv_store
where k like 'dfs:portal:user:%'
  and (expires_at is null or expires_at > now());
```

### Compare migrated portal users count
```sql
select count(*) as portal_users_count from portal_users;
```

## 7) Smoke test portal login

```bash
curl -i -X POST "https://<your-domain>/api/portal/login" \
  -H "content-type: application/json" \
  --data '{"email":"<existing-user-email>","password":"<existing-password>"}'
```

Expected: `HTTP 200` with token + user payload.
