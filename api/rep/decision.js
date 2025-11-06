export const config = { runtime: 'nodejs' };

// ---- Gemeinsame Utilities ----
import { redis } from '../_lib/redis.js'; // oder analog wie in deinen anderen Dateien

const PFX = 'dfs:complaints:';
const KEY = id => `${PFX}${id}`;

function S(v) { return (v ?? '').toString().trim(); }

// ---- Handler ----
export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', process.env.WEB_ORIGIN || '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') return res.status(204).end();

  try {
    if (req.method !== 'POST') {
      return res.status(405).json({ error: 'method not allowed' });
    }

    const body = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
    const repId   = S(body.repId);
    const ticket  = S(body.ticket);
    const decision = S(body.decision).toLowerCase(); // "approve" oder "reject"

    if (!repId || !ticket || !['approve', 'reject'].includes(decision)) {
      return res.status(400).json({ error: 'invalid data' });
    }

    // Reklamation laden
    const key = KEY(ticket);
    const complaint = await redis.get(key);
    if (!complaint) return res.status(404).json({ error: 'not found' });

    // Nur der zuständige Vertreter darf das
    if (complaint.repId && complaint.repId !== repId) {
      return res.status(403).json({ error: 'forbidden (wrong rep)' });
    }

    // Status anpassen
    if (decision === 'approve') {
      complaint.status = 'approved_by_rep';
      complaint.repDecision = 'approved';
      complaint.repDecisionAt = new Date().toISOString();
    } else {
      complaint.status = 'rejected_by_rep';
      complaint.repDecision = 'rejected';
      complaint.repDecisionAt = new Date().toISOString();
    }

    await redis.set(key, complaint);

    return res.status(200).json({ ok: true, complaint });
  } catch (e) {
    console.error('rep/decision error', e);
    return res.status(500).json({ error: String(e?.message || e) });
  }
}
