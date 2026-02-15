export const config = { runtime: 'nodejs' };

// curl examples:
// curl -sS 'https://<your-host>/api/admin/diag-store' -H 'x-admin-secret: <ADMIN_SECRET>'
// curl -sS 'https://<your-host>/api/admin/diag-store' -H 'Authorization: Bearer <ADMIN_SECRET>'

import { query } from '../_lib/db.js';
import { redis } from '../_lib/redis.js';
import { safeHandler } from '../_lib/http.js';

function asErrorMessage(err) {
  if (!err) return 'unknown error';
  if (typeof err?.message === 'string' && err.message) return err.message;
  return String(err);
}

function parseDbTarget() {
  const value = String(process.env.DATABASE_URL || '').trim();
  if (!value) return '';
  try {
    const parsed = new URL(value);
    const host = parsed.hostname || '';
    const port = parsed.port || '5432';
    const dbName = (parsed.pathname || '').replace(/^\//, '') || '';
    return `${host}:${port}/${dbName}`;
  } catch {
    return '';
  }
}

function isAuthorized(req) {
  const expected = String(process.env.ADMIN_SECRET || '').trim();
  if (!expected) return false;

  const headerSecret = String(req.headers?.['x-admin-secret'] || '').trim();
  if (headerSecret && headerSecret === expected) return true;

  const authorization = String(req.headers?.authorization || '').trim();
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  const bearerSecret = String(match?.[1] || '').trim();
  return !!bearerSecret && bearerSecret === expected;
}

export async function handler(req, res) {
  if (req.method !== 'GET') {
    return res.status(405).json({ ok: false, code: 'METHOD_NOT_ALLOWED' });
  }

  if (!isAuthorized(req)) {
    return res.status(401).json({ ok: false, code: 'UNAUTHORIZED' });
  }

  const diagnostics = {
    ok: false,
    env: {
      hasDatabaseUrl: !!String(process.env.DATABASE_URL || '').trim(),
      hasJwtSecret: !!String(process.env.JWT_SECRET || '').trim(),
    },
    db: {
      ok: false,
      target: parseDbTarget(),
      ms: 0,
    },
    schema: {
      kv_store: { ok: false },
      portal_users: { ok: false },
    },
    kv: {
      setGetDel: { ok: false, ms: 0 },
    },
    portal: {
      lookup: { ok: false, found: false, ms: 0 },
    },
  };

  const dbStarted = Date.now();
  try {
    await query('select 1 as ok');
    diagnostics.db.ok = true;
  } catch (err) {
    diagnostics.db.error = asErrorMessage(err);
  } finally {
    diagnostics.db.ms = Date.now() - dbStarted;
  }

  let hasPortalUsersTable = false;

  try {
    const { rows } = await query("select to_regclass('public.kv_store') as exists");
    const exists = !!rows?.[0]?.exists;
    diagnostics.schema.kv_store.ok = exists;
    if (!exists) diagnostics.schema.kv_store.error = 'table not found';
  } catch (err) {
    diagnostics.schema.kv_store.error = asErrorMessage(err);
  }

  try {
    const { rows } = await query("select to_regclass('public.portal_users') as exists");
    hasPortalUsersTable = !!rows?.[0]?.exists;
    diagnostics.schema.portal_users.ok = hasPortalUsersTable;
    if (!hasPortalUsersTable) diagnostics.schema.portal_users.error = 'table not found';
  } catch (err) {
    diagnostics.schema.portal_users.error = asErrorMessage(err);
  }

  const kvStarted = Date.now();
  try {
    const key = `dfs:diag:ping:${Date.now()}`;
    await redis.set(key, { ok: true }, { ex: 60 });
    await redis.get(key);
    await redis.del(key);
    diagnostics.kv.setGetDel.ok = true;
  } catch (err) {
    diagnostics.kv.setGetDel.error = asErrorMessage(err);
  } finally {
    diagnostics.kv.setGetDel.ms = Date.now() - kvStarted;
  }

  const portalStarted = Date.now();
  try {
    if (!hasPortalUsersTable) {
      diagnostics.portal.lookup.error = diagnostics.schema.portal_users.error || 'table not found';
    } else {
      const { rows } = await query('select email_norm, is_active from portal_users limit 1');
      diagnostics.portal.lookup.ok = true;
      diagnostics.portal.lookup.found = (rows?.length || 0) > 0;
    }
  } catch (err) {
    diagnostics.portal.lookup.error = asErrorMessage(err);
  } finally {
    diagnostics.portal.lookup.ms = Date.now() - portalStarted;
  }

  diagnostics.ok = Boolean(
    diagnostics.db.ok
      && diagnostics.schema.kv_store.ok
      && diagnostics.schema.portal_users.ok
      && diagnostics.kv.setGetDel.ok
      && diagnostics.portal.lookup.ok,
  );

  return res.status(200).json(diagnostics);
}

export default safeHandler(handler, { route: '/api/admin/diag-store' });
