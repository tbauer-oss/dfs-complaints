// api/rep/exists.js
import { setCors } from '../_lib/cors.js';
import { loadRepByEmail } from '../_lib/repsStore.js';

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method not allowed' });

  try {
    const email = (req.body?.email || '').toString().trim().toLowerCase();
    if (!email || !email.includes('@')) {
      return res.status(400).json({ exists: false, error: 'invalid email' });
    }

    const rep = await loadRepByEmail(email);
    if (!rep) {
      return res.status(200).json({ exists: false });
    }

    // Optional: Nur aktive Reps zulassen
    const active = rep.active === undefined ? true : !!rep.active;
    return res.status(200).json({ exists: active });
  } catch (err) {
    console.error('[rep/exists]', err);
    return res.status(500).json({ exists: false, error: 'server error' });
  }
}