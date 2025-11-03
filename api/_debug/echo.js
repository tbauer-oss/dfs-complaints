export const config = { runtime: 'nodejs' };

export default async function handler(req, res) {
  res.statusCode = 200;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify({
    ok: true,
    method: req.method,
    origin: req.headers?.origin || null,
    headers: req.headers,
  }));
}
