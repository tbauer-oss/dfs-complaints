// /api/training/sessions/[id]/participants/[participantId]/signature-token – Issue remote signature token
export const config = { runtime: 'nodejs' };

import { ok, bad, methodNotAllowed } from '../../../../_lib/http.js';
import { withCorsHandler } from '../../../../_lib/withCors.ts';
import { requireTrainingScopeAccess } from '../../../../admin/_guard.js';
import { trainingRecordGet, trainingRecordUpdate } from '../../../../_lib/store.js';
import { generateSignatureToken, hashSignatureToken } from '../../../../_lib/trainingSignature.js';

const TRAINING_TILE = 'trainingSessions';
const TOKEN_TTL_MS = Number(process.env.SIGNATURE_TOKEN_TTL_MS || 2 * 60 * 60 * 1000);
const APP_ORIGIN = (process.env.APP_ORIGIN || process.env.APP_BASE_URL || 'https://dfs-complaints-web.vercel.app').replace(/\/$/, '');

async function handler(req, res) {
  if (req.method !== 'POST') return methodNotAllowed(res);

  const actor = await requireTrainingScopeAccess(req, res, { tile: TRAINING_TILE, write: true });
  if (!actor) return;

  try {
    const id = (req.query?.id || '').toString();
    const participantId = (req.query?.participantId || '').toString();
    if (!id || !participantId) return bad(res, 'missing id', 400);

    const training = await trainingRecordGet(id);
    if (!training) return bad(res, 'not found', 404);

    const participants = Array.isArray(training.participants) ? training.participants : [];
    const idx = participants.findIndex((p) => p.id === participantId);
    if (idx < 0) return bad(res, 'participant not found', 404);

    const participant = participants[idx];
    if (participant.signedAt || participant.signatureBase64 || participant.signatureUrl || participant.overrideNoSignature) {
      return bad(res, 'already signed', 409);
    }

    const token = generateSignatureToken();
    const tokenHash = hashSignatureToken(token);
    const now = Date.now();
    const expiresAt = now + TOKEN_TTL_MS;

    const updatedParticipants = [...participants];
    const updated = {
      ...participant,
      signatureTokenHash: tokenHash,
      signatureTokenIssuedAt: now,
      signatureTokenExpiresAt: expiresAt,
      signatureTokenUsedAt: null,
      signatureRemoteMeta: null,
      updatedAt: now,
    };
    updatedParticipants[idx] = updated;

    const updatedTraining = await trainingRecordUpdate(training.id, {
      participants: updatedParticipants,
      auditLog: [
        ...(training.auditLog || []),
        {
          action: 'signature_token',
          message: `Signatur-Link erstellt für ${participant.name || participant.email || participant.id}`,
          by: actor.email,
          at: now,
        },
      ],
      updatedBy: actor.email,
    });

    const url = `${APP_ORIGIN}/sign?t=${encodeURIComponent(token)}`;
    return ok(res, { ok: true, url, expiresAt, record: updatedTraining });
  } catch (err) {
    console.error('[training/signature-token] error', err);
    return bad(res, 'server error', 500);
  }
}

export default withCorsHandler(handler, {
  before(req, res, { allowOrigin }) {
    res.setHeader('X-Handler', 'signature-token');
    res.setHeader('X-Cors-Applied', allowOrigin ? 'yes' : 'no');
    console.info('[training/signature-token]', {
      method: req.method,
      origin: req.headers?.origin,
      url: req.url,
    });
  },
});
