import { setCors, noContent, methodNotAllowed } from './_lib/http.js';

export default function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);
  if (req.method === 'GET') {
    res.setHeader('Content-Type','application/json');
    return res.status(200).end(JSON.stringify({ endpoint:'gate', method:'GET' }));
  }
  if (req.method !== 'POST') return methodNotAllowed(res);

  const pass = process.env.AUTH_PASSWORD || '';
  try {
    const body = typeof req.body === 'object' ? req.body : JSON.parse(req.body || '{}');
    const pwd  = (body.password || '').toString().trim();
    if (!pass)        return res.writeHead(500).end('AUTH_PASSWORD missing');
    if (!pwd)         return res.writeHead(400).end('password required');
    if (pwd !== pass) return res.writeHead(401).end('invalid');

    res.setHeader('Content-Type','application/json');
    return res.status(200).end(JSON.stringify({ ok:true }));
  } catch {
    return res.writeHead(400).end('bad request');
  }
}
