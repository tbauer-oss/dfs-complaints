// /api/account.js
export const config = { runtime: 'nodejs' };

import {
  handlePreflight, setCors, ok, bad, methodNotAllowed, noContent
} from './_lib/http.js';
import jwt from 'jsonwebtoken';
import {
  userByEmail, userSave, userDelete, pendingDelete,
  complaintsByEmail, complaintDelete
} from './_lib/store.js';

const JWT_SECRET = process.env.JWT_SECRET || '';

function authEmailFromReq(req) {
  const hdr = req.headers?.authorization || req.headers?.Authorization || '';
  const m = /^Bearer\s+(.+)$/i.exec(hdr);
  if (!m) return null;
  try {
    const payload = jwt.verify(m[1], JWT_SECRET);
    const email = (payload?.email || payload?.sub || '').toString().trim().toLowerCase();
    return email || null;
  } catch {
    return null;
  }
}

export default async function handler(req, res) {
  // CORS & Preflight zuerst
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  if (!JWT_SECRET) return bad(res, 'server auth misconfigured', 500);

  const email = authEmailFromReq(req);
  if (!email) return bad(res, 'unauthorized', 401);

  // ---------- GET: Account lesen (für "Mein Account") ----------
  if (req.method === 'GET') {
    try {
      const u = await userByEmail(email);
      if (!u) return bad(res, 'not found', 404);
      // Nur harmlose Felder zurückgeben
      const out = {
        email: u.email || '',
        company: u.company || '',
        contact: u.contact || '',
        street: u.street || '',
        zip: u.zip || '',
        city: u.city || '',
        country: u.country || '',
        phone: u.phone || '',
        lang: u.lang || 'de',
        createdAt: u.createdAt || null,
        revoked: !!u.revoked,
      };
      return ok(res, out);
    } catch (e) {
      console.error('account GET error:', e);
      return bad(res, 'server error', 500);
    }
  }

  // ---------- DELETE: Account löschen ----------
  if (req.method === 'DELETE') {
    try {
      // Soft-Delete als Standard (sicherer)
      const hard = String(req.query?.hard || '').trim() === '1';

      if (hard) {
        // 1) Alle Reklamationen des Nutzers löschen
        const list = await complaintsByEmail(email);
        if (Array.isArray(list)) {
          for (const c of list) {
            if (c?.ticket) {
              try { await complaintDelete(c.ticket); } catch (_) {}
            }
          }
        }
        // 2) Nutzer löschen
        try { await userDelete(email); } catch (_) {}
        // 3) Eventuelles pending löschen
        try { await pendingDelete(email); } catch (_) {}
      } else {
        // Soft: nur sperren – Daten bleiben erhalten
        const u = (await userByEmail(email)) || { email };
        u.revoked = true;
        u.revokedAt = Date.now();
        await userSave(u);
      }

      // 204 genügt Frontend-seitig meist; sonst ok(res,{...})
      return noContent(res);
    } catch (e) {
      console.error('account DELETE error:', e);
      return bad(res, 'server error', 500);
    }
  }

  return methodNotAllowed(res);
}
