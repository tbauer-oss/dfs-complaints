// api/admin/complaints.js
export const config = { runtime: 'nodejs' };

import { setCors, noContent, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { complaintsAll, complaintByTicket, complaintSave } from '../_lib/store.js';

const ADMIN_SECRET = process.env.ADMIN_SECRET || '';
const isAdmin = (req) => ADMIN_SECRET && req.headers?.['x-admin-secret'] === ADMIN_SECRET;

// ---- Status-Mapping: intern numerisch (1..6), für Admin-UI zusätzlich Label ----
const STATUS_CODE = {
  'Eingegegangen': 1,
  'In Bearbeitung': 2,
  'Rückfrage erforderlich': 3,
  'Angenommen / Genehmigt': 4, // decision = 'accepted'
  'Abgelehnt': 4,               // decision = 'rejected' (geschlossen)
  'In Nacharbeit': 5,
  'Abgeschlossen': 6,
};
const STATUS_LABEL = {
  1: 'Eingegegangen',
  2: 'In Bearbeitung',
  3: 'Rückfrage erforderlich',
  4: 'Entscheidung',         // Label neutral; Entscheidung steht in c.decision
  5: 'In Nacharbeit',
  6: 'Abgeschlossen',
};
function parseStatus(input) {
  if (input == null) return null;
  if (typeof input === 'number') {
    const n = Number(input);
    return n >= 1 && n <= 6 ? n : null;
  }
  if (typeof input === 'string') {
    const s = input.trim();
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
  statusLabel: STATUS_LABEL[c.status] || 'Eingegegangen',
});

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);
  if (!isAdmin(req)) return bad(res, 'admin unauthorized', 401);

  // ===== GET: alle oder gefiltert nach ?email= =====
  if (req.method === 'GET') {
    const email = normEmail(req.query?.email || '');
    const list = await complaintsAll();
    if (!Array.isArray(list)) return ok(res, []);
    const filtered = email
      ? list.filter((c) => normEmail(c?.email) === email)
      : list;
    const out = filtered.sort(sortDescByDate).map(decorateForAdmin);
    return ok(res, out);
  }

  // ===== PATCH: Status / Decision / ReportLink setzen =====
  if (req.method === 'PATCH') {
    let body;
    try { body = readJson(req); } catch { return bad(res, 'invalid json', 400); }

    const ticket     = (body?.ticket || '').toString().trim();
    const statusIn   = body?.status;                 // Zahl 1..6 ODER Label-String
    const decisionIn = body?.decision ?? undefined;  // 'accepted' | 'rejected' | null | undefined
    const reportLink = body?.reportLink;             // optional String | null

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
      // Bei 'rejected' schließen wir den Vorgang (Status bleibt 4 = Entscheidung).
      if (c.decision === 'rejected') {
        c.closed = true;
        c.closedAt = Date.now();
        c.status = 4; // bleibt im "Entscheidung"-Code
        c.statusUpdatedAt = Date.now();
      }

      // Bei 'accepted' NICHT automatisch schließen; Abschluss erfolgt mit Status 6.
    }

    // --- Report-Link (optional) ---
    if (reportLink !== undefined) c.reportLink = reportLink || null;

    // Timestamps
    c.updatedAt = Date.now();

    await complaintSave(c);
    return ok(res, {
      ok: true,
      ticket: c.ticket,
      status: c.status,
      statusLabel: STATUS_LABEL[c.status] || 'Eingegegangen',
      decision: c.decision ?? null,
      reportLink: c.reportLink ?? null,
    });
  }

  return methodNotAllowed(res);
}
