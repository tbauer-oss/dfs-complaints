// api/complaint/list.js
export const config = { runtime: 'nodejs' };

import { setCors, noContent, ok, bad, methodNotAllowed } from '../_lib/http.js';
import { complaintsByEmail } from '../_lib/store.js';
import jwt from 'jsonwebtoken';

const JWT_SECRET = process.env.JWT_SECRET || '';

function getUserEmail(req) {
  // Erwartet "Authorization: Bearer <token>"
  const hdr = req.headers?.authorization || '';
  const m = /^Bearer\s+(.+)$/i.exec(hdr);
  if (!m) return null;
  try {
    const payload = jwt.verify(m[1], JWT_SECRET);
    return (payload?.email || '').toString().toLowerCase();
  } catch {
    return null;
  }
}

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);
  if (req.method !== 'GET') return methodNotAllowed(res);

  const email = getUserEmail(req);
  if (!email) return bad(res, 'unauthorized', 401);

  const details = (req.query?.details || '').toString().trim() === '1';
  const list = await complaintsByEmail(email);

  if (details) return ok(res, list);

  // Kompakte Ticketliste (falls du sie woanders nutzt)
  return ok(res, list.map(c => c.ticket));
}
