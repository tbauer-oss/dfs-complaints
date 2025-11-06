// /api/rep/decision.js
export const config = { runtime: 'nodejs' };

import { Redis } from '@upstash/redis';
import { getRepFromAuthHeader } from '../_lib/repAuth.js'; // <— neu: JWT aus Header lesen

// ---- Upstash-Verbindung (unverändert) ----
const redisUrl =
  process.env.REDIS_URL ||
  process.env.UPSTASH_REDIS_REST_URL || '';
const redisToken =
  process.env.REDIS_TOKEN ||
  process.env.UPSTASH_REDIS_REST_TOKEN || '';

const redis = (redisUrl && redisToken)
  ? new Redis({ url: redisUrl, token: redisToken })
  : null;

function requireRedis() {
  if (!redis) throw new Error('Redis not configured');
}
function S(v) { return (v ?? '').toString().trim(); }

// ---- CORS helper (einheitlich mit anderen Endpunkten) ----
function setCors(res) {
  const origin = process.env.WEB_ORIGIN || 'https://dfs-complaints-web.vercel.app';
  res.setHeader('Access-Control-Allow-Origin', origin);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Methods', 'POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Gate');
  res.setHeader('Access-Control-Max-Age', '600');
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
}

const PFX = 'dfs:complaints:';
const KEY = (id) => `${PFX}${id}`;

export default async function handler(req, res) {
  setCors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method not allowed' });

  try {
    requireRedis();

    // --- Auth aus Bearer-Token (nicht aus Body) ---
    let auth = null;
    try { auth = getRepFromAuthHeader(req); } catch {}
    if (!auth || !auth.repId) {
      return res.status(401).json({ error: 'unauthorized' });
    }
    const repId = S(auth.repId);

    // --- Body robust parsen (auch wenn text/plain kommt) ---
    let body = req.body;
    if (typeof body === 'string') {
      try { body = JSON.parse(body || '{}'); } catch { body = {}; }
    }
    body = body || {};

    const ticket = S(body.ticket || body.id);

    // decision akzeptiert Varianten:
    //  - decision: "accept"/"accepted"/"approve"/"approved"/"reject"/"rejected"/"decline"
    //  - approve: true/false
    const rawByDecision = S(body.decision).toLowerCase();
    const rawByApprove  = (body.approve === true) ? 'accept'
                         : (body.approve === false) ? 'reject'
                         : '';
    const raw = (rawByDecision || rawByApprove);

    const map = {
      'accept': 'accepted',
      'accepted': 'accepted',
      'approve': 'accepted',
      'approved': 'accepted',
      'reject': 'rejected',
      'rejected': 'rejected',
      'decline': 'rejected',
    };
    const decision = map[raw];

    if (!ticket || !decision) {
      return res.status(400).json({ error: 'invalid data' });
    }

    // ---- Reklamation laden & prüfen ----
    const key = KEY(ticket);
    const complaint = await redis.get(key);
    if (!complaint) {
      return res.status(404).json({ error: 'complaint not found' });
    }
    // Wenn der Datensatz eine Zuordnung enthält, prüfen
    if (complaint.repId && S(complaint.repId) !== repId) {
      return res.status(403).json({ error: 'forbidden (wrong rep)' });
    }

    // ---- Entscheidung setzen (vereinheitlicht) ----
    const now = new Date().toISOString();
    complaint.decision = decision;          // Frontend liest 'decision'
    complaint.decisionAt = now;             // optional, konsistent benennen
    complaint.repId = complaint.repId || repId;

    // Optionaler Statusübergang (falls du das nutzt):
    complaint.status =
      (decision === 'accepted') ? 'approved_by_rep' : 'rejected_by_rep';

    await redis.set(key, complaint);

    return res.status(200).json({
      ok: true,
      ticket,
      decision: complaint.decision,
      status: complaint.status,
      at: now,
    });

  } catch (e) {
    console.error('[rep/decision] error', e);
    return res.status(500).json({ error: String(e?.message || e) });
  }
}
