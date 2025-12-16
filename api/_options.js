// api/_options.js
export const config = { runtime: 'nodejs' };

const PROD_ORIGIN = 'https://dfs-complaints-web.vercel.app';
const LOCAL_ORIGIN = /^http:\/\/localhost(?::\d+)?$/i;

export default function handler(req, res) {
  const origin = req?.headers?.origin || '';
  const allowOrigin = origin === PROD_ORIGIN || LOCAL_ORIGIN.test(origin) ? origin : PROD_ORIGIN;

  res.setHeader('Access-Control-Allow-Origin', allowOrigin);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('Access-Control-Max-Age', '86400');

  res.statusCode = 204;
  res.end();
}
