// api/admin/pending.js
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';

const ADMIN_SECRET = process.env.ADMIN_SECRET || '';

function isAdmin(req) {
  // Header-Keys sind in Node lowercase
  const hdr = req?.headers?.['x-admin-secret'];
  return typeof hdr === 'string' && !!ADMIN_SECRET && hdr === ADMIN_SECRET;
}

export default async function handler(req, res) {
  // --- CORS/Preflight zuerst (setzt Header & beantwortet OPTIONS mit 204) ---
  if (handlePreflight(req, res)) return;
  // Für Nicht-OPTIONS alle CORS-Header setzen
  setCors(req, res);

  // --- Admin-Auth (nach Preflight!) ---
  if (!isAdmin(req)) return bad(res, 'admin unauthorized', 401);

  // --- Schwere Module erst jetzt laden (verhindert Preflight-/CORS-Brüche) ---
  let store, mail;
  try {
    store = await import('../_lib/store.js');
    // mail ist optional – darf nicht den Request killen
    mail = await import('../_lib/mail.js').catch(() => null);
  } catch (e) {
    console.error('lazy import failed:', e);
    return bad(res, 'server error (imports)', 500);
  }

  const { pendingList, pendingDelete, userSave, userDelete } = store;
  const send = mail?.send;
  const tpl  = mail?.tpl;

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
      const action   = (body.action ?? 'approve').toString();
      const lang     = (body.lang ?? 'de').toString().trim().toLowerCase();

      if (!emailRaw) return bad(res, 'missing email', 400);
      if (action !== 'approve') return bad(res, 'invalid action', 400);

      const list = await pendingList();
      const p = Array.isArray(list)
        ? list.find(x => String(x?.email || '').trim().toLowerCase() === emailRaw)
        : null;
      if (!p) return bad(res, 'not found', 404);

      // Aus Pending entfernen, in Users übernehmen
      await pendingDelete(p.email);
      const user = {
        ...p,
        lang,
        status: 'active',
        approvedAt: Date.now(),
        revoked: false,
      };
      await userSave(user);

      // Bestätigungsmail (fehlertolerant, nie den Request brechen)
      if (send && tpl?.approved) {
        try {
          const name = (user.contact || user.company || '').toString();
          await send(user.email, tpl.approved(name));
        } catch (_) {}
      }

      return ok(res, { ok: true, email: user.email });
    }

    // ---- REJECT/DELETE -----------------------------------------------------
    if (req.method === 'DELETE') {
      // erlaubt Body ODER ?email=...
      const body  = readJson(req) || {};
      const qmail = ((req.query?.email ?? body.email) || '').toString().trim();
      if (!qmail) return bad(res, 'missing email', 400);

      await pendingDelete(qmail);
      // Cleanup, falls Nutzer bereits existiert (failsafe)
      try { await userDelete(qmail); } catch (_) {}

      // Konsistente JSON-Antwort
      return ok(res, { deleted: true, email: qmail });
    }

    return methodNotAllowed(res); // 405
  } catch (e) {
    console.error('admin/pending error:', e);
    return bad(res, 'server error', 500);
  }
}
