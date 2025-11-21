export const config = { runtime: 'nodejs' };
import jwt from 'jsonwebtoken';
import { setCors, noContent, ok, bad, methodNotAllowed } from '../_lib/http.js';
import { complaintsByEmail } from '../_lib/store.js';

const JWT_SECRET = process.env.JWT_SECRET || 'devsecret';

function auth(req){
  const hdr = req.headers?.authorization || '';
  const tok = hdr.startsWith('Bearer ') ? hdr.slice(7) : null;
  try { return tok ? jwt.verify(tok, JWT_SECRET) : null; } catch { return null; }
}

export default async function handler(req,res){
  setCors(req,res);
  if (req.method === 'OPTIONS') return noContent(res);
  if (req.method !== 'GET')     return methodNotAllowed(res);

  const a = auth(req);
  if (!a?.sub) return bad(res,'unauthorized',401);

  const list = await complaintsByEmail(a.sub);
  return ok(res, list);
}
