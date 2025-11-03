// api/admin/pending.js
export const config = { runtime: 'nodejs' };

import {
  handlePreflight, setCors, ok, bad, methodNotAllowed, readJson,
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
  // --- CORS/Preflight zuerst ---
  if (handlePreflight(req, res)) return; // setzt CORS + beantwortet OPTIONS (204)
  setCors(req, res); // für Nicht-OPTIONS: immer CORS setzen

  // --- Admin-Auth (nach Preflight!) ---
  if (!isAdmin(req)) return bad(res, 'admin unauthorized', 401);

  try {
    // ---- LIST --------------------------------------------------------------
    if (req.method === 'GET') {
      const list = await pendingList();
      return ok(res, list);
    }

    // ---- APPROVE -----------------------------------------------------------
    if (req.method === 'POST') {
      // erwartet: { email, action?: 'approve', lang?: 'de'|'en'|... }
      const body = readJson(req) || {};
      const emailRaw = (body.email ?? '').toString().trim().toLowerCase();
      const action = (body.action ?? 'approve').toString();
      const lang   = (body.lang ?? 'de').toString().trim().toLowerCase();

      if (!emailRaw) return bad(res, 'missing email', 400);
      if (action !== 'approve') return bad(res, 'invalid action', 400);

      // Pending-Datensatz suchen
      const list = await pendingList();
      const p = Array.isArray(list)
        ? list.find(x => String(x?.email || '').trim().toLowerCase() === emailRaw)
        : null;
      if (!p) return bad(res, 'not found', 404);

      // Aus Pending entfernen, in Users übernehmen
      await pendingDelete(p.email);
      const user = {
        ...p,
        lang,                 // übernommene Sprache (falls Frontend sie sendet)
        status: 'active',
        approvedAt: Date.now(),
        revoked: false,
      };
      await userSave(user);

      // Bestätigungsmail (fehlertolerant)
      try {
        const name = (user.contact || user.company || '').toString();
        await send(user.email, tpl.approved(name));
      } catch (_) {}

      return ok(res, { ok: true, email: user.email });
    }

    // ---- REJECT/DELETE -----------------------------------------------------
    if (req.method === 'DELETE') {
      // erlaubt Body ODER ?email=...
      const body  = readJson(req) || {};
      const qmail = ((req.query?.email ?? body.email) || '').toString().trim();
      if (!qmail) return bad(res, 'missing email', 400);

      await pendingDelete(qmail);
      // Falls bereits als User existiert (Failsafe-Cleanup)
      try { await userDelete(qmail); } catch (_) {}

      // 204 oder 200 – wir geben konsistent JSON zurück
      return ok(res, { deleted: true, email: qmail });
    }

    return methodNotAllowed(res); // 405
  } catch (e) {
    // Log für Server-Inspect
    console.error('admin/pending error:', e);
    return bad(res, 'server error', 500);
  }
}
