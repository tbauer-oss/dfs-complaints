// api/account/index.js
export const config = { runtime: 'nodejs' };

import { setCors, ok, bad, noContent, methodNotAllowed } from '../_lib/http.js';
import { getAuthUser } from '../_lib/auth.js';
import { userByEmail, userSave } from '../_lib/store.js';
import { sendMail } from '../_lib/mailer.js';

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);

  const auth = getAuthUser(req);
  if (!auth) return bad(res, 'unauthorized', 401);

  // GET: aktuelle Accountdaten
  if (req.method === 'GET') {
    const u = await userByEmail(auth.email);
    if (!u) return bad(res, 'not found', 404);
    // sensible Felder weglassen (passhash etc.)
    const out = { email: u.email, company: u.company, firstName: u.firstName, lastName: u.lastName, street: u.street, zip: u.zip, city: u.city, phone: u.phone };
    return ok(res, out);
  }

  // PUT: Account aktualisieren
  if (req.method === 'PUT') {
    const body = typeof req.body === 'object' ? req.body : JSON.parse(req.body ?? '{}');
    const u = await userByEmail(auth.email);
    if (!u) return bad(res, 'not found', 404);

    const updated = { ...u,
      company: body.company ?? u.company,
      firstName: body.firstName ?? u.firstName,
      lastName: body.lastName ?? u.lastName,
      street: body.street ?? u.street,
      zip: body.zip ?? u.zip,
      city: body.city ?? u.city,
      phone: body.phone ?? u.phone
    };
    await userSave(updated);

    // Mail an Kunde + DFS
    await sendMail({
      to: auth.email, cc: 'complaint@dfs-diamon.de',
      subject: '[DFS Complaint] Accountdaten geändert',
      html: `<p>Ihre Accountdaten wurden aktualisiert.</p>`
    });

    const out = { email: updated.email, company: updated.company, firstName: updated.firstName, lastName: updated.lastName, street: updated.street, zip: updated.zip, city: updated.city, phone: updated.phone };
    return ok(res, out);
  }

  return methodNotAllowed(res);
}
