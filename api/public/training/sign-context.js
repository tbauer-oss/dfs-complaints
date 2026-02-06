// /api/public/training/sign-context – load signing context
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed } from '../../_lib/http.js';
import { findParticipantByTokenHash, hashSignatureToken, resolveClientIp } from '../../_lib/trainingSignature.js';

const RATE_LIMIT_WINDOW_MS = Number(process.env.PUBLIC_SIGNATURE_RATE_WINDOW_MS || 60_000);
const RATE_LIMIT_MAX = Number(process.env.PUBLIC_SIGNATURE_RATE_MAX || 30);
const rateBuckets = new Map();

function rateLimit(req, res) {
  const ip = resolveClientIp(req) || 'unknown';
  const now = Date.now();
  const existing = rateBuckets.get(ip) || { count: 0, start: now };
  if (now - existing.start > RATE_LIMIT_WINDOW_MS) {
    rateBuckets.set(ip, { count: 1, start: now });
    return true;
  }
  if (existing.count >= RATE_LIMIT_MAX) {
    bad(res, 'rate limit', 429);
    return false;
  }
  existing.count += 1;
  rateBuckets.set(ip, existing);
  return true;
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  if (req.method !== 'GET') return methodNotAllowed(res);
  if (!rateLimit(req, res)) return;

  try {
    const token = (req.query?.t || '').toString().trim();
    if (!token) return bad(res, 'token missing', 400);
    const tokenHash = hashSignatureToken(token);
    const match = await findParticipantByTokenHash(tokenHash);
    if (!match) return bad(res, 'invalid token', 404);

    const { training, participant } = match;
    const now = Date.now();
    if (participant.signatureTokenUsedAt || participant.signedAt || participant.overrideNoSignature) {
      return bad(res, 'token used', 410);
    }
    if (!participant.signatureTokenExpiresAt || participant.signatureTokenExpiresAt < now) {
      return bad(res, 'token expired', 410);
    }

    const label = [training.trainingNumber, training.title].filter(Boolean).join(' · ');
    return ok(res, {
      ok: true,
      sessionId: training.id,
      trainingTitle: label,
      participantDisplayName: participant.name || participant.email || participant.id,
      companyName: 'DFS-DIAMON GmbH',
      requiresCheckbox: true,
      expiresAt: participant.signatureTokenExpiresAt,
    });
  } catch (err) {
    console.error('[training/sign-context] error', err);
    return bad(res, 'server error', 500);
  }
}
