// api/admin/complaints.js
export const config = { runtime: 'nodejs' };

import {
  setCors,
  ok,
  bad,
  noContent,
  methodNotAllowed,
  readJson,
} from '../_lib/http.js';

import {
  complaintsAll,
  complaintsOpen,
  complaintsByEmail,
  complaintByTicket,
  complaintSave,
  complaintDelete,
} from '../_lib/store.js';

// -------- Admin-Auth ----------
const ADMIN_SECRET = process.env.ADMIN_SECRET || '';
const isAdmin = (req) =>
  ADMIN_SECRET && req.headers?.['x-admin-secret'] === ADMIN_SECRET;

// -------- Status-Mapping ----------
const STATUS_LABEL = {
  1: 'Eingegegangen',
  2: 'In Bearbeitung',
  3: 'Rückfrage erforderlich',
  4: 'Entscheidung',
  5: 'In Nacharbeit',
  6: 'Abgeschlossen',
};

const STATUS_CODE = Object.fromEntries(
  Object.entries(STATUS_LABEL).map(([k, v]) => [v, Number(k)])
);

/** Akzeptiert: Zahl 1..6, numerischer String "1".."6" oder Label-String */
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

// -------- Helpers ----------
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

// =======================================================
// Handler
// =======================================================
export default async function handler(req, res) {
  // 1) CORS-Header IMMER zuerst setzen
  try { setCors(req, res); } catch (_) {}

  // 2) OPTIONS (Preflight) sofort beantworten – ohne Admin-Auth
  if (req.method === 'OPTIONS') return noContent(res);

  // 3) Ab hier Admin-Auth prüfen
  if (!isAdmin(req)) return bad(res, 'admin unauthorized', 401);

  try {
    // ----------------------------
    // GET
    // ----------------------------
    if (req.method === 'GET') {
      const q = req.query || {};
      const email   = normEmail(q.email || '');
      const ticket  = (q.ticket || '').toString().trim();
      const open    = (q.open || '').toString().trim();
      const details = (q.details || '').toString().trim();

      // a) Einzel-Complaint per Ticket
      if (ticket) {
        const c = await complaintByTicket(ticket);
        if (!c) return bad(res, 'not found', 404);
        return ok(res, decorateForAdmin(c));
      }

      // b) Complaints eines Kunden
      if (email) {
        const list = await complaintsByEmail(email);
        list.sort(sortDescByDate);
        if (details === '1') {
          return ok(res, list.map(decorateForAdmin));
        }
        // kompakte Antwort: nur Ticket-IDs
        return ok(res, list.map((c) => c.ticket));
      }

      // c) Nur offene Reklamationen
      if (open === '1') {
        const list = await complaintsOpen();
        return ok(res, list.map(decorateForAdmin));
      }

      // d) Alle Reklamationen
      const all = await complaintsAll();
      const out = (Array.isArray(all) ? all : [])
        .sort(sortDescByDate)
        .map(decorateForAdmin);
      return ok(res, out);
    }

    // ----------------------------
    // POST / PATCH – Status / Decision / Report
    // ----------------------------
    if (req.method === 'POST' || req.method === 'PATCH') {
      // Body robust parsen
      let body = readJson(req);
      if (typeof body === 'string') {
        try { body = JSON.parse(body); } catch { /* ignore */ }
      }
      if (typeof body === 'string') body = { ticket: body };
      if (!body || typeof body !== 'object') body = {};

      const ticket     = (body?.ticket || '').toString().trim();
      const statusIn   = body?.status;                // 1..6 | "1".."6" | Label
      const decisionIn = body?.decision;              // 'accepted' | 'rejected' | "" | null | undefined
      const reportLink = body?.reportLink;            // string | "" | null | undefined

      if (!ticket) return bad(res, 'missing ticket', 400);

      const c = await complaintByTicket(ticket);
      if (!c) return bad(res, 'not found', 404);

      // ---- Status (optional) ----
      if (statusIn !== undefined) {
        const code = parseStatus(statusIn);
        if (code == null) return bad(res, 'invalid status', 400);
        c.status = code;
        c.statusUpdatedAt = Date.now();
      }

      // ---- Decision (optional) ----
      const rawDecision = body?.decision;
      const decisionIn = (rawDecision === '') ? null : rawDecision;

      if (rawDecision !== undefined) {  // Key wurde gesendet (auch '')
        if (decisionIn !== null && decisionIn !== 'accepted' && decisionIn !== 'rejected') {
          return bad(res, 'invalid decision', 400);
        }
        c.decision = decisionIn;  // null | 'accepted' | 'rejected'

        // Business-Logik:
        if (c.decision === 'rejected') {
          c.closed = true;
          c.closedAt = Date.now();
          c.status = 4;                 // Entscheidung (systemgesetzt)
          c.statusUpdatedAt = Date.now();
        } else {
          // bei accepted oder null: NICHT auto-schließen
          if (c.closed) { delete c.closed; delete c.closedAt; }
        }
      }
      
      // ---- Report-Link (optional; leer => löschen) ----
      if (reportLink !== undefined) {
        const v = (reportLink ?? '').toString().trim();
        if (v) c.reportLink = v;
        else delete c.reportLink;
      }

      // Persist
      c.updatedAt = Date.now();

      // robust speichern (bevorzugt keyed, Fallback full)
      try {
        await complaintSave(ticket, c);
      } catch {
        await complaintSave({ ...c });
      }

      return ok(res, {
        ticket: c.ticket,
        status: c.status,
        statusLabel: STATUS_LABEL[c.status] || STATUS_LABEL[1],
        decision: c.decision ?? null,
        reportLink: c.reportLink ?? null,
        updatedAt: c.updatedAt,
      });
    }

    // ----------------------------
    // DELETE – Complaint löschen
    // ----------------------------
    if (req.method === 'DELETE') {
      // ticket aus ?ticket=... oder Body
      let ticket = (req.query?.ticket || '').toString().trim();
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
      return noContent(res);
    }

    return methodNotAllowed(res);
  } catch (e) {
    console.error('admin/complaints error:', e);
    return bad(res, e?.message || 'server error', 500);
  }
}
