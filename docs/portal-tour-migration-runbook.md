# Portal onboarding tour migration runbook

## 1) Apply SQL migration in Supabase

Open **Supabase → SQL Editor** for production and run:

```sql
ALTER TABLE public.portal_users
  ADD COLUMN IF NOT EXISTS tour_seen boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS tour_seen_at timestamptz NULL,
  ADD COLUMN IF NOT EXISTS tour_version integer NOT NULL DEFAULT 1;
```

## 2) Verify schema

Run:

```sql
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'portal_users'
  AND column_name IN ('tour_seen', 'tour_seen_at', 'tour_version')
ORDER BY column_name;
```

Expected:
- `tour_seen` exists, `boolean`, `NOT NULL`, default `false`.
- `tour_seen_at` exists (`timestamp with time zone`), nullable.
- `tour_version` exists (`integer`), default `1`.

## 3) Redeploy API

Redeploy the backend so new error handling and fallback queries are active.

## 4) Smoke test

- Call `POST /api/portal/login` with a valid portal account.
- Confirm response includes `tourSeen` and no `STORE_UNAVAILABLE`.
- If migration is missing, API now returns `500` + `SCHEMA_MISMATCH` (`Database migration missing`).
