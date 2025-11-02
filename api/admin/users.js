// api/admin/users.js
export const config = { runtime: 'nodejs' };

import {
  handlePreflight, ok, bad, methodNotAllowed, readJson
} from '../_lib/http.js';
import { usersList, userSave, userDelete, pendingDelete } from '../_lib/store.js';

const ADMIN_SECRET = process.env.ADMIN_SECRET || '';

function isAdmin(req) {
  // Node normalisiert Header-Keys zu lowercase
  const hdr = req.headers?.['x-admin-secret'];
  return typeof hdr === 'string' && !!ADMIN_SECRET && hdr === ADMIN_SECRET;
}

export default async function handler(req, res) {
  // CORS-Header setzen + OPTIONS (Preflight) direkt beantworten
  if (handlePreflight(req, res)) return;

  if (!isAdmin(req)) return bad(res, 'admin unauthorized', 401);

  try {
    // ---- LIST ----
    if (req.method === 'GET') {
      const list = await usersList();
      return ok(res, list);
    }

    // ---- REVOKE / UNREVOKE ----
    if (req.method === 'PATCH') {
      // erwartet: { email, revoked: true/false }
      const { email, revoked } = readJson(req) || {};
      if (!email) return bad(res, 'missing email', 400);

      const list = await usersList();
      const u = list.find(x => (x.email || '').toString().toLowerCase() === String(email).toLowerCase());
      if (!u) return bad(res, 'not found', 404);

      u.revoked = !!revoked;
      await userSave(u);
      return ok(res, { ok: true });
    }

    // ---- DELETE (robust) ----
    if (req.method === 'DELETE') {
      const body = readJson(req) || {};
      const email = (req.query?.email || body.email || '').toString().trim();
      if (!email) return bad(res, 'missing email', 400);

      await userDelete(email);
      // pending ggf. mit aufräumen (failsafe)
      try { await pendingDelete(email); } catch (_) {}
      return ok(res, { deleted: true, email });
    }

    // ---- POST Fallback: action=delete ----
    if (req.method === 'POST') {
      const body = readJson(req) || {};
      const action = (body.action || '').toString();
      if (action === 'delete') {
        const email = (body.email || '').toString().trim();
        if (!email) return bad(res, 'missing email', 400);
        await userDelete(email);
        return ok(res, { deleted: true, email });
      }
      return bad(res, 'unknown action', 400);
    }

    return methodNotAllowed(res);
  } catch (e) {
    return bad(res?.message || String(e), 500);
  }
}
