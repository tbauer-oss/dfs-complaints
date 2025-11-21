// api/_lib/repAuth.js
export const config = { runtime: 'nodejs' };

import jwt from 'jsonwebtoken';

const REP_SECRET = process.env.REP_JWT_SECRET;

/**
 * Liest den Authorization-Header ("Bearer <token>"), verifiziert das JWT
 * gegen REP_JWT_SECRET und gibt bei Erfolg { repId, token, claims } zurück.
 * Bei Fehlern oder fehlendem Token: null.
 */
export function getRepFromAuthHeader(req) {
  if (!REP_SECRET) return null;

  const h = String(req.headers?.authorization || '');
  if (!/^Bearer\s+/i.test(h)) return null;

  const token = h.replace(/^Bearer\s+/i, '').trim();
  if (!token) return null;

  try {
    const claims = jwt.verify(token, REP_SECRET);
    // Primär nutzen wir "repId", akzeptieren aber zur Sicherheit auch "sub" oder "id"
    const repId = claims?.repId ?? claims?.sub ?? claims?.id;
    if (!repId) return null;

    return {
      repId: String(repId),
      token,
      claims,
    };
  } catch {
    return null;
  }
}

/**
 * Optionaler Helper: prüft ein übergebenes Token (z. B. aus Cookies) und gibt
 * bei Erfolg { repId, claims } zurück, sonst null.
 */
export function verifyRepToken(token) {
  if (!REP_SECRET || !token) return null;
  try {
    const claims = jwt.verify(token, REP_SECRET);
    const repId = claims?.repId ?? claims?.sub ?? claims?.id;
    if (!repId) return null;
    return { repId: String(repId), claims };
  } catch {
    return null;
  }
}

/**
 * Optionaler Helper: erstellt ein neues Rep-JWT mit { repId }.
 * Default-Expiry: 7d (kann via opts überschrieben werden).
 */
export function signRepToken(repId, opts = {}) {
  if (!REP_SECRET) throw new Error('REP_JWT_SECRET not set');
  if (!repId) throw new Error('repId is required');
  const options = { expiresIn: '7d', ...opts };
  return jwt.sign({ repId }, REP_SECRET, options);
}
