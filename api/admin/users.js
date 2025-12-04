// api/admin/users.js
export const config = { runtime: 'nodejs' };

import {
  handlePreflight, setCors, ok, bad, methodNotAllowed, readJson
} from '../_lib/http.js';
import { usersList, userSave, userDelete, pendingDelete } from '../_lib/store.js';
import { requirePortalAccess } from './_guard.js';

export default async function handler(req, res) {
  // CORS-Header setzen + OPTIONS (Preflight) direkt beantworten
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { write: req.method !== 'GET' });
  if (!actor) return;

  try {
    // ---- LIST ----
    if (req.method === 'GET') {
      const list = await usersList();

      const out = list.map(u => ({
        email: u.email || '',
        company: u.company || '',
        contact: u.contact || '',
        street: u.street || '',
        zip: u.zip || '',
        city: u.city || '',
        country: u.country || '',
        phone: u.phone || '',
        lang: (u.lang || 'de'),
        createdAt: u.createdAt || null,
        revoked: !!u.revoked,
        selfDeleted: !!u.selfDeleted,
        // NEU: Kundennummer mitliefern, egal ob Feld bei dir customerNumber oder customer_no heißt
       customerNumber: u.customerNumber || u.customer_no || '',
      }));

      return ok(res, out);
    }

    // ---- REVOKE / UNREVOKE ----
    if (req.method === 'PATCH') {
      // erwartet: { email, revoked: true/false }
      const { email, revoked } = readJson(req) || {};
      const wanted = String(email || '').trim().toLowerCase();
      if (!wanted) return bad(res, 'missing email', 400);
      const list = await usersList();
      const u = list.find(x => String(x?.email || '').trim().toLowerCase() === wanted);

      if (!u) return bad(res, 'not found', 404);
      u.revoked = !!revoked;

      // Falls der Nutzer sein Konto selbst gelöscht hat, aber der Admin ihn wieder
      // freigibt, entfernen wir die Self-Delete-Markierung, damit entsprechende
      // Hinweise in der UI verschwinden.
      if (!u.revoked) {
        u.selfDeleted = false;
        u.revokedAt = null;
        u.deletedAt = null;
      }

      await userSave(u);
      return ok(res, { ok: true });
    }

    // ---- DELETE (robust) ----
    if (req.method === 'DELETE') {
      const body = readJson(req) || {};
      const wanted = (req.query?.email || body.email || '').toString().trim().toLowerCase();
      if (!wanted) return bad(res, 'missing email', 400);
      await userDelete(wanted);
      
      // pending ggf. mit aufräumen (failsafe)
      try { await pendingDelete(email); } catch (_) {}
      return ok(res, { deleted: true, email: wanted });
    }

    // ---- POST: Aktionen (z. B. delete, updateCustomerNumber) ----
    if (req.method === 'POST') {
      const body = readJson(req) || {};
      const action = (body.action || '').toString().trim();

      // 1) Kundennummer aktualisieren
      if (action === 'updateCustomerNumber') {
        const email = (body.email || '').toString().trim().toLowerCase();
        if (!email) return bad(res, 'missing email', 400);

        const list = await usersList();
        const u = list.find(
          x => (x?.email || '').toString().trim().toLowerCase() === email
        );
        if (!u) return bad(res, 'not found', 404);

        const customerNumber = (body.customerNumber || '').toString().trim();
        // hier schreiben wir es in das User-Objekt
        u.customerNumber = customerNumber;

        await userSave(u);
        return ok(res, { ok: true, email, customerNumber });
      }

      // 2) Nutzer löschen (wie bisher)
      if (action === 'delete') {
        const wanted = (body.email || '').toString().trim().toLowerCase();
        if (!wanted) return bad(res, 'missing email', 400);
        await userDelete(wanted);
        return ok(res, { deleted: true, email: wanted });
      }

      return bad(res, 'unknown action', 400);
    }
    
    return methodNotAllowed(res);
  } catch (e) {
    return bad(res, e?.message || String(e), 500);
  }
}
