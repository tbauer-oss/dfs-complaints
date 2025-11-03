// api/admin/complaints.js
export const config = { runtime: 'nodejs' };

import {
  handlePreflight,
  setCors,
  ok,
  bad,
  methodNotAllowed,
  readJson,
  noContent,
} from '../_lib/http.js';

const ADMIN_SECRET = process.env.ADMIN_SECRET || '';
const isAdmin = (req) =>
  !!ADMIN_SECRET && req?.headers?.['x-admin-secret'] === ADMIN_SECRET;

// ---- Status-Mapping: intern numerisch (1..6), Admin-UI bekommt Label dazu ----
const STATUS_LABEL = {
  1: 'Eingegegangen',
  2: 'In Bearbeitung',
  3: 'Rückfrage erforderlich',
  4: 'Entscheidung', // Decision steht separat
  5: 'In Nacharbeit',
  6: 'Abgeschlossen',
};
const STATUS_CODE = Object.fromEntries(
  Object.entries(STATUS_LABEL).map(([k, v]) => [v, Number(k)])
);

/** akzeptiert Zahl 1..6, numerische Strings "1".."6" oder Label-Strings */
function parseStatus(input) {
  if (input == null) return null;
  if (typeof input === 'number') {
    const n = Number(input);
    return n >= 1 && n <= 6 ? n : null;
  }
  if (typeof input === 'string') {
    const s = input.trim();
    if (/^\d+$/.test(s)) {
      const n = Number(s);
      return n >= 1 && n <= 6 ? n : null;
    }
    return STATUS_CODE[s] ?? null;
  }
  return null;
}

// ---- Helpers ----
const normEmail = (v = '') => v.toString().trim().toLowerCase();
const sortDescByDate = (a, b) => {
  const ta = a?.updatedAt ?? a?.createdAt ?? 0;
  const tb = b?.updatedAt ?? b?.createdAt ?? 0;
  return (tb || 0) - (ta || 0);
};
const decorateForAdmin = (c) => ({
  ...c,
  statusLabel: STATUS_LABEL[c.status] || STATUS_LABEL[1],
});

export default async function handler(req, res) {
  // 1) Preflight zuerst (setzt CORS, beantwortet OPTIONS 204)
  if (handlePreflight(req, res)) return;

  // 2) Für alle weiteren Antworten CORS setzen
  setCors(req, res);

  // 3) Admin-Auth
  if (!isAdmin(req)) return bad(res, 'admin unauthorized', 401);

  // 4) Schwere Module erst jetzt laden (verhindert Preflight-/CORS-Brüche)
  let store;
  try {
    store = await import('../_lib/store.js');
  } catch (e) {
    console.error('admin/complaints lazy import failed:', e);
    return bad(res, 'server error (imports)', 500);
  }

  const {
    complaintsAll,
    complaintsOpen,
    complaintsByEmail,
    complaintByTicket,
    complaintSave,
    complaintDelete,
  } = store;

  try {
    // ===========================
    // GET: verschiedene Modi
    // ===========================
    if (req.method === 'GET') {
      // Query robust lesen
      const url = new URL(req.url, 'http://x');
      const email   = normEmail(url.searchParams.get('email') || '');
      const ticket  = (url.searchParams.get('ticket') || '').toString().trim();
      const open    = (url.searchParams.get('open') || '').toString().trim();
      const details = (url.searchParams.get('details') || '').toString().trim();

      // a) Einzel-Complaint per Ticket (inkl. payload)
      if (ticket) {
        const c = await complaintByTicket(ticket);
        if (!c) return bad(res, 'not found', 404);
        return ok(res, decorateForAdmin(c));
      }

      // b) Complaints eines Kunden (Tickets oder Detailobjekte)
      if (email) {
        const list = await complaintsByEmail(email);
        list.sort(sortDescByDate);
        if (details === '1') {
          return ok(res, list.map(decorateForAdmin));
        }
        // Kompakt: nur Ticket-IDs (Backwards-Kompatibilität)
        return ok(res, list.map((c) => c.ticket));
      }

      // c) Nur offene Reklamationen
      if (open === '1') {
        const list = await complaintsOpen();
        return ok(res, list.map(decorateForAdmin));
      }

      // d) Alle Reklamationen (Admin-Übersicht)
      const all = await complaintsAll();
      const out = (Array.isArray(all) ? all : [])
        .sort(sortDescByDate)
        .map(decorateForAdmin);
      return ok(res, out);
    }

    // ======================================
    // POST / PATCH: Status/Decision/Report
    // ======================================
    if (req.method === 'POST' || req.method === 'PATCH') {
      const body = readJson(req);

      const ticket     = (body?.ticket || '').toString().trim();
      const statusIn   = body?.status;                // Zahl 1..6 | "1".."6" | Label
      const decisionIn = body?.decision ?? undefined; // 'accepted' | 'rejected' | null | undefined
      const reportLink = body?.reportLink;            // string | null | undefined

      if (!ticket) return bad(res, 'missing ticket', 400);

      const c = await complaintByTicket(ticket);
      if (!c) return bad(res, 'not found', 404);

      // --- Status (optional) ---
      if (statusIn !== undefined) {
        const code = parseStatus(statusIn);
        if (code == null) return bad(res, 'invalid status', 400);
        c.status = code;
        c.statusUpdatedAt = Date.now();
      }

      // --- Decision (optional) ---
      if (decisionIn !== undefined) {
        if (decisionIn !== null && decisionIn !== 'accepted' && decisionIn !== 'rejected') {
          return bad(res, 'invalid decision', 400);
        }
        c.decision = decisionIn ?? null;

        // Business-Logik:
        // Bei 'rejected' bleibt Status 4 (= Entscheidung), gilt als geschlossen (für Offenen-Liste).
        if (c.decision === 'rejected') {
          c.closed = true;
          c.closedAt = Date.now();
          c.status = 4;
          c.statusUpdatedAt = Date.now();
        }
        // Bei 'accepted' kein Auto-Abschluss – Abschluss explizit mit Status 6.
      }

      // --- Report-Link (optional) ---
      if (reportLink !== undefined) {
        c.reportLink = reportLink || null;
      }

      // Timestamps & Persist
      c.updatedAt = Date.now();
      await complaintSave(c);

      return ok(res, {
        ticket: c.ticket,
        status: c.status,
        statusLabel: STATUS_LABEL[c.status] || STATUS_LABEL[1],
        decision: c.decision ?? null,
        reportLink: c.reportLink ?? null,
        updatedAt: c.updatedAt,
      });
    }

    // ===== DELETE: Complaint löschen =====
    if (req.method === 'DELETE') {
      // ticket aus ?ticket=... oder Body
      const url = new URL(req.url, 'http://x');
      let ticket = (url.searchParams.get('ticket') || '').toString().trim();

      if (!ticket && req.body) {
        try {
          const b =
            typeof req.body === 'string'
              ? JSON.parse(req.body || '{}')
              : req.body;
          ticket = (b?.ticket || '').toString().trim();
        } catch (_) {}
      }

      if (!ticket) return bad(res, 'missing ticket', 400);

      const c = await complaintByTicket(ticket);
      if (!c) return bad(res, 'not found', 404);

      await complaintDelete(ticket);
      return noContent(res); // 204
    }

    return methodNotAllowed(res); // 405
  } catch (e) {
    console.error('admin/complaints error:', e);
    return bad(res, e?.message || 'server error', 500);
  }
}
