export const config = { runtime: 'nodejs' };
import { setCors, noContent, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { usersList, userSave, userDelete } from '../_lib/store.js';

const ADMIN_SECRET = process.env.ADMIN_SECRET || '';
const isAdmin = req => ADMIN_SECRET && req.headers?.['x-admin-secret'] === ADMIN_SECRET;

export default async function handler(req,res){
  setCors(req,res);
  if (req.method === 'OPTIONS') return noContent(res);
  if (!isAdmin(req)) return bad(res,'admin unauthorized',401);

  if (req.method === 'GET'){
    return ok(res, await usersList());
  }
  if (req.method === 'PATCH'){
    // revoke/unrevoke: { email, revoked: true/false }
    const { email, revoked } = readJson(req);
    const list = await usersList();
    const u = list.find(x => x.email === email);
    if (!u) return bad(res,'not found',404);
    u.revoked = !!revoked;
    await userSave(u);
    return ok(res,{ ok:true });
  }
  if (req.method === 'DELETE'){
    const { email } = readJson(req);
    await userDelete(email);
    return ok(res,{ ok:true });
  }
  return methodNotAllowed(res);
}
