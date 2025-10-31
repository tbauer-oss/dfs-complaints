// /api/auth/register.js
export const config = { runtime: 'nodejs' };

import bcrypt from 'bcryptjs';

// === CORS (dein Block, unverändert) ===
const PROD_FE  = 'https://dfs-complaints-web.vercel.app';
const PREVIEW  = /^https:\/\/dfs-complaints-web-[a-z0-9-]+(?:-[a-z0-9-]+)?\.vercel\.app$/i;
function setCors(req, res) {
  const origin = req.headers?.origin || '';
  const allow = origin && (origin === PROD_FE || PREVIEW.test(origin)) ? origin : PROD_FE;
  res.setHeader('Access-Control-Allow-Origin', allow);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Admin-Secret');
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
}

// === Helpers ===
const isPreview = process.env.VERCEL_ENV !== 'production';
const validEmail = s => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(s || ''));

function toBool(v) {
  if (typeof v === 'boolean') return v;
  const s = String(v ?? '').trim().toLowerCase();
  return s === '1' || s === 'true' || s === 'on' || s === 'yes';
}

function readJson(req) {
  // Vercel/Node liefert in vielen Fällen req.body bereits als Objekt.
  if (req.body && typeof req.body === 'object') return req.body;
  try { return JSON.parse(req.body ?? '{}'); } catch { return {}; }
}

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') { res.statusCode = 204; return res.end(); }
  if (req.method !== 'POST')    { res.statusCode = 405; return res.end(JSON.stringify({ error: 'method not allowed' })); }

  try {
    const b = readJson(req);

    // Pflichtfelder prüfen
    const required = ['email','password','password2','company','contact','street','zip','city','country'];
    for (const k of required) {
      if (!b[k]) { res.statusCode = 400; return res.end(JSON.stringify({ error:`missing ${k}` })); }
    }

    if (!validEmail(b.email)) {
      res.statusCode = 400; return res.end(JSON.stringify({ error: 'invalid email' }));
    }
    if (String(b.password) !== String(b.password2)) {
      res.statusCode = 400; return res.end(JSON.stringify({ error: 'password mismatch' }));
    }
    if (!toBool(b.privacy)) {
      res.statusCode = 400; return res.end(JSON.stringify({ error: 'privacy not accepted' }));
    }

    // Store lazy laden (crasht nicht bei Preflight)
    const store = await import('../_lib/store.js');
    const pendingGet  = store.pendingGet  || store.pendingByEmail; // Fallback, falls alter Name
    const pendingSave = store.pendingSave;

    if (!pendingGet || !pendingSave) {
      throw new Error('store not ready (pendingGet/pendingSave missing)');
    }

    const email = String(b.email).toLowerCase();

    // Doppelte Registrierung verhindern
    if (await pendingGet(email)) {
      res.statusCode = 409; return res.end(JSON.stringify({ error:'already pending' }));
    }

    // Hash erzeugen & Pending-Objekt speichern
    const pending = {
      email,
      passhash: await bcrypt.hash(String(b.password), 10),
      company: b.company,
      contact: b.contact,
      street: b.street,
      zip: b.zip,
      city: b.city,
      country: b.country,
      phone: b.phone || '',
      createdAt: Date.now(),
      status: 'pending',
    };

    await pendingSave(pending);

    // Sofortige Antwort (UI wird nicht vom Mailversand blockiert)
    res.statusCode = 200;
    res.end(JSON.stringify({ ok: true }));

    // Mails "fire & forget"
    const lang = (b.lang || 'de').toLowerCase();
    import('../_lib/mail.js')
      .then(({ send, notifyQM, tpl }) => Promise.allSettled([
        send(pending.email, tpl.afterRegisterToCustomer(pending.contact || pending.company, lang)),
        notifyQM(tpl.afterRegisterToQM(pending.email, lang)),
      ]))
      .catch(console.error);

  } catch (err) {
    console.error('register.js fatal:', err);
    res.statusCode = 500;
    const msg = isPreview ? (err?.message || String(err)) : 'internal error';
    return res.end(JSON.stringify({ error: msg }));
  }
}
