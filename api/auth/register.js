export const config = { runtime: 'nodejs' };

import bcrypt from 'bcryptjs';
import { setCors, noContent, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { pendingByEmail, pendingSave } from '../_lib/store.js';
import { send, notifyQM, tpl } from '../_lib/mail.js';

function validEmail(s){ return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(s||'')); }

export default async function handler(req, res){
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);
  if (req.method !== 'POST')    return methodNotAllowed(res);

  const b = readJson(req);
  const required = ['email','password','password2','company','contact','street','zip','city','country','privacy'];
  for (const k of required) if (!b[k]) return bad(res, `missing ${k}`);

  if (!validEmail(b.email)) return bad(res, 'invalid email');
  if (b.password !== b.password2) return bad(res,'password mismatch');

  if (await pendingByEmail(b.email)) return bad(res,'already pending', 409);

  const hash = await bcrypt.hash(b.password, 10);
  const pending = {
    email: b.email.toLowerCase(),
    passhash: hash,
    company: b.company,
    contact: b.contact,
    street: b.street, zip: b.zip, city: b.city, country: b.country,
    phone: b.phone || '',
    createdAt: Date.now(),
    status: 'pending'
  };
  await pendingSave(pending);

  await send(pending.email, tpl.afterRegisterToCustomer(pending.contact || pending.company));
  await notifyQM(tpl.afterRegisterToQM(pending.email));

  return ok(res, { ok: true });
}
