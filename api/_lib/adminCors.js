export function applyAdminCors(req, res) {
  const origin = req.headers.origin || '';
  const allowed = new Set([
    'https://dfs-complaints-web.vercel.app',
    'http://localhost:3000',
    'http://localhost:5173',
  ]);
  const normalizeOrigin = (value) => {
    if (!value) return '';
    try {
      const url = new URL(value);
      const isHttpsDefault = url.protocol === 'https:' && (url.port === '' || url.port === '443');
      const isHttpDefault = url.protocol === 'http:' && (url.port === '' || url.port === '80');
      if (isHttpsDefault || isHttpDefault) {
        return `${url.protocol}//${url.hostname}`;
      }
      return url.origin;
    } catch {
      return value.trim().toLowerCase();
    }
  };
  const normalized = normalizeOrigin(origin);

  if (allowed.has(normalized)) {
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Vary', 'Origin');
    res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
    res.setHeader(
      'Access-Control-Allow-Headers',
      'Content-Type, Authorization, X-Requested-With, X-Admin-Secret, X-Gate'
    );
    res.setHeader('Access-Control-Max-Age', '86400');
    res.setHeader('Access-Control-Allow-Credentials', 'true');
  }
  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return true;
  }
  return false;
}
