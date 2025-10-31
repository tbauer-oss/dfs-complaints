// /api/diag/env-kv.js
export const config = { runtime: 'nodejs' };

function mask(v) {
  if (!v) return null;
  const s = String(v);
  if (s.length <= 12) return '***';
  return s.slice(0, 6) + '…' + s.slice(-6);
}

export default async function handler(_req, res) {
  const keys = [
    'UPSTASH_REDIS_REST_URL',
    'UPSTASH_REDIS_REST_TOKEN',
    'UPSTASH_REDIS_REST_KV_REST_API_URL',
    'UPSTASH_REDIS_REST_KV_REST_API_TOKEN',
    'UPSTASH_REDIS_REST_KV_REST_API_READ_ONLY_TOKEN',
    'KV_REST_API_URL',
    'KV_REST_API_TOKEN',
    'REDIS_URL',
    'REDIS_TOKEN',
  ];
  const seen = {};
  for (const k of keys) {
    const v = process.env[k];
    seen[k] = { present: !!v, sample: mask(v) };
  }
  res.setHeader('Content-Type','application/json');
  res.end(JSON.stringify({ ok:true, env: seen }, null, 2));
}
