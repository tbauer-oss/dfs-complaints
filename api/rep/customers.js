// api/rep/customers.js
export const config = { runtime: 'nodejs' };

import bcrypt from 'bcryptjs';

import { setCors } from '../_lib/cors.js';
import { getRepFromAuthHeader } from '../_lib/repAuth.js';
import { repCustomers as storeRepCustomers } from '../_lib/repsStore.js';
import { userSave, userByEmail } from '../_lib/store.js';

function S(v) { return (v ?? '').toString().trim(); }

// ------- Minimaler Upstash-Client (REST) -------
// nutzt ausschließlich Set-Befehle + kleine Helfer
const UP_URL   = process.env.UPSTASH_REDIS_REST_URL  || '';
const UP_TOKEN = process.env.UPSTASH_REDIS_REST_TOKEN || '';

async function upReq(path, { method = 'POST' } = {}) {
  if (!UP_URL || !UP_TOKEN) throw new Error('UPSTASH env missing');
  const r = await fetch(`${UP_URL}${path}`, {
    method,
    headers: { Authorization: `Bearer ${UP_TOKEN}` },
    cache: 'no-store',
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) {
    const msg = j?.error || j?.message || `Upstash error ${r.status}`;
    throw new Error(msg);
  }
  return j?.result;
}

// Set-Helfer (SADD/SREM/SMEMBERS) – Members werden URL-encoded
async function kvSAdd(key, ...members) {
  const m = members.filter(Boolean);
  if (!m.length) return 0;
  const seg = m.map(encodeURIComponent).join('/');
  return await upReq(`/sadd/${encodeURIComponent(key)}/${seg}`);
}
async function kvSRem(key, ...members) {
  const m = members.filter(Boolean);
  if (!m.length) return 0;
  const seg = m.map(encodeURIComponent).join('/');
  return await upReq(`/srem/${encodeURIComponent(key)}/${seg}`);
}
async function kvSMembers(key) {
  const res = await upReq(`/smembers/${encodeURIComponent(key)}`);
  return Array.isArray(res) ? res.map(S) : [];
}

// klassische GET/SET/DEL nur für Migration des Legacy-Keys
async function kvGet(key) { return await upReq(`/get/${encodeURIComponent(key)}`, { method: 'GET' }); }
async function kvSet(key, value) { return await upReq(`/set/${encodeURIComponent(key)}/${encodeURIComponent(value)}`); }
async function kvDel(key) { return await upReq(`/del/${encodeURIComponent(key)}`); }

// Key-Schema
const KEY_SET   = (repId) => `dfs:rep:${repId}:customers`;     // ✅ korrektes Ziel (Set)
const KEY_LEG   = (repId) => `dfs:repCustomers:${repId}`;      // ❌ Legacy (String JSON)
const KEY_REP_OF = (email) => `dfs:repOf:${email}`;            // Mapping Kunde -> Rep

// Einmalige Migration Legacy(String-JSON) -> Set
async function migrateLegacyToSet(repId) {
  try {
    const legacyKey = KEY_LEG(repId);
    const raw = await kvGet(legacyKey);
    if (!raw) return;
    let arr = null;
    if (typeof raw === 'string' && raw.trim().startsWith('[')) {
      try { arr = JSON.parse(raw); } catch { /* ignore */ }
    }
    if (Array.isArray(arr) && arr.length) {
      const emails = arr
        .map(x => S(x).toLowerCase())
        .filter(x => x && x.includes('@'));
      if (emails.length) {
        await kvSAdd(KEY_SET(repId), ...emails);
      }
    }
    await kvDel(legacyKey); // Legacy aufräumen
  } catch (e) {
    console.warn('[rep/customers] legacy migration skipped:', e?.message || e);
  }
}

// ------- Fallback-Assign/Unassign (nur Set, kein JSON mehr) -------
async function fallbackRepAssign(repId, email) {
  const em = S(email).toLowerCase();
  if (!repId || !em || !em.includes('@')) return;
  await migrateLegacyToSet(repId);
  await kvSAdd(KEY_SET(repId), em);       // ⇒ Set pflegen
  await kvSet(KEY_REP_OF(em), repId);     // Mapping Kunde -> Rep aktualisieren
}

async function fallbackRepUnassign(repId, email) {
  const em = S(email).toLowerCase();
  if (!repId || !em) return;
  await migrateLegacyToSet(repId);
  await kvSRem(KEY_SET(repId), em);       // ⇒ aus Set entfernen
  try { await kvDel(KEY_REP_OF(em)); } catch { /* ignore */ }
}

// Sicheres Lesen der Kundenliste: bevorzugt storeRepCustomers(),
// sonst Fallback direkt aus dem Set. Legacy wird davor migriert.
async function readRepCustomers(repId) {
  await migrateLegacyToSet(repId);
  try {
    if (typeof storeRepCustomers === 'function') {
      const list = await storeRepCustomers(repId);
      if (Array.isArray(list) && list.length) return list.map(S);
    }
  } catch { /* ignore, dann Fallback */ }
  return await kvSMembers(KEY_SET(repId));
}

export default async function handler(req, res) {
  // CORS inkl. X-Debug für Browser-Tests
  setCors(req, res, 'Content-Type, Authorization, X-Gate, X-Debug');
  if (req.method === 'OPTIONS') return res.status(204).end();

  try {
    // Auth
    let auth = null;
    try { auth = getRepFromAuthHeader(req); } catch (e) {
      console.error('[rep/customers] auth parse failed:', e);
      return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));
    }
    if (!auth) return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));

    // POST: assign/unassign
    if (req.method === 'POST') {
      try {
        let body = {};
        try {
          body = typeof req.body === 'string'
            ? JSON.parse(req.body || '{}')
            : (req.body || {});
        } catch {}

        const action = S(body.action || body.op); // Alias: op

        if (action === 'create') {
          try {
            const email = S(body.email).toLowerCase();
            const company = S(body.company);
            const contactRaw = S(body.contact);
            const firstName = S(body.firstName);
            const lastName = S(body.lastName);
            const street = S(body.street);
            const zip = S(body.zip);
            const city = S(body.city);
            const country = S(body.country);
            const countryCode = S(body.countryCode).toUpperCase().slice(0, 2);
            const phone = S(body.phone);
            const lang = (S(body.lang) || 'de').toLowerCase();
            const password = S(body.password);
            const customerNo = S(body.customerNo);
            const vatId = S(body.vatId);

            if (!email || !email.includes('@')) {
              return res.status(400).end(JSON.stringify({ error: 'invalid email' }));
            }
            if (!company) {
              return res.status(400).end(JSON.stringify({ error: 'company required' }));
            }
            if (!street || !zip || !city || !country) {
              return res.status(400).end(JSON.stringify({ error: 'address required' }));
            }
            const hasContact = contactRaw.length > 0;
            const hasNames = firstName.length > 0 && lastName.length > 0;
            if (!hasContact && !hasNames) {
              return res.status(400).end(JSON.stringify({ error: 'contact or name required' }));
            }
            if (!password || password.length < 8) {
              return res.status(400).end(JSON.stringify({ error: 'password too short' }));
            }

            const existing = await userByEmail(email);
            if (existing) {
              return res.status(409).end(JSON.stringify({ error: 'customer exists' }));
            }

            const contact = hasContact ? contactRaw : `${firstName} ${lastName}`.trim();
            const passhash = await bcrypt.hash(password, 10);

            const user = {
              email,
              company,
              contact,
              firstName: firstName || undefined,
              lastName: lastName || undefined,
              street,
              zip,
              city,
              country,
              countryCode: countryCode || undefined,
              phone: phone || undefined,
              lang,
              passhash,
              createdAt: Date.now(),
              repCreated: auth.repId,
            };
            if (customerNo) {
              user.customerNo = customerNo;
              user.customerNumber = customerNo;
            }
            if (vatId) {
              user.vatId = vatId;
            }

            await userSave(user);

            let assigned = false;
            try {
              const store = await import('../_lib/repsStore.js');
              if (typeof store.repAssign === 'function') {
                await store.repAssign(auth.repId, email);
                assigned = true;
              }
            } catch (_) {}
            if (!assigned) {
              await fallbackRepAssign(auth.repId, email);
            }

            return res.status(200).end(JSON.stringify({
              ok: true,
              email,
              company,
              assigned: true,
            }));
          } catch (e) {
            console.error('[rep/customers] create error:', e);
            return res.status(500).end(JSON.stringify({ error: 'server error', where: 'create' }));
          }
        }

        const email  = (S(body.email) || S(body.customerEmail)).toLowerCase();
        if (!email || !email.includes('@')) {
          return res.status(400).end(JSON.stringify({ error: 'invalid email' }));
        }

        // repsStore (falls vorhanden) bevorzugen, andernfalls Set-Fallback
        let store = {};
        try { store = await import('../_lib/repsStore.js'); } catch { /* ignore */ }
        const hasAssign   = typeof store.repAssign   === 'function';
        const hasUnassign = typeof store.repUnassign === 'function';

        if (action === 'assign') {
          if (hasAssign) await store.repAssign(auth.repId, email);
          else           await fallbackRepAssign(auth.repId, email);
          return res.status(204).end();
        }

        if (action === 'unassign') {
          if (hasUnassign) await store.repUnassign(auth.repId, email);
          else             await fallbackRepUnassign(auth.repId, email);
          return res.status(204).end();
        }

        return res.status(400).end(JSON.stringify({ error: 'invalid action' }));
      } catch (e) {
        const xdbg = S(req.headers['x-debug']);
        console.error('[rep/customers] POST error:', e);
        if (xdbg) {
          return res.status(500).end(JSON.stringify({
            error: 'server error',
            where: 'post',
            details: e?.message || String(e),
          }));
        }
        return res.status(500).end(JSON.stringify({ error: 'server error' }));
      }
    }

    // GET: Liste / Details
    if (req.method === 'GET') {
      try {
        const details = (req.query?.details || '').toString() === '1';
        const emails = await readRepCustomers(auth.repId);
        if (!Array.isArray(emails) || emails.length === 0) {
          return res.status(200).end(JSON.stringify([]));
        }

        if (!details) {
          return res.status(200).end(JSON.stringify(emails));
        }

        const { userByEmail } = await import('../_lib/store.js');

        const out = [];
        for (const mail of emails) {
          let name = mail;
          let company = '', address = '', zip = '', city = '', country = '';
          let phone = '', customerNo = '', vatId = '';

          try {
            const u = await userByEmail(mail);
            if (u && typeof u === 'object') {
              const first = S(u.firstName);
              const last  = S(u.lastName);
              const full  = S(`${first} ${last}`);

              company    = S(u.companyName || u.company || u.org);
              name       = company || S(u.contactName || u.name || full || mail) || mail;
              address    = S(u.address || u.street || u.street1 || u.address1);
              zip        = S(u.zip || u.postcode || u.postalCode || u.plz);
              city       = S(u.city || u.town || u.ort);
              country    = S(u.country || u.countryCode || u.land);
              phone      = S(u.phone || u.tel || u.phoneNumber || u.telephone);
              customerNo = S(u.customerNo || u.customerId || u.kundennummer || u.kundenNr);
              vatId      = S(u.vat || u.vatId || u.vatid || u.ustId || u.ustid);
            }
          } catch (e) {
            console.warn('[rep/customers] userByEmail failed for', mail, e?.message || e);
          }

          out.push({ email: mail, name, company, address, zip, city, country, phone, customerNo, vatId });
        }

        return res.status(200).end(JSON.stringify(out));
      } catch (e) {
        console.error('[rep/customers] GET error:', e);
        return res.status(200).end(JSON.stringify([]));
      }
    }

    return res.status(405).end(JSON.stringify({ error: 'method not allowed' }));
  } catch (e) {
    console.error('[rep/customers] FATAL:', e);
    setCors(req, res, 'Content-Type, Authorization, X-Gate, X-Debug');
    return res.status(500).end(JSON.stringify({ error: 'fatal server error' }));
  }
}
