// /api/auth/register.js
export const config = { runtime: 'nodejs' };

import bcrypt from 'bcryptjs';

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

const isPreview = process.env.VERCEL_ENV !== 'production';
const validEmail = s => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(s || ''));

function toBool(v) {
  if (typeof v === 'boolean') return v;
  const s = String(v ?? '').trim().toLowerCase();
  return s === '1' || s === 'true' || s === 'on' || s === 'yes';
}

function readJson(req) {
  if (req.body && typeof req.body === 'object') return req.body;
  try { return JSON.parse(req.body ?? '{}'); } catch { return {}; }
}

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') { res.statusCode = 204; return res.end(); }
  if (req.method !== 'POST')    { res.statusCode = 405; return res.end(JSON.stringify({ error: 'method not allowed' })); }

  try {
    const b = readJson(req);

    // Pflichtfelder
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

    // Store laden
    const store = await import('../_lib/store.js');
    const { pendingGet: _pendingGet, pendingByEmail, pendingSave } = store;
    const pendingGet = _pendingGet || pendingByEmail;
    if (!pendingGet || !pendingSave) throw new Error('store not ready (pendingGet/pendingSave missing)');

    const email = String(b.email).toLowerCase();
    const lang = (b.lang || 'de').toLowerCase();

    // Prüfen, ob schon pending -> Mail erneut senden und 409 zurückgeben (Frontend zeigt passenden Text)
    const existing = await pendingGet(email);
    if (existing) {
      try {
        const { send, notifyQM, tpl, verifyTransport } = await import('../_lib/mail.js');
        await verifyTransport().catch(()=>{});
        await Promise.allSettled([
          send(existing.email, tpl.afterRegisterToCustomer(existing.contact || existing.company, lang)),
          notifyQM(tpl.afterRegisterToQM(existing.email, lang)),
        ]);
      } catch (e) {
        console.error('register: resend mail failed:', e);
      }
      res.statusCode = 409;
      return res.end(JSON.stringify({ error: 'pending_exists', status: 'resent' }));
    }

    // Neu anlegen
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

    // >>> WICHTIG: Mails JETZT senden (vor res.end), nicht "fire & forget"
    try {
      const { send, notifyQM, tpl, verifyTransport } = await import('../_lib/mail.js');
      await verifyTransport().catch(()=>{});
      const results = await Promise.allSettled([
        send(pending.email, tpl.afterRegisterToCustomer(pending.contact || pending.company, lang)),
        notifyQM(tpl.afterRegisterToQM(pending.email, lang)),
      ]);
      console.log('register: mail results', results.map(r => r.status));
    } catch (e) {
      console.error('register: initial mail failed:', e);
      // wir antworten trotzdem 200 – Registrierung ist gespeichert
    }

    // Antwort
    res.statusCode = 200;
    return res.end(JSON.stringify({ ok: true }));

  } catch (err) {
    console.error('register.js fatal:', err);
    res.statusCode = 500;
    const msg = isPreview ? (err?.message || String(err)) : 'internal error';
    return res.end(JSON.stringify({ error: msg }));
  }
}
