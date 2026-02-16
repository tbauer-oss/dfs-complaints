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

- In Vercel, set `DATABASE_URL` to a Supabase Postgres endpoint (direct `5432` or transaction pooler `6543`).
- Do **not** append `?sslmode=...` or `?uselibpqcompat=...` to `DATABASE_URL`; SSL is handled by `api/_lib/db.js`.

## 1) Set environment variables

```bash
export DATABASE_URL='postgresql://postgres.<project-ref>:<password>@aws-0-<region>.pooler.supabase.com:6543/postgres'
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

Supported `DATABASE_URL` formats:

- Supabase Direct (port `5432`):

  ```bash
  postgresql://postgres:<password>@db.<project-ref>.supabase.co:5432/postgres
  ```

- Supabase Transaction Pooler (port `6543`, username includes project ref):

  ```bash
  postgresql://postgres.<project-ref>:<password>@aws-0-<region>.pooler.supabase.com:6543/postgres
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
- `DATABASE_URL` (direct `:5432` or transaction pooler `:6543`, without `sslmode` query params)
- `JWT_SECRET`

In Vercel, set `DATABASE_URL` in the **Production** environment, then redeploy so runtime instances pick up the new value.

Then smoke-test portal login.

## 6) One-time cleanup of legacy portal user KV keys

```bash
node scripts/cleanup_legacy_portal_user_keys.js
```

Behavior:
- Removes legacy keys matching `dfs:portal:user:%` from `kv_store`.
- Use `--dry-run` (or `DRY_RUN=1`) to count matching keys without deleting.
- Run once after DB-backed auth is live so no legacy `password_hash` payloads remain in KV.

