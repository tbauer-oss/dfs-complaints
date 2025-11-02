// api/admin/pending.js
export const config = { runtime: 'nodejs' };

import {
  handlePreflight, ok, bad, methodNotAllowed, readJson
} from '../_lib/http.js';
import { pendingList, pendingDelete, userSave, userDelete } from '../_lib/store.js';
import { send, tpl } from '../_lib/mail.js';

const ADMIN_SECRET = process.env.ADMIN_SECRET || '';
function isAdmin(req) {
  // Header-Keys sind in Node lowercase
  const hdr = req.headers?.['x-admin-secret'];
  return typeof hdr === 'string' && !!ADMIN_SECRET && hdr === ADMIN_SECRET;
}

export default async function handler(req, res) {
  // --- CORS/Preflight zuerst (setzt Header & beantwortet OPTIONS mit 204) ---
  if (handlePreflight(req, res)) return;

  if (!isAdmin(req)) return bad(res, 'admin unauthorized', 401);

  try {
    // ---- LIST --------------------------------------------------------------
    if (req.method === 'GET') {
      const list = await pendingList();
      return ok(res, list);
    }

    // ---- APPROVE -----------------------------------------------------------
    if (req.method === 'POST') {
      // erwartet: { email }
      const { email } = readJson(req) || {};
      const wanted = String(email || '').trim().toLowerCase();
      if (!wanted) return bad(res, 'missing email', 400);

      const list = await pendingList();
      const p = Array.isArray(list)
        ? list.find(x => String(x?.email || '').trim().toLowerCase() === wanted)
        : null;
      if (!p) return bad(res, 'not found', 404);

      // In Users übernehmen
      await pendingDelete(p.email);
      const user = { ...p, status: 'active', approvedAt: Date.now(), revoked: false };
      await userSave(user);

      // Bestätigungsmail (fehlerresistent)
      try { await send(user.email, tpl.approved(user.contact || user.company)); } catch (_) {}

      return ok(res, { ok: true, email: user.email });
    }

    // ---- REJECT/DELETE -----------------------------------------------------
    if (req.method === 'DELETE') {
      // erlaubt Body ODER ?email=...
      const body = readJson(req) || {};
      const qmail = (req.query?.email || body.email || '').toString().trim();
      if (!qmail) return bad(res, 'missing email', 400);

      await pendingDelete(qmail);
      // Cleanup, falls Nutzer bereits existiert (failsafe)
      try { await userDelete(qmail); } catch (_) {}

      return ok(res, { deleted: true, email: qmail });
    }

    return methodNotAllowed(res);
  } catch (e) {
    console.error('admin/pending error:', e);
    return bad(res, 'server error', 500);
  }
}
