export const config = { runtime: 'nodejs' };

import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { setCors, noContent, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { userByEmail } from '../_lib/store.js';

const JWT_SECRET = process.env.JWT_SECRET || 'devsecret';

export default async function handler(req, res){
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);
  if (req.method !== 'POST')    return methodNotAllowed(res);

  const { email, password } = readJson(req);
  const u = await userByEmail(String(email||'').toLowerCase());
  if (!u) return bad(res, 'not found', 404);

  const okPw = await bcrypt.compare(password||'', u.passhash||'');
  if (!okPw) return bad(res,'invalid',401);
  if (u.revoked) return bad(res,'revoked',403);

  const token = jwt.sign({ sub: u.email }, JWT_SECRET, { expiresIn: '12h' });
  return ok(res, { token, profile: { email: u.email, company: u.company, contact: u.contact, street: u.street, zip: u.zip, city: u.city, country: u.country, phone: u.phone||'' } });
}
