// /api/rep/login.js
import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import { setCors } from '../_lib/cors.js';
import { loadRepByEmail } from '../_lib/repsStore.js';

const REP_SECRET = process.env.REP_JWT_SECRET;

export default async function handler(req, res) {
  setCors(req, res, 'Content-Type, Authorization, X-Gate, X-Rep-Secret');
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST')    return res.status(405).json({ error: 'method not allowed' });

  if (!REP_SECRET) return res.status(500).json({ error: 'server misconfig (REP_JWT_SECRET)' });

  const body = (req.body && typeof req.body === 'object') ? req.body : {};
  const email = (body.email || '').toString().trim().toLowerCase();
  const password = (body.password || '').toString();
  const secret = (body.secret || '').toString();

  if (!email) return res.status(400).json({ error: 'missing email' });

  const rep = await loadRepByEmail(email);
  if (!rep || rep.active === false) {
    return res.status(404).json({ error: 'not found or inactive' });
  }

  // Mode A: Einmalpasswort (Secret)
  if (secret) {
    if (secret !== REP_SECRET) return res.status(401).json({ error: 'bad secret' });
    const token = jwt.sign({ repId: rep.id }, REP_SECRET, { expiresIn: '7d' });
    // Wichtig: mustChangePw aus Store zurückgeben (z. B. true beim ersten Login)
    return res.status(200).json({ token, mustChangePw: !!rep.mustChangePw });
  }

  // Mode B: Normales Passwort
  if (!password) return res.status(400).json({ error: 'missing password' });
  if (!rep.passHash) return res.status(401).json({ error: 'no password set' });
  const ok = await bcrypt.compare(password, rep.passHash);
  if (!ok) return res.status(401).json({ error: 'bad credentials' });

  const token = jwt.sign({ repId: rep.id }, REP_SECRET, { expiresIn: '7d' });
  return res.status(200).json({ token, mustChangePw: false });
}