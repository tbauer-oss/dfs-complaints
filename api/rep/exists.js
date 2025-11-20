// api/rep/exists.js
export default async function handler(req, res) {
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
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Admin-Secret, X-Gate, X-Rep-Secret');
  if (req.method === 'OPTIONS') return res.status(204).end();

  if (req.method !== 'POST') return res.status(405).json({ error: 'method not allowed' });

  try {
    const email = (req.body?.email || '').toString().trim().toLowerCase();
    if (!email || !email.includes('@')) {
      return res.status(400).json({ exists: false, error: 'invalid email' });
    }

    // Wichtig: nutzt deinen Store & Index (repBy:<email>)
    const { loadRepByEmail } = await import('../_lib/repsStore.js');
    const rep = await loadRepByEmail(email);

    // Optional nur aktive zulassen
    const exists = !!rep && (rep.active === undefined ? true : !!rep.active);

    return res.status(200).json({ exists });
  } catch (err) {
    console.error('[rep/exists]', err);
    return res.status(500).json({ exists: false, error: 'server error' });
  }
}