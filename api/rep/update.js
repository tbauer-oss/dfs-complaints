// api/rep/update.js
import { setCors } from '../_lib/cors.js';
import { getRepFromAuthHeader } from '../_lib/repAuth.js';
import { loadRepById, upsertRep } from '../_lib/repsStore.js';

export default async function handler(req, res) {
  setCors(req, res, 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'PUT' && req.method !== 'PATCH')
    return res.status(405).json({ error: 'method not allowed' });

  const auth = getRepFromAuthHeader(req);
  if (!auth) return res.status(401).json({ error: 'unauthorized' });

  const rep = await loadRepById(auth.repId);
  if (!rep) return res.status(404).json({ error: 'not found' });

  const { firstName, lastName, region, lang } = req.body || {};
  try {
    const updated = await upsertRep({
      id: rep.id,
      firstName: firstName ?? rep.firstName,
      lastName:  lastName  ?? rep.lastName,
      email:     rep.email,
      region:    region    ?? rep.region,
      lang:      lang      ?? rep.lang,
      active:    rep.active,
    });
    return res.status(200).json({ ok: true, rep: updated });
  } catch (e) {
    console.error('[rep/update]', e);
    return res.status(500).json({ error: 'update failed' });
  }
}
