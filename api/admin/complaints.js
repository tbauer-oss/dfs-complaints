export const config = { runtime: 'nodejs' };

import { setCors, noContent, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { complaintsAll, complaintByTicket, complaintSave } from '../_lib/store.js';

const ADMIN_SECRET = process.env.ADMIN_SECRET || '';
const isAdmin = req => ADMIN_SECRET && req.headers?.['x-admin-secret'] === ADMIN_SECRET;

// Zulässige Stati
const STATES = [
  'Eingegegangen',
  'In Bearbeitung',
  'Rückfrage erforderlich',
  'Angenommen / Genehmigt',
  'Abgelehnt',
  'In Nacharbeit',
  'Abgeschlossen'
];

export default async function handler(req,res){
  setCors(req,res);
  if (req.method === 'OPTIONS') return noContent(res);
  if (!isAdmin(req)) return bad(res,'admin unauthorized',401);

  if (req.method === 'GET'){
    return ok(res, await complaintsAll());
  }
  if (req.method === 'PATCH'){
    const { ticket, status } = readJson(req);
    if (!ticket || !STATES.includes(status)) return bad(res,'invalid');
    const c = await complaintByTicket(ticket);
    if (!c) return bad(res,'not found',404);
    c.status = status;
    c.statusUpdatedAt = Date.now();
    await complaintSave(c);
    return ok(res,{ ok:true });
  }
  return methodNotAllowed(res);
}
