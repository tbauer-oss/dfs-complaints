// api/admin/complaints/index.js
export const config = { runtime: 'nodejs' };

import { setCors, ok, bad, noContent, methodNotAllowed } from '../../_lib/http.js';
import { getAdmin } from '../../_lib/auth.js';
// Passen ggf. die Namen an, falls deine store.js abweicht:
import {
  complaintGet,        // (ticket) => complaint | null
  complaintSave,       // (complaint) => void
  complaintsByEmail,   // (email) => []
  complaintsOpen,      // () => []  (alle offenen)
  Status,              // enum/const mit SENT.., CLOSED (hier 6)
} from '../../_lib/store.js';
import { generateDualReportsForComplaint } from '../../_lib/reporting.js';
import { normalizeReportLinksMap } from '../../_lib/departments.js';

function normBody(req) {
  let b = req.body;
  if (typeof b === 'string') {
    try { b = JSON.parse(b); }
    catch { b = { ticket: b }; }
  }
  if (!b || typeof b !== 'object') b = {};
  return b;
}

function strOrUndef(v) {
  if (v === undefined || v === null) return undefined;
  const s = String(v);
  return s;
}

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);

  // --- Admin-Auth ---
  const admin = getAdmin?.(req);
  if (!admin) return bad(res, 'unauthorized', 401);

  // ---------- GET ----------
  // /api/admin/complaints?email=...&details=1
  // /api/admin/complaints?open=1
  // /api/admin/complaints?ticket=DFS_CP000001
  if (req.method === 'GET') {
    const q = req.query || {};

    if (q.ticket) {
      const c = await complaintGet(String(q.ticket));
      if (!c) return bad(res, 'not found', 404);
      return ok(res, c);
    }

    if (q.open) {
      const list = await complaintsOpen();
      return ok(res, list);
    }

    if (q.email) {
      const list = await complaintsByEmail(String(q.email));
      // details=1 → gleiche Struktur; (du hattest es im FE so vorgesehen)
      return ok(res, list);
    }

    // Fallback: nichts Konkretes angefragt
    return bad(res, 'missing query', 400);
  }

  // ---------- POST (Update) ----------
  // Body erlaubt: { ticket, status?, decision?, reportLink? }
  // Besonderheiten:
  // - decision: ""  -> null (löschen)
  // - reportLink: "" -> null (löschen)
  if (req.method === 'POST') {
    const b = normBody(req);

    const ticket = strOrUndef(b.ticket) || strOrUndef(req.query?.ticket);
    if (!ticket) return bad(res, 'ticket required', 400);

    const c = await complaintGet(ticket);
    if (!c) return bad(res, 'not found', 404);

    // status optional, muss Zahl sein
    if (b.status !== undefined && b.status !== null && b.status !== '') {
      const n = Number(b.status);
      if (!Number.isFinite(n)) return bad(res, 'invalid status', 400);
      c.status = n;
    }

    // decision: "", null => null
    if ('decision' in b) {
      const d = (typeof b.decision === 'string') ? b.decision.trim() : b.decision;
      c.decision = d ? String(d) : null;
    }

    // reportLink: "" => null
    if ('reportLink' in b) {
      const rl = (b.reportLink === '') ? null : strOrUndef(b.reportLink);
      c.reportLink = rl ?? null;
    }

    if (c.status === Status.CLOSED) {
      try {
        const generated = await generateDualReportsForComplaint(c, { preferredLang: b.reportLang || b.reportLanguage });
        if (generated) {
          const mergedExternal = normalizeReportLinksMap({ ...(c.externalReportLinks || {}), ...(generated.externalLinks || {}) });
          const mergedInternal = normalizeReportLinksMap({ ...(c.internalReportLinks || {}), ...(generated.internalLinks || {}) });
          const mergedReportLinks = normalizeReportLinksMap({ ...(c.reportLinks || {}), ...(generated.externalLinks || {}) });
          const defaultLink = mergedExternal[generated.lang]
            || mergedExternal.de
            || mergedExternal.en
            || Object.values(mergedExternal)[0]
            || mergedInternal[generated.lang]
            || mergedInternal.de
            || mergedInternal.en
            || Object.values(mergedInternal)[0];
          if (Object.keys(mergedExternal).length > 0) c.externalReportLinks = mergedExternal;
          if (Object.keys(mergedInternal).length > 0) c.internalReportLinks = mergedInternal;
          if (Object.keys(mergedReportLinks).length > 0) c.reportLinks = mergedReportLinks;
          if (defaultLink) c.reportLink = defaultLink;
        }
      } catch (err) {
        console.error('[admin/complaints:index] report generation failed', err?.message || err);
      }
    }

    c.updatedAt = Date.now();

    await complaintSave(c);
    return ok(res, c);
  }

  // ---------- DELETE ----------
  // ?ticket=... ODER Body {ticket:"..."}
  if (req.method === 'DELETE') {
    const b = normBody(req);
    const ticket = strOrUndef(b.ticket) || strOrUndef(req.query?.ticket);
    if (!ticket) return bad(res, 'ticket required', 400);

    const c = await complaintGet(ticket);
    if (!c) return bad(res, 'not found', 404);

    // "Löschen" hier: auf CLOSED setzen? Oder wirklich entfernen?
    // Falls du echtes Löschen willst, ersetze diese Zeilen durch complaintDelete(ticket).
    c.status = typeof Status?.CLOSED === 'number' ? Status.CLOSED : 5;
    c.updatedAt = Date.now();
    await complaintSave(c);

    return ok(res, c);
  }

  return methodNotAllowed(res);
}
