// /api/account.js
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed } from './_lib/http.js';
import jwt from 'jsonwebtoken';
import {
  userDelete,
  pendingDelete,
  complaintsByEmail,
  complaintDelete,
} from './_lib/store.js';

const JWT_SECRET = process.env.JWT_SECRET || '';

function authEmailFromReq(req) {
  const hdr = req.headers?.authorization || req.headers?.Authorization || '';
  const m = /^Bearer\s+(.+)$/i.exec(hdr);
  if (!m) return null;
  try {
    const tok = m[1];
    const payload = jwt.verify(tok, JWT_SECRET);
    const email = (payload?.email || payload?.sub || '').toString().trim().toLowerCase();
    return email || null;
  } catch {
    return null;
  }
}

export default async function handler(req, res) {
  // CORS/Preflight zuerst
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  if (req.method !== 'DELETE') return methodNotAllowed(res);
  if (!JWT_SECRET) return bad(res, 'server auth misconfigured', 500);

  const email = authEmailFromReq(req);
  if (!email) return bad(res, 'unauthorized', 401);

  try {
    // 1) Reklamationen des Nutzers löschen (failsafe)
    const list = await complaintsByEmail(email);
    if (Array.isArray(list)) {
      for (const c of list) {
        if (c?.ticket) {
          try { await complaintDelete(c.ticket); } catch {}
        }
      }
    }
    // 2) Nutzer löschen
    try { await userDelete(email); } catch {}
    // 3) Eventuelles pending löschen
    try { await pendingDelete(email); } catch {}

    return ok(res, { deleted: true, email });
  } catch (e) {
    console.error('account DELETE error:', e);
    return bad(res, 'server error', 500);
  }
}
