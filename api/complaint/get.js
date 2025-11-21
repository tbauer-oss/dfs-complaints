// api/complaint/get.js
export const config = { runtime: 'nodejs' };

import { setCors, noContent, ok, bad, methodNotAllowed } from '../_lib/http.js';
import { complaintByTicket } from '../_lib/store.js';
import jwt from 'jsonwebtoken';

const JWT_SECRET = process.env.JWT_SECRET || '';

function getUserEmail(req) {
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

  const ticket = (req.query?.ticket || '').toString().trim();
  if (!ticket) return bad(res, 'missing ticket', 400);

  const c = await complaintByTicket(ticket);
  if (!c || (c.email || '').toLowerCase() !== email) {
    return bad(res, 'not found', 404);
  }
  return ok(res, c);
}
