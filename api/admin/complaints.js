// api/admin/complaints.js
export const config = { runtime: 'nodejs' };

import { setCors, noContent, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { complaintsAll, complaintByTicket, complaintSave } from '../_lib/store.js';

const ADMIN_SECRET = process.env.ADMIN_SECRET || '';
const isAdmin = (req) => ADMIN_SECRET && req.headers?.['x-admin-secret'] === ADMIN_SECRET;

// Zulässige Stati (bestehende String-Variante beibehalten)
const STATES = [
  'Eingegegangen',            // 1
  'In Bearbeitung',           // 2
  'Rückfrage erforderlich',   // 3
  'Angenommen / Genehmigt',   // 4 (hellgrün im Frontend)
  'Abgelehnt',                // 4 (rot, gilt als abgeschlossen)
  'In Nacharbeit',            // 5 (optional)
  'Abgeschlossen'             // 6 (grün, wenn vorher angenommen)
];

// kleine Helper
function normalizeEmail(v) {
  return (v || '').toString().trim().toLowerCase();
}
function sortDescByDate(a, b) {
  const ta = a?.createdAt ?? a?.updatedAt ?? 0;
  const tb = b?.createdAt ?? b?.updatedAt ?? 0;
  return (tb || 0) - (ta || 0);
}

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);
  if (!isAdmin(req)) return bad(res, 'admin unauthorized', 401);

  // ======== GET: alle oder gefiltert nach ?email= ========
  if (req.method === 'GET') {
    const email = normalizeEmail(req.query?.email);
    const list = await complaintsAll();            // nutzt deinen Store
    if (!Array.isArray(list)) return ok(res, []);  // robust

    const out = email
      ? list.filter(c => normalizeEmail(c?.email) === email).sort(sortDescByDate)
      : list.sort(sortDescByDate);

    return ok(res, out);
  }

  // ======== PATCH: Status/Decision/ReportLink anpassen ========
  if (req.method === 'PATCH') {
    let body;
    try {
      body = readJson(req);
    } catch {
      return bad(res, 'invalid json', 400);
    }

    const ticket     = (body?.ticket || '').toString().trim();
    const status     = body?.status;          // optional
    const decision   = body?.decision ?? null; // 'accepted' | 'rejected' | null
    const reportLink = body?.reportLink;      // optional string|null

    if (!ticket) return bad(res, 'missing ticket', 400);

    const c = await complaintByTicket(ticket);
    if (!c) return bad(res, 'not found', 404);

    // --- Status prüfen (wenn übergeben) ---
    if (status != null) {
      if (!STATES.includes(status)) return bad(res, 'invalid status', 400);
      c.status = status;
      c.statusUpdatedAt = Date.now();
    }

    // --- Decision (optional) verarbeiten ---
    // Entscheidung nur 'accepted' | 'rejected' | null zulassen
    if (decision !== undefined) {
      if (decision !== null && decision !== 'accepted' && decision !== 'rejected') {
        return bad(res, 'invalid decision', 400);
      }
      c.decision = decision || null;

      // Business-Logik:
      // Wenn abgelehnt => automatisch abgeschlossen (rot), wie von dir gewünscht.
      if (c.decision === 'rejected') {
        c.status = 'Abgelehnt';      // rot
        c.closed = true;
        c.closedAt = Date.now();
        c.statusUpdatedAt = Date.now();
      }
      // Wenn accepted und Status explizit „Abgeschlossen“ gesetzt wird, ist es regulär abgeschlossen.
      // (Kein Auto-Close hier — das steuerst du über den Status selbst.)
    }

    // --- Report-Link (optional) ---
    if (reportLink !== undefined) {
      c.reportLink = reportLink || null;
    }

    // UpdatedAt setzen
    c.updatedAt = Date.now();

    await complaintSave(c);
    return ok(res, { ok: true, ticket: c.ticket, status: c.status, decision: c.decision, reportLink: c.reportLink });
  }

  return methodNotAllowed(res);
}
