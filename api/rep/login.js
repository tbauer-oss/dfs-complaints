// api/rep/login.js
import { setCors } from '../_lib/cors.js';
import { loadRepByEmail, setRepPassword } from '../_lib/repsStore.js';
import { signRepJwt, checkPassword, hashPassword } from '../_lib/repAuth.js';

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST')   return res.status(405).end(JSON.stringify({ error: 'method not allowed' }));

  try {
    const body = (typeof req.body === 'string') ? JSON.parse(req.body||'{}') : (req.body || {});
    const email = (body.email || '').toString().trim().toLowerCase();
    const password = (body.password || '').toString();

    if (!email || !password) return res.status(400).end(JSON.stringify({ error: 'missing email or password' }));

    const rep = await loadRepByEmail(email);
    if (!rep) return res.status(401).end(JSON.stringify({ error: 'invalid credentials' }));

    // erster Login: wenn passHash fehlt, akzeptiere das Initial-Passwort und setze mustChangePw=true
    if (!rep.passHash) {
      const hash = await hashPassword(password);
      await setRepPassword(rep.id, hash, true);
      const token = signRepJwt({ id: rep.id, email: rep.email });
      return res.status(200).end(JSON.stringify({ token, mustChangePw: true }));
    }

    const ok = await checkPassword(password, rep.passHash);
    if (!ok) return res.status(401).end(JSON.stringify({ error: 'invalid credentials' }));

    const token = signRepJwt(rep);
    return res.status(200).end(JSON.stringify({ token, mustChangePw: !!rep.mustChangePw }));
  } catch (e) {
    res.status(500).end(JSON.stringify({ error: String(e?.message || e) }));
  }
}
