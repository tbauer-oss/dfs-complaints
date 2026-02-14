#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Pool } from 'pg';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const UPSTASH_URL = String(process.env.UPSTASH_REDIS_REST_URL || '').replace(/\/$/, '');
const UPSTASH_TOKEN = String(process.env.UPSTASH_REDIS_REST_TOKEN || '').trim();
const DATABASE_URL = String(process.env.DATABASE_URL || '').trim();

const args = process.argv.slice(2);
const readArg = (name) => {
  const found = args.find((arg) => arg.startsWith(`--${name}=`));
  return found ? found.slice(name.length + 3) : '';
};
const startCursorArg = readArg('cursor');
const countArg = Number(readArg('count') || 200);
const progressFile = readArg('progress') || path.join(__dirname, '.upstash-migration-progress.json');

if (!UPSTASH_URL || !UPSTASH_TOKEN) {
  console.error('[migrate_upstash_to_supabase_full] missing UPSTASH_REDIS_REST_URL or UPSTASH_REDIS_REST_TOKEN');
  process.exit(1);
}
if (!DATABASE_URL) {
  console.error('[migrate_upstash_to_supabase_full] missing DATABASE_URL');
  process.exit(1);
}

function safeKey(key) {
  const k = String(key || '');
  return k.length > 80 ? `${k.slice(0, 77)}...` : k;
}

function normalizeEmail(email) {
  return String(email || '').trim().toLowerCase();
}

