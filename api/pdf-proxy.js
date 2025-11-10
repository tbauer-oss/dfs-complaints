// api/pdf-proxy.js
export const config = { runtime: 'nodejs' };

const ALLOWED_HOSTS = [
  'dfs-diamon.de',
  'www.dfs-diamon.de'
];

export default async function handler(req, res) {
  try {
    const raw = (req.query.url || '').toString();
    if (!raw) return res.status(400).json({ error: 'Missing url' });

    const u = new URL(raw);
    if (u.protocol !== 'https:') {
      return res.status(400).json({ error: 'Only https is allowed' });
    }
    if (!ALLOWED_HOSTS.includes(u.hostname)) {
      return res.status(400).json({ error: 'Host not allowed' });
    }

    const r = await fetch(u.toString(), {
      method: 'GET',
      headers: { 'User-Agent': 'DFS-Complaints-PDF-Proxy' },
      cache: 'no-store',
    });

    if (!r.ok) {
      return res.status(r.status).json({ error: `Upstream ${r.status}` });
    }

    const buf = Buffer.from(await r.arrayBuffer());

    res.setHeader('Content-Type', r.headers.get('content-type') || 'application/pdf');
    res.setHeader('Content-Disposition', 'inline; filename="document.pdf"');
    // Caching optional:
    res.setHeader('Cache-Control', 'public, max-age=3600, s-maxage=3600');

    // CORS ist nicht nötig, da Same-Origin – schadet aber nicht:
    res.setHeader('Access-Control-Allow-Origin', '*');

    res.status(200).send(buf);
  } catch (e) {
    res.status(500).json({ error: 'Proxy failed', detail: String(e) });
  }
}
