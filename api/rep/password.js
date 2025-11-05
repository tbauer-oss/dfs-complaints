// /api/rep/password.js
import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import { loadRepById, updateRepPassword } from '../_lib/repsStore.js';

const REP_SECRET = process.env.REP_JWT_SECRET;

function getBearerToken(req) {
  const h = req.headers.authorization || '';
  if (!h.toLowerCase().startsWith('bearer ')) return '';
  return h.slice(7).trim();
}

export default async function handler(req, res) {
  // ---- CORS (wie in allen anderen Endpunkten) ----
  const origin = req.headers.origin || '';
  const allow = [
    'https://dfs-complaints-web.vercel.app',
    'http://localhost:5173',
    'http://localhost:3000',
  ];
  if (allow.includes(origin)) {
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Vary', 'Origin');
  } else if (process.env.WEB_ORIGIN) {
    res.setHeader('Access-Control-Allow-Origin', process.env.WEB_ORIGIN);
  }

  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'Content-Type, Authorization, X-Admin-Secret, X-Gate, X-Rep-Secret'
  );
  if (req.method === 'OPTIONS') return res.status(204).end();

  // ---- Method & Server-Check ----
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'method not allowed' });
  }
  if (!REP_SECRET) {
    return res.status(500).json({ error: 'server misconfig (REP_JWT_SECRET not set)' });
  }

  try {
    // ---- Token prüfen ----
    const token = getBearerToken(req);
    if (!token) return res.status(401).json({ error: 'unauthorized (missing token)' });

    const claims = jwt.verify(token, REP_SECRET);
    const repId = claims?.repId;
    if (!repId) return res.status(401).json({ error: 'unauthorized (invalid claims)' });

    const rep = await loadRepById(repId);
    if (!rep || rep.active === false) {
      return res.status(403).json({ error: 'inactive or unknown representative' });
    }

    // ---- Body auswerten ----
    const body = (req.body && typeof req.body === 'object') ? req.body : {};
    const oldPw = String(body.old || '').trim();
    const newPw = String(body.new || '').trim();

    if (!newPw) {
      return res.status(400).json({ error: 'missing new password' });
    }
    if (newPw.length < 8) {
      return res.status(400).json({ error: 'password too short (min. 8 chars)' });
    }

    // ---- Optional: altes Passwort prüfen, falls vorhanden ----
    if (rep.passHash && oldPw) {
      const match = await bcrypt.compare(oldPw, rep.passHash);
      if (!match) {
        return res.status(401).json({ error: 'invalid old password' });
      }
    }

    // ---- Neues Passwort setzen ----
    const hash = await bcrypt.hash(newPw, 10);
    await updateRepPassword(rep.id, hash);

    const newToken = jwt.sign({ repId }, REP_SECRET, { expiresIn: '7d' });
    return res.status(200).json({ token: newToken });

    // ---- Antwort ----
    return res.status(200).json({ ok: true });
  } catch (err) {
    console.error('[rep/password]', err);
    return res.status(401).json({ error: 'unauthorized' });
  }
}
