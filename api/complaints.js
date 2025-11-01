// api/complaints.js
export const config = { runtime: 'nodejs' };

import jwt from 'jsonwebtoken';
import { setCors, noContent, ok, bad, methodNotAllowed, readJson } from './_lib/http.js';
import { complaintsAll, complaintSave, nextTicket } from './_lib/store.js';

const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret-change-me';

// ---- Auth aus Authorization: Bearer <token> ----
function requireUser(req) {
  const auth = req.headers?.authorization || '';
  const m = auth.match(/^Bearer\s+(.+)$/i);
  if (!m) return null;
  try {
    const payload = jwt.verify(m[1], JWT_SECRET);
    // erwartete Felder: payload.email (und optional id, company, ...)
    return payload && payload.email ? { email: String(payload.email).toLowerCase().trim(), payload } : null;
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

export default async function handler(req, res) {
  // Immer zuerst CORS setzen
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);

  const user = requireUser(req);
  if (!user) return bad(res, 'unauthorized', 401);

  // ===== GET: eigene Reklamationen des eingeloggten Nutzers =====
  if (req.method === 'GET') {
    const list = await complaintsAll();
    const own = Array.isArray(list)
      ? list.filter(c => (c?.email || '').toLowerCase().trim() === user.email)
           .sort((a, b) => (b?.updatedAt ?? b?.createdAt ?? 0) - (a?.updatedAt ?? a?.createdAt ?? 0))
      : [];
    return ok(res, own.map(toDto));
  }

  // ===== POST: neue Reklamation anlegen =====
  if (req.method === 'POST') {
    let body;
    try { body = readJson(req); } catch { return bad(res, 'invalid json', 400); }

    // payload: Pflichtfelder im Sinne deines Formulars
    const p = body?.payload || {};
    const segment   = (p.segment || '').toString();
    const article   = (p.article || '').toString();
    const desc      = (p.desc || '').toString();
    // optionale Felder:
    const batch     = (p.batch || '').toString();
    const qty       = (p.qty || '').toString();
    const expiry    = (p.expiry || '').toString();
    const applied   = (p.applied || '').toString();     // 'Ja'/'Nein' oder ''
    const injury    = (p.injury || '').toString();      // 'Ja'/'Nein' oder ''
    const injuryDesc= (p.injuryDesc || '').toString();
    const returned  = (p.returned || '').toString();    // 'Ja'/'Nein'
    const handling  = (p.handling || '').toString();    // 'Ersatz'/'Gutschrift'/'Nacharbeit'

    // Minimalprüfung wie im Frontend
    if (!article || !desc) return bad(res, 'required fields missing', 400);
    if (segment === 'Zahnarzt' && !batch) return bad(res, 'batch required for dentist', 400);

    // Uploads sind optional – falls dein Client Base64 mitsendet:
    // uploads: [{name, mime, data}]  (data = base64)
    const uploads = Array.isArray(body?.uploads) ? body.uploads.map(u => ({
      name: (u?.name || '').toString(),
      mime: (u?.mime || 'application/octet-stream').toString(),
      // Speichere hier NICHT die Rohdaten in Redis – nur Metadaten oder einen separaten Storage verwenden.
      // Für jetzt: nur Meta, damit UI die Anzahl anzeigen kann.
      size: Number(u?.size || 0),
    })) : [];

    const now = Date.now();
    const ticket = await nextTicket();

    const complaint = {
      ticket,
      email: user.email,
      payload: {
        segment, article, desc, batch, qty, expiry, applied, injury, injuryDesc, returned, handling,
      },
      uploads,            // nur Metadaten (siehe Kommentar oben)
      status: 1,          // 1 = Eingegegangen
      decision: null,     // noch keine Entscheidung
      reportLink: null,
      createdAt: now,
      updatedAt: now,
    };

    await complaintSave(complaint);
    return ok(res, { ok: true, ticket });
  }

  return methodNotAllowed(res);
}
