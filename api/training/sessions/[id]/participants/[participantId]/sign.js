// /api/training/sessions/[id]/participants/[participantId]/sign – Signature capture
export const config = { runtime: 'nodejs' };

import crypto from 'node:crypto';
import { ok, bad, methodNotAllowed, readJson } from '../../../../../_lib/http.js';
import { withCorsHandler } from '../../../../../_lib/http.js';
import { requireTrainingScopeAccess } from '../../../../../admin/_guard.js';
import { isAdminUser } from '../../../../../_lib/portalAuth.js';
import { trainingRecordGet, trainingRecordUpdate } from '../../../../../_lib/store.js';

const TRAINING_TILE = 'trainingSessions';
const MAX_SIGNATURE_BYTES = 250000;

function stripBase64(data = '') {
  const str = data.toString().trim();
  if (!str) return '';
  const match = str.match(/^data:image\/[a-zA-Z]+;base64,(.+)$/);
  return match ? match[1] : str;
}

async function handler(req, res) {
  if (req.method === 'OPTIONS') return res.status(204).end();
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
    const body = readJson(req) || {};
    const action = (body.action || 'sign').toString();
    const admin = isAdminUser(actor);

    if (!admin) {
      const actorMail = (actor.email || '').toString().toLowerCase();
      const participantMail = (participant.userId || participant.email || '').toString().toLowerCase();
      if (!actorMail || actorMail !== participantMail) {
        return bad(res, 'forbidden', 403);
      }
    }

    const updatedParticipants = [...participants];
    const updated = { ...participant };
    const now = Date.now();

    if (action === 'reset') {
      if (!admin) return bad(res, 'forbidden', 403);
      const reason = (body.reason || '').toString().trim();
      const resolvedReason = reason.length >= 5 ? reason : 'Unterschrift zurückgesetzt';
      updated.signedAt = null;
      updated.signedByUserId = '';
      updated.signatureBase64 = '';
      updated.signatureUrl = '';
      updated.signatureHash = '';
      updated.signatureNote = '';
      updated.confirmationChecked = false;
      updated.overrideNoSignature = false;
      updated.overrideReason = '';
      updated.overriddenByUserId = '';
      updated.overriddenAt = null;
      updated.signatureTokenHash = '';
      updated.signatureTokenIssuedAt = null;
      updated.signatureTokenExpiresAt = null;
      updated.signatureTokenUsedAt = null;
      updated.signatureRemoteMeta = null;
      updated.updatedAt = now;
      updatedParticipants[idx] = updated;
      const updatedTraining = await trainingRecordUpdate(training.id, {
        participants: updatedParticipants,
        auditLog: [
          ...(training.auditLog || []),
          { action: 'signature_reset', message: resolvedReason, by: actor.email, at: now },
        ],
      });
      return ok(res, { ok: true, record: updatedTraining });
    }

    if (action === 'override') {
      if (!admin) return bad(res, 'forbidden', 403);
      const reason = (body.reason || '').toString().trim();
      if (reason.length < 5) return bad(res, 'override reason required', 400);
      updated.overrideNoSignature = true;
      updated.overrideReason = reason;
      updated.overriddenByUserId = actor.email || '';
      updated.overriddenAt = now;
      updated.confirmationChecked = true;
      updated.updatedAt = now;
      updatedParticipants[idx] = updated;
      const updatedTraining = await trainingRecordUpdate(training.id, {
        participants: updatedParticipants,
        auditLog: [
          ...(training.auditLog || []),
          { action: 'signature_override', message: `Teilnahme bestätigt ohne Signatur: ${reason}`, by: actor.email, at: now },
        ],
      });
      return ok(res, { ok: true, record: updatedTraining });
    }

    if (participant.signedAt || participant.signatureBase64 || participant.signatureUrl || participant.overrideNoSignature) {
      return bad(res, 'already signed', 409);
    }

    const signatureBase64 = stripBase64(body.signatureBase64 || body.signatureImageBase64 || '');
    if (!signatureBase64) return bad(res, 'signature required', 400);
    const buffer = Buffer.from(signatureBase64, 'base64');
    if (buffer.length > MAX_SIGNATURE_BYTES) {
      return bad(res, 'signature too large', 413);
    }

    updated.signatureBase64 = signatureBase64;
    updated.signatureHash = crypto.createHash('sha256').update(signatureBase64).digest('hex');
    updated.signedAt = now;
    updated.signedByUserId = actor.email || '';
    updated.signatureNote = (body.note || '').toString().trim();
    updated.confirmationChecked = true;
    updated.signatureTokenUsedAt = now;
    updated.signatureRemoteMeta = null;
    updated.updatedAt = now;
    updatedParticipants[idx] = updated;

    const updatedTraining = await trainingRecordUpdate(training.id, {
      participants: updatedParticipants,
      auditLog: [
        ...(training.auditLog || []),
        { action: 'signature', message: 'Unterschrift erfasst', by: actor.email, at: now },
      ],
    });

    return ok(res, { ok: true, record: updatedTraining });
  } catch (err) {
    console.error('[training/signature] error', err);
    return bad(res, 'server error', 500);
  }
}

export default withCorsHandler(handler);
