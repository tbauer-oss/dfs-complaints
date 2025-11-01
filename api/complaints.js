// api/complaints.js
export const config = { runtime: 'nodejs' };

import jwt from 'jsonwebtoken';
import { setCors, noContent, ok, bad, methodNotAllowed, readJson } from './_lib/http.js';

// Versuche: zentrale Store-Funktionen nutzen, falls vorhanden
// (Passe die Importnamen an, falls dein store andere Namen verwendet.)
import {
  nextTicket as _nextTicket,
  complaintListByEmail as _complaintsByEmail,
  complaintSave as _complaintSave,
} from './_lib/store.js';

// Fallback, falls du (noch) keine Store-Funktionen exportierst
import { Redis } from '@upstash/redis';

const redis = (process.env.REDIS_URL && process.env.REDIS_TOKEN)
  ? new Redis({ url: process.env.REDIS_URL, token: process.env.REDIS_TOKEN })
  : null;

const P = 'dfs:'; // Prefix wie in deinem store.js
const mem = {
  complaints: new Map(),     // key: ticket -> complaint
  counters: { ticket: 0 },
};

// ---------- Helpers ----------
function requireAuth(req, res) {
  const hdr = req.headers?.authorization || '';
  const m = /^Bearer\s+(.+)$/.exec(hdr);
  if (!m) { bad(res, 'unauthorized', 401); return null; }

  const secret = process.env.JWT_SECRET || process.env.JWT_KEY || '';
  if (!secret) { bad(res, 'server misconfigured (JWT_SECRET missing)', 500); return null; }

  try {
    const decoded = jwt.verify(m[1], secret);
    const email = decoded?.email || decoded?.sub || '';
    if (!email) { bad(res, 'unauthorized', 401); return null; }
    return { email, jwt: decoded };
  } catch {
    bad(res, 'unauthorized', 401);
    return null;
  }
}

async function nextTicket() {
  if (_nextTicket) return await _nextTicket();
  if (redis) {
    const n = await redis.incr(`${P}counter:ticket`);
    return `DFS_CP${String(n).padStart(6, '0')}`;
  }
  mem.counters.ticket += 1;
  return `DFS_CP${String(mem.counters.ticket).padStart(6, '0')}`;
}

async function complaintSave(obj) {
  if (_complaintSave) return await _complaintSave(obj);
  const key = `${P}complaint:${obj.ticket}`;
  if (redis) return await redis.set(key, obj);
  mem.complaints.set(obj.ticket, obj);
  return true;
}

async function complaintsByEmail(email) {
  if (_complaintsByEmail) return await _complaintsByEmail(email);

  if (redis) {
    // Kein Scan hier – einfache Speicherung als Set pro Nutzer
    const ids = (await redis.smembers(`${P}complaints:by:${email}`)) || [];
    const all = await Promise.all(ids.map(id => redis.get(`${P}complaint:${id}`)));
    return (all || []).filter(Boolean);
  }
  // Memory-Fallback
  return [...mem.complaints.values()].filter(c => c.email === email);
}

async function indexByEmail(email, ticket) {
  if (redis) {
    await redis.sadd(`${P}complaints:by:${email}`, ticket);
  } else {
    // nichts notwendig für mem
  }
}

// ---------- Uploads „sicher“ normalisieren ----------
function normalizeUploads(arr) {
  if (!Array.isArray(arr)) return [];
  // Erwartet: { name, mime, data } mit data = base64-String
  return arr
    .map((u) => ({
      name: String(u?.name || '').slice(0, 120),
      mime: String(u?.mime || 'application/octet-stream'),
      // wir speichern **nur** Base64 (oder gar nichts) – keine Binärgrößen in Redis explodieren lassen
      data: typeof u?.data === 'string' ? u.data : '',
    }))
    // nur kleine Anhänge akzeptieren (z. B. je max. 2 MB base64 -> ca. 2.6 MB String)
    .filter((u) => u.name && u.data && u.data.length <= 2_800_000);
}

// ---------- Handler ----------
export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);

  // Auth erzwingen
  const auth = requireAuth(req, res);
  if (!auth) return;
  const email = auth.email;

  if (req.method === 'GET') {
    try {
      const list = await complaintsByEmail(email);

      // Sicherer DTO fürs Frontend
      const safe = (list || []).map(c => ({
        ticket: c.ticket,
        email: c.email,
        createdAt: c.createdAt,
        updatedAt: c.updatedAt,
        status: c.status,
        decision: c.decision ?? null,
        reportLink: c.reportLink ?? null,
        // KEINE payload/Uploads zurückgeben
      })).sort((a, b) => (b.updatedAt ?? 0) - (a.updatedAt ?? 0));

      return ok(res, safe);
    } catch (e) {
      return bad(res, 'failed to list complaints', 500);
    }
  }

  if (req.method === 'POST') {
    try {
      const body = readJson(req);
      const now = Date.now();

      // Minimal-Validierung
      const payload = body?.payload && typeof body.payload === 'object' ? body.payload : {};
      const uploads = normalizeUploads(body?.uploads);

      // Neues Ticket
      const ticket = await nextTicket();

      // Kompaktes Complaint-Objekt (keine unkontrollierten Felder)
      const complaint = {
        ticket,
        email,
        createdAt: now,
        updatedAt: now,
        status: 1,             // "gesendet"
        decision: null,
        reportLink: null,
        payload,               // hier liegen segment, article, batch, ...
        uploads,               // base64-thumbs / kleine bilder
      };

      await complaintSave(complaint);
      await indexByEmail(email, ticket);

      return ok(res, { ticket });
    } catch (e) {
      return bad(res, 'failed to create complaint', 500);
    }
  }

  return methodNotAllowed(res);
}
