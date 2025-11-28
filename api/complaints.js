// /api/complaints.js
export const config = { runtime: 'nodejs' };

import jwt from 'jsonwebtoken';
import {
  handlePreflight, ok, bad, methodNotAllowed, readJson
} from './_lib/http.js';
import { complaintsAll, complaintSave, nextTicket, Status } from './_lib/store.js';
import {
  blobUploadsEnabled,
  normalizeProvidedUploads,
  processIncomingFiles,
} from './_lib/uploads.js';

const JWT_SECRET = process.env.JWT_SECRET || process.env.JWT || '';

/* ---- JWT prüfen ---- */
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

/* ---- DTO fürs Frontend ---- */
function toDto(c) {
  return {
    ticket: c.ticket,
    email: c.email,
    createdAt: c.createdAt ?? 0,
    updatedAt: c.updatedAt ?? c.createdAt ?? 0,
    status: c.status ?? 1,
    decision: c.decision ?? null,
    reportLink: c.reportLink ?? null,
  };
}

/* ---- Sortierhilfe ---- */
function sortDescByDate(a, b) {
  const ta = a?.updatedAt ?? a?.createdAt ?? 0;
  const tb = b?.updatedAt ?? b?.createdAt ?? 0;
  return (tb || 0) - (ta || 0);
}

export default async function handler(req, res) {
  // --- CORS zuerst (setzt Header & beantwortet OPTIONS mit 204) ---
  if (handlePreflight(req, res)) {
    console.log('[CORS] Preflight answered for /api/complaints');
    return;
  }

  // --- Auth prüfen ---
  const user = requireUser(req);
  if (!user) {
    console.warn('[CORS/Auth] Unauthorized access attempt to /api/complaints');
    return bad(res, 'unauthorized', 401);
  }

  try {
    // ===== GET: eigene Reklamationen =====
    if (req.method === 'GET') {
      const list = await complaintsAll();
      const own = Array.isArray(list)
        ? list.filter(c => (c?.email || '').toString().trim().toLowerCase() === user.email)
        : [];
      own.sort(sortDescByDate);
      return ok(res, own.map(toDto));
    }

    // ===== POST: neue Reklamation =====
    if (req.method === 'POST') {
      const body = readJson(req);
      const p = body?.payload || {};
      const files = Array.isArray(body?.files) ? body.files : [];
      const providedUploads = normalizeProvidedUploads(body?.uploads);

      const segment    = String(p.segment || '');
      const article    = String(p.article || '');
      const desc       = String(p.desc || '');
      const batch      = String(p.batch || '');
      const qty        = String(p.qty || '');
      const expiry     = String(p.expiry || '');
      const applied    = String(p.applied || '');
      const injury     = String(p.injury || '');
      const injuryDesc = String(p.injuryDesc || '');
      const returned   = String(p.returned || '');
      const handling   = String(p.handling || '');

      // Pflichtfelder prüfen
      if (!article || !desc) return bad(res, 'required fields missing', 400);
      if (segment === 'Zahnarzt' && !batch)
        return bad(res, 'batch required for dentist', 400);

      let ticketPromise;
      const ensureTicket = () => {
        ticketPromise = ticketPromise || nextTicket();
        return ticketPromise;
      };

      let processedFiles;
      try {
        processedFiles = await processIncomingFiles(files, {
          ticket: ensureTicket,
          allowPreviewFallback: !blobUploadsEnabled,
        });
      } catch (err) {
        const msg = err?.message === 'files too large'
          ? 'files too large'
          : err?.message === 'invalid file encoding'
            ? 'invalid file encoding'
            : 'file upload failed';
        return bad(res, msg, 400);
      }

      const ticket = await ensureTicket();
      const uploads = [...providedUploads, ...processedFiles.uploads];
      const now = Date.now();

      const complaint = {
        ticket,
        email: user.email,
        payload: {
          segment, article, desc, batch, qty, expiry,
          applied, injury, injuryDesc, returned, handling
        },
        uploads,
        status: Status.RECEIVED,
        decision: null,
        reportLink: null,
        createdAt: now,
        updatedAt: now,
      };

      await complaintSave(complaint);
      return ok(res, { ok: true, ticket });
    }

    return methodNotAllowed(res);
  } catch (e) {
    console.error('complaints.js error:', e);
    return bad(res, 'server error', 500);
  }
}
