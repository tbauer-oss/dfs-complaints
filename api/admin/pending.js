export const config = { runtime: 'nodejs' };

import { setCors, noContent, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { pendingList, pendingDelete, userSave, userDelete } from '../_lib/store.js';
import { send, tpl } from '../_lib/mail.js';

const ADMIN_SECRET = process.env.ADMIN_SECRET || '';
function isAdmin(req){ return ADMIN_SECRET && req.headers?.['x-admin-secret'] === ADMIN_SECRET; }

export default async function handler(req, res){
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);
  if (!isAdmin(req)) return bad(res,'admin unauthorized',401);

  if (req.method === 'GET'){
    const list = await pendingList();
    return ok(res, list);
  }
  if (req.method === 'POST'){
    // Approve: body = { email }
    const { email } = readJson(req);
    // move from pending to users
    // (simplify: we can't read pendingByEmail here -> approve via UI listing)
    // robust approver: pendingList -> find
    const list = await pendingList();
    const p = list.find(x => x.email === email);
    if (!p) return bad(res,'not found',404);

    await pendingDelete(email);
    const user = { ...p, status: 'active', approvedAt: Date.now(), revoked: false };
    await userSave(user);

    await send(user.email, tpl.approved(user.contact || user.company));
    return ok(res, { ok: true });
  }
  if (req.method === 'DELETE'){
    const { email } = readJson(req);
    await pendingDelete(email);
    await userDelete(email); // ensure full cleanup
    return ok(res, { ok: true });
  }
  return methodNotAllowed(res);
}
