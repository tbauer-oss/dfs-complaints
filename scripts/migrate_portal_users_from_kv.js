#!/usr/bin/env node
import { query } from '../api/_lib/db.js';
import { normalizeEmail } from '../api/_lib/identity.js';

const args = process.argv.slice(2);
const hasArg = (name) => args.includes(`--${name}`);
const SOURCE = hasArg('source-upstash') ? 'upstash' : 'kv_store';

const UPSTASH_URL = String(process.env.UPSTASH_REDIS_REST_URL || '').replace(/\/$/, '');
const UPSTASH_TOKEN = String(process.env.UPSTASH_REDIS_REST_TOKEN || '').trim();

if (!String(process.env.DATABASE_URL || '').trim()) {
  console.error('[migrate_portal_users_from_kv] missing DATABASE_URL');
  process.exit(1);
}
if (SOURCE === 'upstash' && (!UPSTASH_URL || !UPSTASH_TOKEN)) {
  console.error('[migrate_portal_users_from_kv] --source-upstash requires UPSTASH_REDIS_REST_URL and UPSTASH_REDIS_REST_TOKEN');
  process.exit(1);
}

function normalizeHash(raw) {
  const value = String(raw || '').trim();
  return value.length > 0 ? value : null;
}

function parseStoredValue(rowValue) {
  if (!rowValue || typeof rowValue !== 'object') return rowValue;
  if (rowValue.__type === 'string') return rowValue.value ?? null;
  return rowValue;
}

function parseRoleValue(value) {
  if (!value) return '';
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (!trimmed) return '';
    try {
      const asJson = JSON.parse(trimmed);
      if (asJson && typeof asJson === 'object' && asJson.role) return String(asJson.role).trim().toLowerCase();
    } catch {}
    return trimmed.toLowerCase();
  }
  if (typeof value === 'object' && value.role) return String(value.role).trim().toLowerCase();
  return '';
}

function mapPortalUser(key, parsedValue, roleByEmail) {
  const keyEmail = normalizeEmail(String(key).slice('dfs:portal:user:'.length));
  let value = parsedValue;
  if (typeof value === 'string') {
    try { value = JSON.parse(value); } catch { return null; }
  }
  if (!value || typeof value !== 'object') return null;

  const emailNorm = normalizeEmail(value.email || value.mail || keyEmail);
  if (!emailNorm) return null;

  const roleFromObject = String(value.role || '').trim().toLowerCase();
  const role = roleFromObject || roleByEmail.get(emailNorm) || 'user';
  const passwordHash = normalizeHash(value.password_hash || value.passwordHash || value.hash || value.passhash || value.passHash);

  const portalStatus = String(value.portalStatus || value.status || '').trim().toLowerCase();
  const isActive = portalStatus
    ? portalStatus !== 'inactive'
    : !(value.active === false || value.isActive === false || value.is_active === false);

  return {
    email: String(value.email || emailNorm).trim(),
    email_norm: emailNorm,
    password_hash: passwordHash,
    role,
    is_active: isActive,
    created_at: value.createdAt || null,
    updated_at: value.updatedAt || null,
  };
}

async function upsertPortalUser(user) {
  const result = await query(
    `INSERT INTO portal_users (email, email_norm, password_hash, role, is_active, created_at, updated_at)
     VALUES (
       $1,
       $2,
       NULLIF($3, ''),
       $4,
       $5,
       COALESCE($6::timestamptz, NOW()),
       COALESCE($7::timestamptz, NOW())
     )
     ON CONFLICT (email_norm)
     DO UPDATE SET
       email = EXCLUDED.email,
       password_hash = CASE
         WHEN EXCLUDED.password_hash IS NOT NULL AND length(EXCLUDED.password_hash) > 0 THEN EXCLUDED.password_hash
         ELSE portal_users.password_hash
       END,
       role = EXCLUDED.role,
       is_active = EXCLUDED.is_active,
       updated_at = NOW()
     RETURNING (xmax = 0) AS inserted,
               CASE
                 WHEN password_hash IS NULL OR length(password_hash) = 0 THEN true
                 ELSE false
               END AS hash_missing`,
    [
      user.email,
      user.email_norm,
      user.password_hash,
      user.role,
      user.is_active,
      user.created_at,
      user.updated_at,
    ],
  );
  return result.rows?.[0] || { inserted: false, hash_missing: false };
}


