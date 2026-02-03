// api/rep/assignment/notify.js
export const config = { runtime: 'nodejs' };

import jwt from 'jsonwebtoken';
import { setCors } from '../../_lib/cors.js';

const REP_SECRET = process.env.REP_JWT_SECRET;

function getBearerToken(req) {
  const h = String(req.headers.authorization || '');
  return h.toLowerCase().startsWith('bearer ') ? h.slice(7).trim() : '';
}

export default async function handler(req, res) {
  setCors(req, res, 'Content-Type, Authorization, X-Gate');
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') {
    return res.status(405).end(JSON.stringify({ error: 'method not allowed' }));
  }
  if (!REP_SECRET) {
    return res.status(500).end(JSON.stringify({ error: 'server misconfig (REP_JWT_SECRET not set)' }));
  }

  const token = getBearerToken(req);
  if (!token) return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));

  try {
    jwt.verify(token, REP_SECRET);
  } catch {
    return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));
  }

  return res.status(204).end();
}
