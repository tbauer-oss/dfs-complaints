import crypto from 'node:crypto';
import { trainingRecordsAll } from './store.js';

const TOKEN_BYTES = Number(process.env.SIGNATURE_TOKEN_BYTES || 32);

function timingSafeEqualHex(a = '', b = '') {
  const aa = Buffer.from(a, 'hex');
  const bb = Buffer.from(b, 'hex');
  if (aa.length !== bb.length) return false;
  return crypto.timingSafeEqual(aa, bb);
}

export function generateSignatureToken() {
  return crypto.randomBytes(TOKEN_BYTES).toString('base64url');
}

export function hashSignatureToken(token = '') {
  return crypto.createHash('sha256').update(String(token)).digest('hex');
}

export async function findParticipantByTokenHash(tokenHash) {
  if (!tokenHash) return null;
  const list = await trainingRecordsAll();
  for (const training of list) {
    const participants = Array.isArray(training.participants) ? training.participants : [];
    for (let idx = 0; idx < participants.length; idx += 1) {
      const participant = participants[idx];
      if (!participant?.signatureTokenHash) continue;
      if (timingSafeEqualHex(participant.signatureTokenHash, tokenHash)) {
        return { training, participant, participantIndex: idx };
      }
    }
  }
  return null;
}

export function resolveClientIp(req) {
  const forwarded = req.headers?.['x-forwarded-for'];
  if (typeof forwarded === 'string' && forwarded.trim()) {
    return forwarded.split(',')[0].trim();
  }
  if (Array.isArray(forwarded) && forwarded.length) {
    return forwarded[0];
  }
  return req.socket?.remoteAddress || '';
}

export function inferDevice(userAgent = '') {
  const ua = String(userAgent).toLowerCase();
  if (ua.includes('iphone') || ua.includes('ipad') || ua.includes('android') || ua.includes('mobile')) return 'mobile';
  if (ua.includes('tablet')) return 'tablet';
  return 'desktop';
}
