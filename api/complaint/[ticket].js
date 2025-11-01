// api/complaint/[ticket].js
export const config = { runtime: 'nodejs' };

import { setCors, ok, bad, noContent, methodNotAllowed } from '../../_lib/http.js';
import { getAuthUser } from '../../_lib/auth.js';
import { complaintGet, complaintUpdate, Status } from '../../_lib/store.js';
import { sendMail } from '../../_lib/mailer.js';

const ADMIN_SECRET = process.env.ADMIN_SECRET || '';

function adminAuthorized(req) {
  const hdr = req.headers?.['x-admin-secret'];
  return !!(hdr && ADMIN_SECRET && hdr === ADMIN_SECRET);
}

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);

  const { ticket } = req.query || {};
  if (!ticket) return bad(res, 'missing ticket', 400);

  // GET: Authentifizierter Kunde darf sein Ticket sehen
  if (req.method === 'GET') {
    const user = getAuthUser(req);
    if (!user) return bad(res, 'unauthorized', 401);
    const comp = await complaintGet(ticket);
    if (!comp) return bad(res, 'not found', 404);
    if (comp.email !== user.email) return bad(res, 'forbidden', 403);
    return ok(res, comp);
  }

  // PATCH: Admin ändert Status/decision/reportLink
  if (req.method === 'PATCH') {
    if (!adminAuthorized(req)) return bad(res, 'admin unauthorized', 401);
    const body = typeof req.body === 'object' ? req.body : JSON.parse(req.body ?? '{}');

    const patch = {};
    if (body.status != null) {
      const s = Number(body.status);
      if (![1,2,3,4,5,6].includes(s)) return bad(res, 'invalid status', 400);
      patch.status = s;
    }
    if (body.decision != null) {
      if (!['accepted', 'rejected', null].includes(body.decision))
        return bad(res, 'invalid decision', 400);
      patch.decision = body.decision;
    }
    if (body.reportLink != null) {
      patch.reportLink = body.reportLink || null;
    }

    let updated = await complaintUpdate(ticket, patch);
    if (!updated) return bad(res, 'not found', 404);

    // Wenn abgelehnt -> automatisch abgeschlossen (rot), wie gewünscht
    if (updated.decision === 'rejected' && updated.status !== Status.CLOSED) {
      updated = await complaintUpdate(ticket, { status: Status.CLOSED });
    }

    // Mail an Kunden bei Statusänderung/Entscheidung
    await sendMail({
      to: updated.email,
      subject: `[DFS Complaint] Update zu ${ticket} (Status ${updated.status}${updated.decision ? ` / ${updated.decision}` : ''})`,
      html: `
        <p>Ihr Reklamationsstatus wurde aktualisiert.</p>
        <p><strong>Ticket:</strong> ${ticket}<br/>
           <strong>Status:</strong> ${updated.status}${updated.decision ? ` (${updated.decision})` : ''}</p>
        ${updated.reportLink ? `<p><a href="${updated.reportLink}">Reklamationsbericht</a></p>` : ''}
      `
    });

    return ok(res, updated);
  }

  return methodNotAllowed(res);
}
