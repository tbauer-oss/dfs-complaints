// api/rep/decision/reset.js
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors } from '../../_lib/http.js';
import { redis } from '../../_lib/redis.js';

const S = (v) => (v ?? '').toString().trim();
const nowIso = () => new Date().toISOString();
const rid = () => `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;

async function loadRepAuth() {
  const mod = await import(new URL('../../_lib/repAuth.js', import.meta.url));
  if (typeof mod.getRepFromAuthHeader !== 'function') {
    throw new Error('repAuth export missing');
  }
  return mod.getRepFromAuthHeader;
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res, 'Content-Type, Authorization, X-Gate, X-Debug');

  const debug = S(req.query?.debug) === '1' || S(req.headers?.['x-debug']) === '1';
  const reqId = rid();

  if (req.method !== 'POST') {
    return debug
      ? res.status(200).json({ ok: false, reqId, error: 'method not allowed', method: req.method })
      : res.status(405).json({ error: 'method not allowed' });
  }

  let getRepFromAuthHeader;
  try {
    getRepFromAuthHeader = await loadRepAuth();
  } catch (e) {
    console.error('[rep/decision/reset] repAuth load error:', e);
    return debug
      ? res.status(500).json({ ok: false, reqId, error: 'repAuth import failed' })
      : res.status(500).json({ error: 'repAuth import failed' });
  }

  let auth = null;
  try {
    auth = getRepFromAuthHeader(req);
  } catch (e) {
    console.error('[rep/decision/reset] getRepFromAuthHeader error:', e);
  }
  if (!auth?.repId) {
    return debug
      ? res.status(200).json({
          ok: false,
          reqId,
          error: 'unauthorized',
          haveAuthHeader: !!req.headers?.authorization,
          xGate: !!req.headers?.['x-gate'],
        })
      : res.status(401).json({ error: 'unauthorized' });
  }

  let ticket = '';
  let raw = '';
  try {
    if (req.body && typeof req.body === 'object') {
      ticket = S(req.body.ticket);
    } else {
      raw = S(req.body);
      ticket = S(raw ? JSON.parse(raw).ticket : '');
    }
  } catch (e) {
    console.error(`[rep/decision/reset] ${reqId} invalid json:`, e, 'body=', raw);
    return res.status(400).json({ error: 'invalid json' });
  }
  if (!ticket) return res.status(400).json({ error: 'ticket required' });

  try {
    const key1 = `dfs:complaint:${ticket}`;
    const key2 = `dfs:complaints:${ticket}`;

    let complaint = await redis.get(key1);
    if (!complaint) complaint = await redis.get(key2);

    if (!complaint) {
      return debug
        ? res.status(200).json({ ok: false, reqId, error: 'complaint not found', ticket })
        : res.status(404).json({ error: 'complaint not found' });
    }

    if (typeof complaint === 'string') {
      try { complaint = JSON.parse(complaint); } catch {}
    }
    if (typeof complaint !== 'object' || Array.isArray(complaint)) {
      return res.status(500).json({ error: 'invalid complaint format' });
    }

    if (S(complaint.repId) && S(complaint.repId) !== S(auth.repId)) {
      return debug
        ? res.status(200).json({ ok: false, reqId, error: 'forbidden (wrong rep)', repIdOnRecord: complaint.repId })
        : res.status(403).json({ error: 'forbidden (wrong rep)' });
    }

    delete complaint.repDecision;
    delete complaint.repDecisionAt;
    delete complaint.repDecisionBy;
    delete complaint.repId;
    complaint.updatedAt = Date.now();

    const existedInKey1 = !!(await redis.get(key1));
    const saveKey = existedInKey1 ? key1 : key2;
    await redis.set(saveKey, complaint);

    try {
      await redis.set(
        `dfs:audit:repDecisionReset:${ticket}:${nowIso()}`,
        { by: auth.repId, at: nowIso(), action: 'reset' },
        { ex: 60 * 60 * 24 * 7 },
      );
    } catch (e) {
      console.warn('[rep/decision/reset] audit write failed:', e);
    }

    return debug
      ? res.status(200).json({
          ok: true,
          reqId,
          ticket,
          removed: ['repDecision', 'repDecisionAt', 'repDecisionBy', 'repId'],
          savedKey: saveKey,
        })
      : res.status(204).end();
  } catch (e) {
    console.error(`[rep/decision/reset] ${reqId} error:`, e);
    return res.status(500).json({ error: e?.message || String(e) });
  }
}
