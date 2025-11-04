// api/rep/login.js
import { setCors } from '../_lib/cors.js';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { loadRepByEmail, setRepPassword } from '../_lib/repsStore.js';

const REP_SECRET = process.env.REP_JWT_SECRET;

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).end(JSON.stringify({ error: 'method not allowed' }));

  const { email, password, secret } = req.body || {};
  const hdrSecret = req.headers['x-rep-secret'];

  // ---- 1) Secret-Login (Einmalpasswort) ----
  if (hdrSecret || secret) {
    const sec = hdrSecret || secret;
    if (sec !== REP_SECRET) return res.status(401).json({ error: 'invalid secret' });
    return res.status(200).json({ ok: true, mustChangePw: true });
  }

  // ---- 2) Standard-Login mit Email + Passwort ----
  if (!email || !password) {
    return res.status(400).json({ error: 'missing email or password' });
  }

  const rep = await loadRepByEmail(email);
  if (!rep) return res.status(404).json({ error: 'unknown rep' });
  if (!rep.active) return res.status(403).json({ error: 'inactive rep' });

  if (!rep.passHash) {
    // noch nie Passwort gesetzt
    return res.status(403).json({ error: 'password not set (use secret first)' });
  }

  const ok = await bcrypt.compare(password, rep.passHash);
  if (!ok) return res.status(401).json({ error: 'invalid credentials' });

  // ---- Token erzeugen ----
  const token = jwt.sign(
    { repId: rep.id, email: rep.email },
    REP_SECRET,
    { expiresIn: '7d' }
  );

  return res.status(200).json({
    token,
    mustChangePw: !!rep.mustChangePw,
  });
}