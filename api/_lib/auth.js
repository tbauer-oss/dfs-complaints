// api/_lib/auth.js
import jwt from 'jsonwebtoken';
import { normalizeRole, normalizeStatus } from './portalAuth.js';
const JWT_SECRET = process.env.JWT_SECRET || '';

export function getAuthUser(req) {
  // Erwartet "Authorization: Bearer <token>"
  const auth = req.headers?.authorization || '';
  const m = auth.match(/^Bearer\s+(.+)$/i);
  if (!m) return null;
  try {
    const payload = jwt.verify(m[1], JWT_SECRET);
    if (!payload?.email) return null;
    // payload: { email, role, portalStatus, ... }
    const role = normalizeRole(payload.role);
    const portalStatus = normalizeStatus(payload.portalStatus);
    return { ...payload, role, portalStatus };
  } catch {
    return null;
  }
}