async function upstashCall(command, ...parts) {
  const encoded = parts.map((p) => encodeURIComponent(String(p)));
  const url = `${UPSTASH_URL}/${command}/${encoded.join('/')}`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${UPSTASH_TOKEN}` } });
  if (!res.ok) throw new Error(`Upstash ${command} failed (${res.status})`);
  const body = await res.json();
  if (body?.error) throw new Error(`Upstash ${command} error: ${body.error}`);
  return body?.result;
}

async function readProgress() {
  if (startCursorArg) return { cursor: String(startCursorArg) };
  try {
    const raw = await fs.readFile(progressFile, 'utf8');
    const parsed = JSON.parse(raw);
    return { cursor: String(parsed?.cursor || '0') };
  } catch {
    return { cursor: '0' };
  }
}

async function writeProgress(cursor, stats) {
  await fs.writeFile(progressFile, JSON.stringify({ cursor, updatedAt: new Date().toISOString(), stats }, null, 2));
}

function toCanonical(type, value) {
  if (type === 'string') return { __type: 'string', value: value ?? null };
  if (type === 'set') return { __type: 'set', members: Array.isArray(value) ? value : [] };
  if (type === 'hash') return { __type: 'hash', value: value && typeof value === 'object' ? value : {} };
  if (type === 'list') return { __type: 'list', items: Array.isArray(value) ? value : [] };
  if (type === 'zset') return { __type: 'zset', items: Array.isArray(value) ? value : [] };
  return { __type: 'string', value: value ?? null };
}

function portalUserFromKeyValue(key, canonical) {
  if (!String(key).startsWith('dfs:portal:user:')) return null;

  const raw = canonical?.__type === 'string' ? canonical.value : canonical;
  let value = raw;
  if (typeof value === 'string') {
    try { value = JSON.parse(value); } catch { return null; }
  }
  if (!value || typeof value !== 'object') return null;

  const keyEmail = normalizeEmail(String(key).slice('dfs:portal:user:'.length));
  const email = normalizeEmail(value.email || value.mail || keyEmail);
  const passwordHash = String(
    value.password_hash || value.passwordHash || value.passhash || value.passHash || '',
  ).trim();
  const role = String(value.role || 'user').trim().toLowerCase() || 'user';
  const portalStatus = String(value.portalStatus || value.status || '').toLowerCase();
  const isActive = portalStatus ? portalStatus !== 'inactive' : value.is_active !== false && value.isActive !== false;

  if (!email || !passwordHash) return null;

  return { email: value.email || email, email_norm: email, password_hash: passwordHash, role, is_active: isActive };
}

async function readKeyData(key) {
  const typeRaw = await upstashCall('type', key);
  const type = String(typeRaw || '').toLowerCase();
  const ttl = Number(await upstashCall('ttl', key));

  if (type === 'string') {
    const val = await upstashCall('get', key);
    let parsed = val;
    if (typeof val === 'string') {
      try { parsed = JSON.parse(val); } catch {}
    }
    return { canonical: toCanonical('string', parsed), ttl };
  }

  if (type === 'set') {
    const members = await upstashCall('smembers', key);
    return { canonical: toCanonical('set', members || []), ttl };
  }

  if (type === 'hash') {
    const hash = await upstashCall('hgetall', key);
    return { canonical: toCanonical('hash', hash || {}), ttl };
  }

  if (type === 'list') {
    const items = await upstashCall('lrange', key, 0, -1);
    return { canonical: toCanonical('list', items || []), ttl };
  }

  if (type === 'zset') {
    const withScores = await upstashCall('zrange', key, 0, -1, 'withscores');
    const items = [];
    for (let i = 0; i < withScores.length; i += 2) {
      items.push({ member: String(withScores[i]), score: Number(withScores[i + 1]) });
    }
    return { canonical: toCanonical('zset', items), ttl };
  }

  return { canonical: toCanonical('string', null), ttl };
}

async function main() {
  const pool = new Pool({
    connectionString: DATABASE_URL,
    max: Number(process.env.DB_POOL_MAX || 3),
    ssl: DATABASE_URL.includes('localhost') ? false : { rejectUnauthorized: false },
  });

  const client = await pool.connect();
  const stats = {
    scanned: 0,
    migrated: 0,
    portalUsersUpserted: 0,
    byType: { string: 0, set: 0, hash: 0, list: 0, zset: 0, unknown: 0 },
  };

  try {
    let { cursor } = await readProgress();
    console.log(`[migrate_upstash_to_supabase_full] start cursor=${cursor}`);

    do {
      const scanRes = await upstashCall('scan', cursor, 'match', 'dfs:*', 'count', countArg);
      const nextCursor = String(scanRes?.[0] ?? '0');
      const keys = Array.isArray(scanRes?.[1]) ? scanRes[1] : [];
      stats.scanned += keys.length;

      for (const key of keys) {
        const { canonical, ttl } = await readKeyData(key);
        const valueType = String(canonical?.__type || 'unknown').toLowerCase();
        if (!Object.hasOwn(stats.byType, valueType)) stats.byType.unknown += 1;
        else stats.byType[valueType] += 1;

        await client.query(
          `INSERT INTO kv_store (k, v, expires_at)
           VALUES ($1, $2::jsonb, CASE WHEN $3 > 0 THEN NOW() + ($3::text || ' seconds')::interval ELSE NULL END)
           ON CONFLICT (k) DO UPDATE
           SET v = EXCLUDED.v,
               expires_at = EXCLUDED.expires_at,
               updated_at = NOW()`,
          [key, JSON.stringify(canonical), ttl],
        );

        const portalUser = portalUserFromKeyValue(key, canonical);
        if (portalUser) {
          await client.query(
            `INSERT INTO portal_users (email, email_norm, password_hash, role, is_active)
             VALUES ($1, $2, $3, $4, $5)
             ON CONFLICT (email_norm) DO UPDATE
             SET email = EXCLUDED.email,
                 password_hash = EXCLUDED.password_hash,
                 role = EXCLUDED.role,
                 is_active = EXCLUDED.is_active,
                 updated_at = NOW()`,
            [portalUser.email, portalUser.email_norm, portalUser.password_hash, portalUser.role, portalUser.is_active],
          );
          stats.portalUsersUpserted += 1;
        }

        stats.migrated += 1;
        if (stats.migrated % 200 === 0) {
          console.log(`[migrate_upstash_to_supabase_full] migrated=${stats.migrated} lastKey=${safeKey(key)}`);
        }
      }

      cursor = nextCursor;
      await writeProgress(cursor, stats);
      console.log(`[migrate_upstash_to_supabase_full] batch keys=${keys.length} nextCursor=${cursor} total=${stats.migrated}`);
    } while (cursor !== '0');

    console.log('[migrate_upstash_to_supabase_full] done', stats);
    await writeProgress('0', stats);
  } finally {
    client.release();
    await pool.end();
  }
}

main().catch((err) => {
  console.error('[migrate_upstash_to_supabase_full] failed', err.message);
  process.exit(1);
});
