// api/admin/pending.js
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { isAdmin } from '../_lib/auth.js';
import { pendingList, pendingDelete, userSave, userDelete } from '../_lib/store.js';
import { send, tpl } from '../_lib/mail.js';

export default async function handler(req, res) {
  // 1) CORS & Preflight
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  // 2) Admin-Auth
  if (!isAdmin(req, { debug: true })) return bad(res, 'admin unauthorized', 401);

  // 3) Sicherer Wrapper für Store-Aufrufe
  async function safePendingList() {
    try {
      const list = await pendingList();
      if (!Array.isArray(list)) {
        console.error('pendingList returned non-array:', typeof list);
        return [];
      }
      return list;
    } catch (e) {
      console.error('pendingList() failed:', e);
      // Kapsel sauber: liefere leere Liste statt 500
      return [];
    }
  }

  try {
    // ---- LIST --------------------------------------------------------------
    if (req.method === 'GET') {
      const list = await safePendingList();
      return ok(res, list);
    }

    // ---- APPROVE -----------------------------------------------------------
    if (req.method === 'POST') {
      const body = readJson(req) || {};
      const emailRaw = (body.email ?? '').toString().trim().toLowerCase();
      const action = (body.action ?? 'approve').toString();
      const lang   = (body.lang ?? 'de').toString().trim().toLowerCase();

      if (!emailRaw) return bad(res, 'missing email', 400);
      if (action !== 'approve') return bad(res, 'invalid action', 400);

      const list = await safePendingList();
      const p = list.find(x => String(x?.email || '').trim().toLowerCase() === emailRaw);
      if (!p) return bad(res, 'not found', 404);

      try { await pendingDelete(p.email); }
      catch (e) { console.error('pendingDelete failed:', e); /* trotzdem weiter */ }

      const user = {
        ...p,
        lang,
        status: 'active',
        approvedAt: Date.now(),
        revoked: false,
      };

      try { await userSave(user); }
      catch (e) {
        console.error('userSave failed:', e);
        return bad(res, 'store error', 500);
      }

      // Mail darf nicht crashen
      try { await send(user.email, tpl.approved(user.contact || user.company)); } catch (_) {}

      return ok(res, { ok: true, email: user.email });
    }

    // ---- REJECT/DELETE -----------------------------------------------------
    if (req.method === 'DELETE') {
      const body  = readJson(req) || {};
      const qmail = ((req.query?.email ?? body.email) || '').toString().trim();
      if (!qmail) return bad(res, 'missing email', 400);

      try { await pendingDelete(qmail); } catch (e) { console.error('pendingDelete failed:', e); }
      try { await userDelete(qmail); }   catch (e) { /* optional, silent cleanup */ }

      return ok(res, { deleted: true, email: qmail });
    }

    return methodNotAllowed(res);
  } catch (e) {
    // Einmal zentral loggen, aber die Antwort kontrolliert halten
    console.error('admin/pending unhandled:', e);
    return bad(res, 'server error', 500);
  }
}
