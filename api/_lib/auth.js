// api/_lib/auth.js
import jwt from 'jsonwebtoken';
const JWT_SECRET = process.env.JWT_SECRET || '';

export function getAuthUser(req) {
  // Erwartet "Authorization: Bearer <token>"
  const auth = req.headers?.authorization || '';
  const m = auth.match(/^Bearer\s+(.+)$/i);
  if (!m) return null;
  try {
    const payload = jwt.verify(m[1], JWT_SECRET);
    // payload: { email, company, ... }
    return (payload && payload.email) ? payload : null;
  } catch {
    return null;
  }
}