async function markResetRequired(emailNorm) {
  await query(
    `INSERT INTO kv_store (k, v, expires_at, updated_at)
     VALUES ($1, $2::jsonb, NULL, NOW())
     ON CONFLICT (k)
     DO UPDATE SET v = EXCLUDED.v, expires_at = NULL, updated_at = NOW()`,
    [`dfs:portal:password-reset-required:${emailNorm}`, JSON.stringify({ __type: 'string', value: '1' })],
  );
}

async function loadFromKvStore() {
  const users = await query(
    `SELECT k, v
     FROM kv_store
     WHERE k LIKE 'dfs:portal:user:%'
       AND (expires_at IS NULL OR expires_at > NOW())
     ORDER BY k`,
    [],
  );

  const roleRows = await query(
    `SELECT k, v
     FROM kv_store
     WHERE (
       k LIKE 'dfs:portal:role:%'
       OR k LIKE 'dfs:portal:user:role:%'
       OR k LIKE 'dfs:portal:user-role:%'
       OR k LIKE 'dfs:portal:user:%:role'
     )
       AND (expires_at IS NULL OR expires_at > NOW())`,
    [],
  );

  const roleByEmail = new Map();
  for (const row of roleRows.rows || []) {
    const parsed = parseStoredValue(row.v);
    const role = parseRoleValue(parsed);
    if (!role) continue;

    const key = String(row.k || '');
    const match = key.match(/:([^:]+@[^:]+)$/);
    const emailNorm = normalizeEmail(match ? match[1] : '');
    if (emailNorm) roleByEmail.set(emailNorm, role);
  }

  return { rows: users.rows || [], roleByEmail };
}

async function upstashScan(cursor) {
  const url = `${UPSTASH_URL}/scan/${encodeURIComponent(cursor)}?match=${encodeURIComponent('dfs:portal:user:*')}&count=1000`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${UPSTASH_TOKEN}` } });
  if (!res.ok) throw new Error(`scan failed (${res.status})`);
  const body = await res.json();
  if (body?.error) throw new Error(body.error);
  return body?.result;
}

async function upstashPipeline(commands) {
  const res = await fetch(`${UPSTASH_URL}/pipeline`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${UPSTASH_TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(commands),
  });
  if (!res.ok) throw new Error(`pipeline failed (${res.status})`);
  const body = await res.json();
  if (body?.error) throw new Error(body.error);
  return body?.result;
}

async function loadFromUpstash() {
  let cursor = '0';
  const rows = [];
  const roleByEmail = new Map();

  do {
    const scan = await upstashScan(cursor);
    cursor = String(scan?.[0] ?? '0');
    const keys = Array.isArray(scan?.[1]) ? scan[1] : [];
    for (let i = 0; i < keys.length; i += 100) {
      const batch = keys.slice(i, i + 100);
      const results = await upstashPipeline(batch.map((key) => ['GET', key]));
      for (let j = 0; j < batch.length; j += 1) {
        const item = results?.[j];
        if (!item || item.error || item.result == null) continue;
        rows.push({ k: batch[j], v: item.result });
      }
    }
  } while (cursor !== '0');

  return { rows, roleByEmail };
}

async function main() {
  const stats = { scanned: 0, inserted: 0, updated: 0, skipped: 0, missingHashes: 0, resetMarkers: 0 };

  const source = SOURCE === 'upstash' ? await loadFromUpstash() : await loadFromKvStore();

  for (const row of source.rows) {
    stats.scanned += 1;
    const parsed = parseStoredValue(row.v);
    const user = mapPortalUser(row.k, parsed, source.roleByEmail);
    if (!user) {
      stats.skipped += 1;
      continue;
    }

    const result = await upsertPortalUser(user);
    if (result.inserted) stats.inserted += 1;
    else stats.updated += 1;
    if (result.hash_missing) {
      stats.missingHashes += 1;
      await markResetRequired(user.email_norm);
      stats.resetMarkers += 1;
    }
  }

  console.log('[migrate_portal_users_from_kv] done', { source: SOURCE, ...stats });
}

main().catch((err) => {
  console.error('[migrate_portal_users_from_kv] failed', err.message);
  process.exit(1);
});
