# Upstash → Supabase Postgres KV migration

## Step 1: Inventory of Redis methods used in this repo
Used methods (from `rg -o "redis\.([a-zA-Z0-9_]+)" api scripts` and manual review):

- `get`
- `set`
- `del`
- `mget`
- `scan`
- `keys`
- `pipeline`
- `incr`
- `expire`
- `ttl`
- `exists`
- `hset`
- `hget`
- `hgetall`
- `hdel`
- `sadd`
- `smembers`
- `srem`
- `sismember`
- `rpush`
- `lrange`
- `zadd`
- `zrem`
- `zrange`
- `zrevrange`
- `zrangebyscore`
- `zcard`
- `ping`

## Step 2: Database migration
Apply prisma migration `20260215090000_kv_store`.

## Step 3: Environment variables (Vercel)
Required:
- `DATABASE_URL`
- `JWT_SECRET`

No Upstash variables are required anymore.

## Step 4: Optional historical key migration
Run:

```bash
node scripts/migrate_upstash_to_supabase_kv.js
```

If Upstash variables are missing, the script exits with a skip message.

## Verification checklist
- [ ] `DATABASE_URL` configured in Vercel project.
- [ ] Prisma migration applied.
- [ ] API starts without any `UPSTASH_*` env vars.
- [ ] `node scripts/test_kv_store_basic.js` passes.
- [ ] Portal login works.
- [ ] Representative/customer endpoint using KV still works.

## Curl smoke tests
### 1) Portal login
```bash
curl -i -X POST "https://<your-domain>/api/portal/login" \
  -H "content-type: application/json" \
  --data '{"email":"<user>","password":"<password>"}'
```

### 2) KV-backed rep endpoint
```bash
curl -i "https://<your-domain>/api/rep/customers" \
  -H "authorization: Bearer <rep-jwt>"
```
