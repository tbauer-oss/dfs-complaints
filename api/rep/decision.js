// /api/rep/decision.js
export const config = { runtime: 'nodejs' };

// ------------------- IMPORTS -------------------
import { Redis } from '@upstash/redis';

// ---- Upstash-Verbindung ----
const redisUrl =
  process.env.REDIS_URL ||
  process.env.UPSTASH_REDIS_REST_URL ||
  '';
const redisToken =
  process.env.REDIS_TOKEN ||
  process.env.UPSTASH_REDIS_REST_TOKEN ||
  '';

if (!redisUrl || !redisToken) {
  console.warn('[rep/decision] Redis not configured.');
}

const redis = (redisUrl && redisToken)
  ? new Redis({ url: redisUrl, token: redisToken })
  : null;

// ------------------- HILFSFUNKTIONEN -------------------
function S(v) { return (v ?? '').toString().trim(); }

async function requireRedis() {
  if (!redis) throw new Error('Redis not configured');
}

// Key-Struktur für Reklamationen (wie in deinen Complaint-APIs)
const PFX = 'dfs:complaints:';
const KEY = id => `${PFX}${id}`;

// ------------------- HANDLER -------------------
export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', process.env.WEB_ORIGIN || '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  if (req.method === 'OPTIONS') return res.status(204).end();

  try {
    if (req.method !== 'POST') {
      return res.status(405).json({ error: 'method not allowed' });
    }

    await requireRedis();

    // ---- Body einlesen ----
    const body = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
    const repId = S(body.repId);
    const ticket = S(body.ticket);
    const decision = S(body.decision).toLowerCase(); // "approve" oder "reject"

    if (!repId || !ticket || !['approve', 'reject'].includes(decision)) {
      return res.status(400).json({ error: 'invalid data' });
    }

    // ---- Reklamation laden ----
    const key = KEY(ticket);
    const complaint = await redis.get(key);
    if (!complaint) {
      return res.status(404).json({ error: 'complaint not found' });
    }

    // ---- Sicherheitsprüfung ----
    if (complaint.repId && complaint.repId !== repId) {
      return res.status(403).json({ error: 'forbidden (wrong rep)' });
    }

    // ---- Entscheidung setzen ----
    const now = new Date().toISOString();
    complaint.repDecision = decision;
    complaint.repDecisionAt = now;

    if (decision === 'approve') {
      complaint.status = 'approved_by_rep';
    } else {
      complaint.status = 'rejected_by_rep';
    }

    await redis.set(key, complaint);

    // ---- Antwort ----
    return res.status(200).json({
      ok: true,
      ticket,
      status: complaint.status,
      repDecision: complaint.repDecision,
      repDecisionAt: now,
    });

  } catch (e) {
    console.error('[rep/decision] error', e);
    return res.status(500).json({ error: String(e?.message || e) });
  }
}
