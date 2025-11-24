// /api/account.js
export const config = { runtime: 'nodejs' };

import {
  handlePreflight, setCors, ok, bad, methodNotAllowed, noContent, readJson
} from './_lib/http.js';
import jwt from 'jsonwebtoken';
import {
  userByEmail, userSave, userDelete, pendingDelete,
  anonymizeUserAndComplaints,
} from './_lib/store.js';
import { countryLabelFromCode } from './_lib/countryNames.js';

const JWT_SECRET = process.env.JWT_SECRET || '';

function authEmailFromReq(req) {
  const hdr = req.headers?.authorization || req.headers?.Authorization || '';
  const m = /^Bearer\s+(.+)$/i.exec(hdr);
  if (!m) return null;
  try {
    const payload = jwt.verify(m[1], JWT_SECRET);
    const email = (payload?.email || payload?.sub || '').toString().trim().toLowerCase();
    return email || null;
  } catch {
    return null;
  }
}

const ALLOWED_LANG = new Set(['de','en','fr','it','es']);
const norm = (v) => (v == null ? '' : String(v).trim());

export default async function handler(req, res) {
  // CORS/Preflight zuerst
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  if (!JWT_SECRET) return bad(res, 'server auth misconfigured', 500);

  const email = authEmailFromReq(req);
  if (!email) return bad(res, 'unauthorized', 401);

  // ---------- GET: Account lesen ----------
  if (req.method === 'GET') {
    try {
      const u = await userByEmail(email);
      if (!u) return bad(res, 'not found', 404);

      const out = {
        email: u.email || '',
        company: u.company || '',
        contact: u.contact || '',
        street: u.street || '',
        zip: u.zip || '',
        city: u.city || '',
        country: u.country || '',
        countryCode: u.countryCode || '',
        phone: u.phone || '',
        lang: (u.lang || 'de'),
        createdAt: u.createdAt || null,
        revoked: !!u.revoked,

        // NEU: Kundennummer – nur lesen
        customerNumber: u.customerNumber || u.customer_no || '',
      };

      return ok(res, out);
    } catch (e) {
      console.error('account GET error:', e);
      return bad(res, 'server error', 500);
    }
  }
  
  // ---------- PUT/PATCH: Accountdaten ändern ----------
  if (req.method === 'PUT' || req.method === 'PATCH') {
    try {
      const body = readJson(req) || {};

      // Bestehenden Nutzer laden oder Grundgerüst anlegen
      const cur = (await userByEmail(email)) || { email, createdAt: Date.now() };

      const rawCode = norm(body.countryCode).toUpperCase().slice(0, 2);
      const countryCode = rawCode || cur.countryCode || undefined;
      let country = norm(body.country) || cur.country || '';

      // Falls nur ein ISO-Code geliefert wird, einen lesbaren Namen ergänzen
      if (!country && countryCode) {
        country = countryLabelFromCode(countryCode) || '';
      }

      // Nur diese Felder dürfen geändert werden (E-Mail bleibt die vom Token!)
      const update = {
        company:  norm(body.company),
        contact:  norm(body.contact),
        street:   norm(body.street),
        zip:      norm(body.zip),
        city:     norm(body.city),
        country,
        countryCode,
        phone:    norm(body.phone),
        lang:     norm(body.lang),
      };

      // Sprache validieren (optional, sonst Standard 'de')
      if (!ALLOWED_LANG.has(update.lang.toLowerCase())) {
        update.lang = 'de';
      }

      const saved = {
        ...cur,
        ...update,
        email,
        updatedAt: Date.now(),
      };

      await userSave(saved);

      // Reduzierte Antwort
      const out = {
        email: saved.email,
        company: saved.company || '',
        contact: saved.contact || '',
        street: saved.street || '',
        zip: saved.zip || '',
        city: saved.city || '',
        country: saved.country || '',
        countryCode: saved.countryCode || '',
        phone: saved.phone || '',
        lang: saved.lang || 'de',
        createdAt: saved.createdAt || null,
        updatedAt: saved.updatedAt || null,
        revoked: !!saved.revoked,
        customerNumber: saved.customerNumber || saved.customer_no || '',
      };
      return ok(res, out);
    } catch (e) {
      console.error('account PUT/PATCH error:', e);
      return bad(res, 'server error', 500);
    }
  }

  // ---------- DELETE: Account löschen ----------
  if (req.method === 'DELETE') {
    try {
      const hard = String(req.query?.hard || '').trim() === '1';
      const anonymize = !hard && String(req.query?.anonymize || '').trim() === '1';

      if (hard) {
        // 1) Nutzer löschen (Reklamationen bleiben aus regulatorischen Gründen bestehen)
        try { await userDelete(email); } catch (_) {}
        // 2) evtl. Pending-Eintrag löschen
        try { await pendingDelete(email); } catch (_) {}
      } else if (anonymize) {
        // DSGVO-konforme Anonymisierung (statt Hard-Delete)
        const result = await anonymizeUserAndComplaints(email).catch((e) => {
          console.error('[account DELETE anonymize] failed:', e);
          return null;
        });
        if (!result) return bad(res, 'anonymize failed', 500);
        return ok(res, { ok: true, anonymized: true, complaints: result.complaints || 0 });
      } else {
        // Soft-Delete: Markierung als durch User gelöscht
        const u = (await userByEmail(email)) || { email };
        u.revoked = true;
        u.revokedAt = Date.now();
        u.selfDeleted = true;    // <— NEU
        u.deletedAt = Date.now();// <— optional: Zeit merken
        await userSave(u);
      }

      return noContent(res);
    } catch (e) {
      console.error('account DELETE error:', e);
      return bad(res, 'server error', 500);
    }
  }

  return methodNotAllowed(res);
}
