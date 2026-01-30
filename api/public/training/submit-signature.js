// /api/public/training/submit-signature – submit remote signature
export const config = { runtime: 'nodejs' };

import crypto from 'node:crypto';
import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJsonBody } from '../../_lib/http.js';
import { portalUserFromRequest } from '../../_lib/portalAuth.js';
import { trainingRecordUpdate } from '../../_lib/store.js';
import {
  findParticipantByTokenHash,
  hashSignatureToken,
  inferDevice,
  resolveClientIp,
} from '../../_lib/trainingSignature.js';

const RATE_LIMIT_WINDOW_MS = Number(process.env.PUBLIC_SIGNATURE_RATE_WINDOW_MS || 60_000);
const RATE_LIMIT_MAX = Number(process.env.PUBLIC_SIGNATURE_RATE_MAX || 30);
const MAX_SIGNATURE_BYTES = 250000;
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

function stripBase64(data = '') {
  const str = data.toString().trim();
  if (!str) return '';
  const match = str.match(/^data:image\/[a-zA-Z]+;base64,(.+)$/);
  return match ? match[1] : str;
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  if (req.method !== 'POST') return methodNotAllowed(res);
  if (!rateLimit(req, res)) return;

  try {
    const body = await readJsonBody(req, { limitBytes: 900000 });
    const token = (body?.token || '').toString().trim();
    if (!token) return bad(res, 'token missing', 400);
    if (body?.confirmationChecked !== true) return bad(res, 'confirmation required', 400);

    const signatureBase64 = stripBase64(body?.signatureBase64Png || body?.signatureBase64 || '');
    if (!signatureBase64) return bad(res, 'signature required', 400);

    const buffer = Buffer.from(signatureBase64, 'base64');
    if (buffer.length > MAX_SIGNATURE_BYTES) {
      return bad(res, 'signature too large', 413);
    }

    const tokenHash = hashSignatureToken(token);
    const match = await findParticipantByTokenHash(tokenHash);
    if (!match) return bad(res, 'invalid token', 404);

    const { training, participant, participantIndex } = match;
    const now = Date.now();
    if (!participant.signatureTokenExpiresAt || participant.signatureTokenExpiresAt < now) {
      return bad(res, 'token expired', 410);
    }
    if (participant.signatureTokenUsedAt || participant.signedAt || participant.overrideNoSignature) {
      return ok(res, { ok: true, alreadySigned: true });
    }

    const actor = await portalUserFromRequest(req, { allowSecretFallback: false });
    const updatedParticipants = [...training.participants];
    const updated = { ...participant };
    updated.signatureBase64 = signatureBase64;
    updated.signatureHash = crypto.createHash('sha256').update(signatureBase64).digest('hex');
    updated.signedAt = now;
    updated.signedByUserId = actor?.email || '';
    updated.signatureTokenUsedAt = now;
    updated.confirmationChecked = true;
    updated.signatureRemoteMeta = {
      ip: resolveClientIp(req),
      userAgent: req.headers?.['user-agent'] || '',
      device: inferDevice(req.headers?.['user-agent'] || ''),
      submittedAt: now,
    };
    updated.updatedAt = now;
    updatedParticipants[participantIndex] = updated;

    await trainingRecordUpdate(training.id, {
      participants: updatedParticipants,
      auditLog: [
        ...(training.auditLog || []),
        {
          action: 'signature_remote',
          message: `Unterschrift remote erfasst: ${participant.name || participant.email || participant.id}`,
          by: actor?.email || 'remote',
          at: now,
        },
      ],
      updatedBy: actor?.email || 'remote',
    });

    return ok(res, { ok: true });
  } catch (err) {
    console.error('[training/submit-signature] error', err);
    return bad(res, 'server error', 500);
  }
}
