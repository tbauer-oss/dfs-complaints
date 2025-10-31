export const config = { runtime: 'nodejs' };

export default async function handler(req, res) {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  let raw = Buffer.concat(chunks).toString('utf8');
  let json = null;
  try { json = JSON.parse(raw || '{}'); } catch {}
  res.setHeader('Content-Type','application/json');
  res.end(JSON.stringify({
    ok: true,
    method: req.method,
    url: req.url,
    origin: req.headers.origin || null,
    headers: {
      'content-type': req.headers['content-type'] || null,
      'sec-fetch-mode': req.headers['sec-fetch-mode'] || null,
    },
    rawBody: raw || null,
    jsonBody: json,
  }, null, 2));
}
