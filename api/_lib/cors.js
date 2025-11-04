// api/_lib/cors.js
const PROD_FE = 'https://dfs-complaints-web.vercel.app';
const PREVIEW = /^https:\/\/dfs-complaints-web-[a-z0-9-]+(?:-[a-z0-9-]+)?\.vercel\.app$/i;

export function setCors(req, res, allowHeaders = 'Content-Type, Authorization, X-Gate') {
  const origin = req.headers.origin || '';
  const allow  = origin && (origin === PROD_FE || PREVIEW.test(origin)) ? origin : (process.env.WEB_ORIGIN || PROD_FE);
  res.setHeader('Access-Control-Allow-Origin', allow);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', allowHeaders);
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
}
