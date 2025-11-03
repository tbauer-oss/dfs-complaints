// api/complaint/index.js
export const config = { runtime: 'nodejs' };

import { setCors, ok, bad, noContent, methodNotAllowed } from '../_lib/http.js';
import { getAuthUser } from '../_lib/auth.js';
import { nextTicket, complaintSave, complaintsByEmail, Status } from '../_lib/store.js';
import { sendMail } from '../_lib/mailer.js';

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);

  const user = getAuthUser(req);
  if (!user) return bad(res, 'unauthorized', 401);

  // GET: Liste meiner Reklamationen
  if (req.method === 'GET') {
    const list = await complaintsByEmail(user.email);
    return ok(res, list);
  }

  // POST: Neue Reklamation (autom. Ticketnummer)
  if (req.method === 'POST') {
    const body = typeof req.body === 'object' ? req.body : JSON.parse(req.body ?? '{}');

    const ticket = await nextTicket();
    const now = Date.now();
    const complaint = {
      ticket,
      email: user.email,
      createdAt: now,
      updatedAt: now,
      status: Status.SENT,
      decision: null,
      reportLink: null,
      payload: body || {}
    };
    await complaintSave(complaint);

    // Mail an DFS + Kunde
    await sendMail({
      to: 'complaint@dfs-diamon.de',
      cc: user.email,
      subject: `[DFS Complaint] Neue Reklamation ${ticket}`,
      html: `<p>Neue Reklamation von ${user.email}.</p><pre>${JSON.stringify(body, null, 2)}</pre>`
    });

    return ok(res, complaint);
  }

  return methodNotAllowed(res);
}
