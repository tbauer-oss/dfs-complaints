// api/rep/password.js
import { setCors } from '../_lib/cors.js';
import { getRepFromAuthHeader, hashPassword } from '../_lib/repAuth.js';
import { setRepPassword } from '../_lib/repsStore.js';

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST')   return res.status(405).end(JSON.stringify({ error: 'method not allowed' }));

  const auth = getRepFromAuthHeader(req);
  if (!auth) return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));

  try {
    const body = (typeof req.body === 'string') ? JSON.parse(req.body||'{}') : (req.body || {});
    const newPw = (body.new || '').toString();
    if (!newPw) return res.status(400).end(JSON.stringify({ error: 'missing new password' }));

    const hash = await hashPassword(newPw);
    await setRepPassword(auth.repId, hash, false);
    res.status(200).end(JSON.stringify({ ok: true }));
  } catch (e) {
    res.status(500).end(JSON.stringify({ error: String(e?.message || e) }));
  }
}
