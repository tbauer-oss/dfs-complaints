export const config = { runtime: 'nodejs' };

import bcrypt from 'bcryptjs';
import { setCors, noContent, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { pendingByEmail, pendingSave, userByEmail } from '../_lib/store.js';
import { send, notifyQM, tpl } from '../_lib/mail.js';

function validEmail(s){ return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(s||'')); }

export default async function handler(req, res){
  setCors(req, res);                           // CORS IMMER zuerst
  if (req.method === 'OPTIONS') return noContent(res);
  if (req.method !== 'POST')    return methodNotAllowed(res);

  try {
    const b = readJson(req);                   // muss auch schon geparstes req.body können
    const required = ['email','password','password2','company','contact','street','zip','city','country','privacy'];
    for (const k of required) if (!b[k]) return bad(res, `missing ${k}`, 400);

    if (!validEmail(b.email))                 return bad(res, 'invalid email', 400);
    if (b.password !== b.password2)           return bad(res, 'password mismatch', 400);

    // Schon als „User“ vorhanden?
    if (await userByEmail?.(b.email))         return bad(res, 'already registered', 409);
    if (await pendingByEmail(b.email))        return bad(res, 'already pending', 409);

    const hash = await bcrypt.hash(b.password, 10);
    const pending = {
      email: String(b.email).toLowerCase(),
      passhash: hash,
      company: b.company,
      contact: b.contact,
      street: b.street, zip: b.zip, city: b.city, country: b.country,
      phone: b.phone || '',
      createdAt: Date.now(),
      status: 'pending'
    };
    await pendingSave(pending);

    // Antwort zuerst – Mails „best effort“ dahinter
    ok(res, { ok: true });

    // Fire-and-forget (Fehler nur loggen)
    Promise.allSettled([
      send(pending.email, tpl.afterRegisterToCustomer(pending.contact || pending.company)),
      notifyQM(tpl.afterRegisterToQM(pending.email))
    ]).catch(()=>{});
  } catch (e) {
    return bad(res, 'internal error', 500);
  }
}
