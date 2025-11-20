// api/customers/[id].js
export const config = { runtime: 'nodejs' };

import { setCors } from '../_lib/cors.js';
import { readJson } from '../_lib/http.js';
import { getRepFromAuthHeader } from '../_lib/repAuth.js';
import { userByEmail, userSave } from '../_lib/store.js';
import { repCustomers as storeRepCustomers } from '../_lib/repsStore.js';

const ADMIN_SECRET = process.env.ADMIN_SECRET || '';
const UP_URL = process.env.UPSTASH_REDIS_REST_URL || '';
const UP_TOKEN = process.env.UPSTASH_REDIS_REST_TOKEN || '';
const KEY_REP_OF = (email) => `dfs:repOf:${email}`;
const MAX_NOTE = 2000;

const S = (v) => (v ?? '').toString().trim();

async function upstashGet(key) {
  if (!UP_URL || !UP_TOKEN) return null;
  const r = await fetch(`${UP_URL}/get/${encodeURIComponent(key)}`, {
    method: 'GET',
    headers: { Authorization: `Bearer ${UP_TOKEN}` },
    cache: 'no-store',
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) {
    const msg = j?.error || j?.message || `Upstash error ${r.status}`;
    throw new Error(msg);
  }
  return j?.result ?? null;
}

async function repOwnsCustomer(repId, email) {
  if (!repId || !email) return false;
  const lower = email.toLowerCase();
  try {
    const list = await storeRepCustomers(repId);
    if (Array.isArray(list) && list.some((entry) => S(entry).toLowerCase() === lower)) {
      return true;
    }
  } catch (_) {
    // fallback
  }
  try {
    const mapped = await upstashGet(KEY_REP_OF(lower));
    return S(mapped).toLowerCase() === repId.toLowerCase();
  } catch (_) {
    return false;
  }
}

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'PATCH') {
    return res.status(405).end(JSON.stringify({ error: 'method not allowed' }));
  }

  const id = S(req.query?.id).toLowerCase();
  if (!id || !id.includes('@')) {
    return res.status(400).end(JSON.stringify({ error: 'invalid id' }));
  }

  const adminHdr = S(req.headers['x-admin-secret']);
  let repAuth = null;
  let isAdmin = false;

  if (ADMIN_SECRET && adminHdr === ADMIN_SECRET) {
    isAdmin = true;
  } else {
    repAuth = getRepFromAuthHeader(req);
    if (!repAuth?.repId) {
      return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));
    }
    const allowed = await repOwnsCustomer(repAuth.repId, id);
    if (!allowed) {
      return res.status(403).end(JSON.stringify({ error: 'forbidden' }));
    }
  }

  try {
    const body = readJson(req) || {};
    const rawNote = (body.repNote ?? '').toString();
    let note = rawNote.replace(/\r\n/g, '\n');
    if (note.length > MAX_NOTE) note = note.substring(0, MAX_NOTE);
    note = note.trim();

    const user = await userByEmail(id);
    if (!user) {
      return res.status(404).end(JSON.stringify({ error: 'not found' }));
    }

    if (note.length > 0) {
      user.repNote = note;
    } else {
      delete user.repNote;
    }
    user.repNoteUpdatedAt = Date.now();
    if (isAdmin) {
      user.repNoteUpdatedBy = 'admin';
    } else if (repAuth?.repId) {
      user.repNoteUpdatedBy = repAuth.repId;
    }

    await userSave(user);

    return res.status(200).end(JSON.stringify({
      ok: true,
      repNote: user.repNote || '',
      updatedAt: user.repNoteUpdatedAt || null,
    }));
  } catch (e) {
    console.error('[customers/[id]] error', e);
    return res.status(500).end(JSON.stringify({ error: 'server error' }));
  }
}
