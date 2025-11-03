// /api/auth/register.js
export const config = { runtime: 'nodejs' };

import bcrypt from 'bcryptjs';
import {
  handlePreflight, ok, bad, methodNotAllowed, readJson
} from '../_lib/http.js';

const isPreview  = process.env.VERCEL_ENV !== 'production';
const validEmail = s => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(s || ''));

function toBool(v) {
  if (typeof v === 'boolean') return v;
  const s = String(v ?? '').trim().toLowerCase();
  return s === '1' || s === 'true' || s === 'on' || s === 'yes';
}

// ---- Sprach-Normalisierung: "de-DE" -> "de", Fallback "de"
const LANGS = new Set(['de','en','fr','it','es']);
function normLang(x) {
  const lc = String(x || '').toLowerCase();
  const two = lc.split(/[-_]/)[0];
  return LANGS.has(two) ? two : 'de';
}

export default async function handler(req, res) {
  // --- CORS zuerst: setzt Header & beantwortet OPTIONS (204) ---
  if (handlePreflight(req, res)) return;

  if (req.method !== 'POST') return methodNotAllowed(res);

  try {
    const b = readJson(req);

    // Pflichtfelder (ohne 'contact'; erlaubt: contact ODER first+last)
    const required = ['email','password','password2','company','street','zip','city','country'];
    for (const k of required) {
      if (!b[k]) return bad(res, `missing ${k}`, 400);
    }

    if (!validEmail(b.email))                return bad(res, 'invalid email', 400);
    if (String(b.password) !== String(b.password2))
                                            return bad(res, 'password mismatch', 400);
    if (!toBool(b.privacy))                 return bad(res, 'privacy not accepted', 400);

    // Kontakt-Pflicht: entweder "contact" ODER (firstName & lastName)
    const hasOldContact = !!b.contact;
    const hasSplitNames = !!b.firstName && !!b.lastName;
    if (!hasOldContact && !hasSplitNames)
                                            return bad(res, 'missing contact or first/last name', 400);

    // Store laden
    const store = await import('../_lib/store.js');
    const { pendingGet: _pendingGet, pendingByEmail, pendingSave } = store;
    const pendingGet = _pendingGet || pendingByEmail;
    if (!pendingGet || !pendingSave) throw new Error('store not ready (pendingGet/pendingSave missing)');

    // Normalisieren/Trimmen
    const email       = String(b.email).trim().toLowerCase();
    const lang        = normLang(b.lang || req.headers['accept-language']);
    const firstName   = String(b.firstName || '').trim();
    const lastName    = String(b.lastName  || '').trim();
    const company     = String(b.company   || '').trim();
    const street      = String(b.street    || '').trim();
    const zip         = String(b.zip       || '').trim();
    const city        = String(b.city      || '').trim();
    const phone       = String(b.phone     || '').trim();
    const countryLbl  = String(b.country   || '').trim();
    const countryCode = (String(b.countryCode || '').trim().toUpperCase().slice(0,2) || undefined);

    const contact = hasOldContact
      ? String(b.contact).trim()
      : `${firstName} ${lastName}`.trim();

    // Bereits pending? -> Mails erneut senden, 409 + Zusatzinfos
    const existing = await pendingGet(email);
    if (existing) {
      let mailSent = false, mailError = null;
      try {
        const { send, notifyQM, tpl, verifyTransport } = await import('../_lib/mail.js');
        await verifyTransport().catch(() => {});
        const results = await Promise.allSettled([
          send(
            existing.email,
            tpl.afterRegisterToCustomer(existing.contact || existing.company, existing.lang || lang)
          ),
          notifyQM(tpl.afterRegisterToQM(existing.email, existing.lang || lang)),
        ]);
        mailSent = results.some(r => r.status === 'fulfilled');
        if (!mailSent) mailError = 'all mail attempts failed';
        await new Promise(r => setTimeout(r, 750));
      } catch (e) {
        mailError = e?.message || String(e);
        console.error('register: resend mail failed:', mailError);
      }
      res.statusCode = 409;
      return res.end(JSON.stringify({ error: 'pending_exists', status: 'resent', mailSent, mailError }));
    }

    // Neu anlegen (+ Sprache speichern)
    const pending = {
      email,
      passhash: await bcrypt.hash(String(b.password), 10),
      company,
      contact,                  // zusammengeführt für Legacy
      firstName: firstName || undefined,
      lastName:  lastName  || undefined,
      street,
      zip,
      city,
      country: countryLbl,      // lesbarer Name (Dropdown-Label)
      countryCode,              // optionaler ISO-2 Code
      phone,
      lang,                     // Sprache speichern
      createdAt: Date.now(),
      status: 'pending',
    };
    await pendingSave(pending);

    // Mails vor der Response senden
    let mailSent = false, mailError = null;
    try {
      const { send, notifyQM, tpl, verifyTransport } = await import('../_lib/mail.js');
      await verifyTransport().catch(()=>{});
      const results = await Promise.allSettled([
        send(pending.email, tpl.afterRegisterToCustomer(pending.contact || pending.company, lang)),
        notifyQM(tpl.afterRegisterToQM(pending.email, lang)),
      ]);
      mailSent = results.some(r => r.status === 'fulfilled');
      if (!mailSent) mailError = 'all mail attempts failed';
      await new Promise(r => setTimeout(r, 750));
    } catch (e) {
      mailError = e?.message || String(e);
      console.error('register: initial mail failed:', mailError);
    }

    await new Promise(r => setTimeout(r, 500));
    return ok(res, { ok: true, mailSent, mailError });

  } catch (err) {
    console.error('register.js fatal:', err);
    const msg = isPreview ? (err?.message || String(err)) : 'internal error';
    return bad(res, msg, 500);
  }
}
