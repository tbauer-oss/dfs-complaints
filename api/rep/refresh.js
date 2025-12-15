// api/rep/refresh.js
export const config = { runtime: 'nodejs' };

import jwt from 'jsonwebtoken';
import { setCors } from '../_lib/cors.js';
import { getRepFromAuthHeader } from '../_lib/repAuth.js';

const REP_SECRET = process.env.REP_JWT_SECRET;

export default async function handler(req, res) {
  setCors(req, res, 'Content-Type, Authorization, X-Gate');
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method not allowed' });
  if (!REP_SECRET) return res.status(500).json({ error: 'server misconfig' });

  const auth = getRepFromAuthHeader(req);
  if (!auth) return res.status(401).json({ error: 'unauthorized' });

  // Neues Token mit kurzer/normaler Laufzeit ausstellen
  const token = jwt.sign({ repId: auth.repId }, REP_SECRET, { expiresIn: '7d' });
  return res.status(200).json({ token });
}
