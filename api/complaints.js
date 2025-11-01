// api/complaints.js
export const config = { runtime: 'nodejs' };

import jwt from 'jsonwebtoken';
import { setCors, noContent, ok, bad, methodNotAllowed, readJson } from './_lib/http.js';
import { complaintsAll, complaintSave, nextTicket } from './_lib/store.js';

// ===== Konfiguration =====
const JWT_SECRET = process.env.JWT_SECRET || process.env.JWT || '';

// ---- JWT aus Authorization-Header lesen/prüfen ----
function requireUser(req) {
  const auth = req.headers?.authorization || req.headers?.Authorization || '';
  const m = auth.match(/^Bearer\s+(.+)$/i);
  if (!m) return null;
  try {
    const payload = jwt.verify(m[1], JWT_SECRET);
    const email = (payload?.email || payload?.sub || '').toString().trim().toLowerCase();
    return email ? { email, payload } : null;
  } catch {
    return null;
  }
}

// ---- schlanke DTO-Ausgabe für das Frontend ----
function toDto(c) {
  return {
    ticket: c.ticket,
    email: c.email,
    createdAt: c.createdAt ?? 0,
    updatedAt: c.updatedAt ?? c.createdAt ?? 0,
    status: c.status ?? 1,             // 1..6
    decision: c.decision ?? null,      // 'accepted' | 'rejected' | null
    reportLink: c.reportLink ?? null,  // optional
  };
}

// ---- Uploads robust parsen (unterstützt 'uploads' oder 'files' mit base64 'bytes') ----
function parseUploads(body) {
  const out = [];

  // Variante A: body.uploads[] mit {name, mime, size} (nur Meta)
  if (Array.isArray(body?.uploads)) {
    for (const u of body.uploads) {
      out.push({
        name: (u?.name || '').toString(),
        mime: (u?.mime || 'application/octet-stream').toString(),
        size: Number(u?.size || 0),
      });
    }
  }

  // Variante B: body.files[] mit {name, mime, bytes: <base64>} (aus deinem Client)
  if (Array.isArray(body?.files)) {
    for (const f of body.files) {
      const b64 = (f?.bytes || '').toString();
      // grobe Größenabschätzung aus base64-Länge
      const approxSize = Math.floor(b64.length * 3 / 4);
      out.push({
        name: (f?.name || '').toString(),
        mime: (f?.mime || 'application/octet-stream').toString(),
        size: approxSize > 0 ? approxSize : 0,
      });
    }
  }

  return out;
}

function sortDescByDate(a, b) {
  const ta = a?.updatedAt ?? a?.createdAt ?? 0;
  const tb = b?.updatedAt ?? b?.createdAt ?? 0;
  return (tb || 0) - (ta || 0);
}

export default async function handler(req, res) {
  // --- CORS IMMER zuerst ---
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);

  // --- Auth prüfen ---
  const user = requireUser(req);
  if (!user) return bad(res, 'unauthorized', 401);

  // ===== GET: eigene Reklamationen =====
  if (req.method === 'GET') {
    try {
      const list = await complaintsAll();
      const own = Array.isArray(list)
        ? list.filter(c => (c?.email || '').toString().trim().toLowerCase() === user.email).sort(sortDescByDate)
        : [];
      return ok(res, own.map(toDto));
    } catch {
      return bad(res, 'server error', 500);
    }
  }

  // ===== POST: neue Reklamation =====
  if (req.method === 'POST') {
    let body;
    try { body = readJson(req); } catch { return bad(res, 'invalid json', 400); }

    const p = body?.payload || {};
    const segment    = (p.segment || '').toString();
    const article    = (p.article || '').toString();
    const desc       = (p.desc || '').toString();

    // optional
    const batch      = (p.batch || '').toString();
    const qty        = (p.qty || '').toString();
    const expiry     = (p.expiry || '').toString();
    const applied    = (p.applied || '').toString();     // 'Ja'/'Nein' oder ''
    const injury     = (p.injury || '').toString();      // 'Ja'/'Nein' oder ''
    const injuryDesc = (p.injuryDesc || '').toString();
    const returned   = (p.returned || '').toString();    // 'Ja'/'Nein'
    const handling   = (p.handling || '').toString();    // 'Ersatz'/'Gutschrift'/'Nacharbeit'

    // Minimal-Validierung (wie im Frontend)
    if (!article || !desc) return bad(res, 'required fields missing', 400);
    if (segment === 'Zahnarzt' && !batch) return bad(res, 'batch required for dentist', 400);

    const uploads = parseUploads(body);   // nur Metadaten

    const now = Date.now();
    const ticket = await nextTicket();

    const complaint = {
      ticket,
      email: user.email,
      payload: {
        segment, article, desc, batch, qty, expiry, applied, injury, injuryDesc, returned, handling,
      },
      uploads,            // nur Metadaten (keine Base64-Daten in Redis)
      status: 1,          // 1 = Eingegegangen
      decision: null,     // noch keine Entscheidung
      reportLink: null,
      createdAt: now,
      updatedAt: now,
    };

    try {
      await complaintSave(complaint);
      return ok(res, { ok: true, ticket });
    } catch {
      return bad(res, 'server error', 500);
    }
  }

  return methodNotAllowed(res);
}
