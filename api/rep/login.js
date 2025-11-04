// /api/rep/login.js
import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import { loadRepByEmail } from '../_lib/repsStore.js';

const REP_SECRET = process.env.REP_JWT_SECRET;

export default async function handler(req, res) {
  // ---- CORS (kleinstmöglicher Eingriff) ----
  const origin = req.headers.origin || '';
  const allow = [
    'https://dfs-complaints-web.vercel.app',
    'http://localhost:5173',
    'http://localhost:3000',
  ];
  if (allow.includes(origin)) {
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Vary', 'Origin');
  }
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'Content-Type, Authorization, X-Admin-Secret, X-Gate, X-Rep-Secret'
  );
  if (req.method === 'OPTIONS') return res.status(204).end();

  // ---- Logik ----
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'method not allowed' });
  }
  if (!REP_SECRET) {
    return res.status(500).json({ error: 'server misconfig (REP_JWT_SECRET not set)' });
  }

  const body = (req.body && typeof req.body === 'object') ? req.body : {};
  const email = String(body.email || '').trim().toLowerCase();
  const password = String(body.password || '').trim();

  if (!email || !password) {
    return res.status(400).json({ error: 'missing credentials' });
  }

  // Nur angelegte Vertreter dürfen rein
  const rep = await loadRepByEmail(email);
  if (!rep || rep.active === false) {
    return res.status(401).json({ error: 'unauthorized' });
  }

  // Erst-Login: noch kein Passwort gesetzt -> Einmalpasswort = REP_JWT_SECRET
  let mustChangePw = false;
  if (!rep.passwordHash) {
    if (password !== REP_SECRET) {
      return res.status(401).json({ error: 'unauthorized' });
    }
    mustChangePw = true;
  } else {
    // Normale Anmeldung mit gesetztem Passwort (bcrypt)
    const ok = await bcrypt.compare(password, rep.passwordHash);
    if (!ok) {
      return res.status(401).json({ error: 'unauthorized' });
    }
  }

  // JWT ausstellen (wird für /api/rep/me & /api/rep/password genutzt)
  const token = jwt.sign(
    {
      repId: rep.id,
      email: rep.email,
      role: 'rep',
      mustChangePw, // Info für den Client
    },
    REP_SECRET,
    { expiresIn: '12h' }
  );

  return res.status(200).json({ token, mustChangePw });
}