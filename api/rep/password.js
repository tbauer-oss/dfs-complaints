// /api/rep/password.js
export const config = { runtime: 'nodejs' };

import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import { setCors } from '../_lib/cors.js';
import { loadRepById, updateRepPassword } from '../_lib/repsStore.js';

const REP_SECRET = process.env.REP_JWT_SECRET;

function getBearerToken(req) {
  const h = String(req.headers.authorization || '');
  return h.toLowerCase().startsWith('bearer ') ? h.slice(7).trim() : '';
}

export default async function handler(req, res) {
  // Einheitliche CORS-Header
  setCors(req, res, 'Content-Type, Authorization, X-Gate, X-Rep-Secret');
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') {
    return res.status(405).end(JSON.stringify({ error: 'method not allowed' }));
  }
  if (!REP_SECRET) {
    return res.status(500).end(JSON.stringify({ error: 'server misconfig (REP_JWT_SECRET not set)' }));
  }

  try {
    // Auth prüfen
    const token = getBearerToken(req);
    if (!token) return res.status(401).end(JSON.stringify({ error: 'unauthorized (missing token)' }));

    const claims = jwt.verify(token, REP_SECRET);
    const repId = claims?.repId;
    if (!repId) return res.status(401).end(JSON.stringify({ error: 'unauthorized (invalid claims)' }));

    const rep = await loadRepById(repId);
    if (!rep || rep.active === false) {
      return res.status(403).end(JSON.stringify({ error: 'inactive or unknown representative' }));
    }

    // Body robust parsen
    const raw = (typeof req.body === 'string') ? req.body : JSON.stringify(req.body || {});
    let body = {};
    try { body = JSON.parse(raw || '{}'); } catch { body = {}; }

    const oldPw = String(body.old || '').trim();
    const newPw = String(body.new || '').trim();

    if (!newPw) {
      return res.status(400).end(JSON.stringify({ error: 'missing new password' }));
    }
    if (newPw.length < 8) {
      return res.status(400).end(JSON.stringify({ error: 'password too short (min. 8 chars)' }));
    }

    // Optional: altes Passwort prüfen, wenn bereits gesetzt und übergeben
    if (rep.passHash && oldPw) {
      const match = await bcrypt.compare(oldPw, rep.passHash);
      if (!match) {
        return res.status(401).end(JSON.stringify({ error: 'invalid old password' }));
      }
    }

    // Neues Passwort setzen (setzt in repsStore mustChangePw=false)
    const hash = await bcrypt.hash(newPw, 10);
    await updateRepPassword(rep.id, hash);

    // Frisches Token zurückgeben (7 Tage)
    const newToken = jwt.sign({ repId }, REP_SECRET, { expiresIn: '7d' });
    return res.status(200).end(JSON.stringify({ token: newToken }));
  } catch (err) {
    console.error('[rep/password]', err);
    return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));
  }
}
