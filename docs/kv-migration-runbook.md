# Upstash → Supabase Postgres KV migration runbook

## 0) Preconditions

- `kv_store` migration exists at `prisma/migrations/20260215090000_kv_store/migration.sql` and includes:
  - `k text primary key`
  - `v jsonb not null`
  - `expires_at timestamptz`
  - indexes on `expires_at` and `left(k, 48)`
  - `updated_at` trigger
- Apply migrations before migration runs:

```bash
npx prisma migrate deploy
```

- In Vercel, set `DATABASE_URL` to the **Supabase Transaction Pooler** endpoint on port **6543** (not direct 5432).

## 1) Set environment variables

```bash
export DATABASE_URL='postgresql://...:6543/postgres?sslmode=require'
export UPSTASH_REDIS_REST_URL='https://<upstash-host>'
export UPSTASH_REDIS_REST_TOKEN='<token>'

# Optional knobs
export MIGRATE_PATTERNS='dfs:*,chat:*'
export SCAN_COUNT='1000'
export PIPELINE_BATCH='100'
export TTL_MODE='none'                # or best-effort
export TTL_PIPELINE_BATCH='100'
export DRY_RUN='0'                    # set to 1 for scan/count only
# export START_CURSOR_MAP='{"dfs:*":"0","chat:*":"12345"}'
# export STOP_AFTER='1000'
```

## 2) Run full key-preserving migration

```bash
node scripts/migrate_upstash_to_supabase_kv_full.js
```

Behavior:
- Migrates all configured patterns (`dfs:*`, `chat:*` by default).
- Preserves key names exactly.
- Reads values via Upstash `/pipeline` GET batching.
- Parses JSON strings into objects/arrays before write; otherwise stores raw strings.
- Writes to Postgres `kv_store` through `api/_lib/redis.js` adapter (`redis.set`) with upsert semantics.
- Resumable via per-pattern cursor map printed at end.
- Idempotent on re-run.
- Never logs key values.
- Retries transient Upstash failures with exponential backoff.
- Aborts on Upstash “max requests limit exceeded” and prints resume cursor map.

## 3) Verify migration completeness

```bash
node scripts/verify_kv_migration.js
```

Prints:
- `upstash_total`
- `supabase_total`
- `diff`
- prefix breakdown from `kv_store` (`split_part(k, ':', 1)`).

## 4) Portal users backfill (without hash clobber)

```bash
node scripts/migrate_portal_users_from_kv.js
```

Behavior:
- Reads `kv_store` keys matching `dfs:portal:user:%`.
- Upserts into `portal_users`.
- Never overwrites existing `password_hash` with empty/null values.
- Preserves role and active flag semantics.

## 5) Deploy

Deploy with:
- `DATABASE_URL` (Supabase transaction pooler `:6543`)
- `JWT_SECRET`

Then smoke-test portal login.
