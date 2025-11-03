// api/admin/users.js
export const config = { runtime: 'nodejs' };

import {
  handlePreflight,
  setCors,
  ok,
  bad,
  methodNotAllowed,
  readJson,
} from '../_lib/http.js';

import {
  usersList,
  userSave,
  userDelete,
  pendingDelete,
} from '../_lib/store.js';

const ADMIN_SECRET = process.env.ADMIN_SECRET || '';

function isAdmin(req) {
  // Node normalisiert Header-Keys zu lowercase
  const hdr = req.headers?.['x-admin-secret'];
  return typeof hdr === 'string' && !!ADMIN_SECRET && hdr === ADMIN_SECRET;
}

// E-Mail normalisieren
const normEmail = (v = '') => v.toString().trim().toLowerCase();

export default async function handler(req, res) {
  // CORS-Header setzen + OPTIONS (Preflight) direkt beantworten
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  // Admin-Auth
  if (!isAdmin(req)) return bad(res, 'admin unauthorized', 401);

  try {
    // ---- LIST --------------------------------------------------------------
    if (req.method === 'GET') {
      const list = await usersList();

      const out = (Array.isArray(list) ? list : []).map((u) => ({
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
        selfDeleted: !!u.selfDeleted, // wichtig fürs Frontend-Label
      }));

      return ok(res, out);
    }

    // ---- REVOKE / UNREVOKE ------------------------------------------------
    if (req.method === 'PATCH') {
      // erwartet: { email, revoked: true/false }
      const { email, revoked } = readJson(req) || {};
      const wanted = normEmail(email);
      if (!wanted) return bad(res, 'missing email', 400);
      if (typeof revoked !== 'boolean') return bad(res, 'missing revoked', 400);

      const list = await usersList();
      const u = (Array.isArray(list) ? list : []).find(
        (x) => normEmail(x?.email) === wanted
      );
      if (!u) return bad(res, 'not found', 404);

      u.revoked = !!revoked;
      await userSave(u);
      return ok(res, { ok: true, email: u.email, revoked: u.revoked });
    }

    // ---- DELETE (robust) ---------------------------------------------------
    if (req.method === 'DELETE') {
      // ?email=... oder Body {email:"..."}
      const url = new URL(req.url, 'http://x');
      const queryEmail = url.searchParams.get('email') || '';
      const body = readJson(req) || {};
      const wanted = normEmail(queryEmail || body.email || '');
      if (!wanted) return bad(res, 'missing email', 400);

      await userDelete(wanted);

      // Failsafe: evtl. noch in pending vorhanden → aufräumen
      try {
        await pendingDelete(wanted); // <-- Bugfix: 'wanted', nicht 'email'
      } catch (_) {}

      return ok(res, { deleted: true, email: wanted });
    }

    // ---- POST Fallback: action=delete -------------------------------------
    if (req.method === 'POST') {
      const body = readJson(req) || {};
      const action = (body.action || '').toString();
      if (action === 'delete') {
        const wanted = normEmail(body.email || '');
        if (!wanted) return bad(res, 'missing email', 400);
        await userDelete(wanted);
        return ok(res, { deleted: true, email: wanted });
      }
      return bad(res, 'unknown action', 400);
    }

    return methodNotAllowed(res);
  } catch (e) {
    console.error('admin/users error:', e);
    return bad(res, e?.message || String(e), 500);
  }
}
