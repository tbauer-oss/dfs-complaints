// api/_lib/repAuth.js
import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';

const REP_JWT_SECRET = process.env.REP_JWT_SECRET || process.env.JWT_SECRET; // nutze bestehenden Secret, falls gewünscht
if (!REP_JWT_SECRET) throw new Error('REP_JWT_SECRET (oder JWT_SECRET) nicht gesetzt');

export function signRepJwt(rep) {
  // minimale Claims + Role
  const payload = {
    role: 'rep',
    repId: rep.id,
    email: (rep.email || '').toLowerCase(),
  };
  // 12h Gültigkeit (anpassbar)
  return jwt.sign(payload, REP_JWT_SECRET, { expiresIn: '12h' });
}

export function getRepFromAuthHeader(req) {
  try {
    const h = req.headers.authorization || '';
    const m = /^Bearer\s+(.+)$/i.exec(h);
    if (!m) return null;
    const token = m[1];
    const payload = jwt.verify(token, REP_JWT_SECRET);
    if (payload?.role !== 'rep') return null;
    return {
      repId: payload.repId,
      email: (payload.email || '').toLowerCase(),
    };
  } catch {
    return null;
  }
}

export async function hashPassword(plain) {
  const salt = await bcrypt.genSalt(10);
  return await bcrypt.hash(plain, salt);
}
export async function checkPassword(plain, hash) {
  try { return await bcrypt.compare(plain, hash); } catch { return false; }
}
