// api/_lib/cors.js
const PROD_FE = 'https://dfs-complaints-web.vercel.app';
const ADMIN_FE = process.env.ADMIN_ORIGIN || PROD_FE;
const PREVIEW_WEB = /^https:\/\/dfs-complaints-web-[a-z0-9-]+(?:-[a-z0-9-]+)?\.vercel\.app$/i;
const PREVIEW_ADMIN = /^https:\/\/dfs-complaints-admin-[a-z0-9-]+(?:-[a-z0-9-]+)?\.vercel\.app$/i;
const DIAMON_DOMAIN = /^https:\/\/([a-z0-9-]+\.)?dfs-diamon\.com$/i;
const LOCAL_PATTERN = /^http:\/\/localhost(?::\d+)?$/i;

function extraOrigins() {
  return (process.env.CORS_EXTRA_ORIGINS || '')
    .split(',')
    .map((o) => o.trim())
    .filter(Boolean);
}

/**
 * Einheitliche CORS-Konfiguration für alle API-Routen
 * - erlaubt PROD + PREVIEW URLs
 * - erlaubt Authorization + Admin + Gate + Rep Header
 * - unterstützt alle gängigen HTTP-Methoden
 */
export function setCors(
  req,
  res,
  allowHeaders = 'Content-Type, Authorization, X-Admin-Secret, X-Gate, X-Rep-Secret, X-Debug'
) {
  const headers = req?.headers ?? {};
  const origin = headers.origin || headers.Origin || '';
  
  // Zulässige Origins: Prod + Preview + Admin + Diamon + lokales Testing + optional extra
  const allow =
    origin &&
    (origin === PROD_FE ||
      origin === ADMIN_FE ||
      PREVIEW_WEB.test(origin) ||
      PREVIEW_ADMIN.test(origin) ||
      DIAMON_DOMAIN.test(origin) ||
      LOCAL_PATTERN.test(origin) ||
      extraOrigins().includes(origin))
      ? origin
      : (process.env.WEB_ORIGIN || PROD_FE);

  // Standard-Header
  res?.setHeader?.('Access-Control-Allow-Origin', allow);
  res?.setHeader?.('Vary', 'Origin');
  res?.setHeader?.('Access-Control-Allow-Credentials', 'true');
  res?.setHeader?.(
    'Access-Control-Allow-Methods',
    'GET,POST,PUT,PATCH,DELETE,OPTIONS'
  );
  res?.setHeader?.('Access-Control-Allow-Headers', allowHeaders);
  
  // Einheitliches Response-Encoding
  res?.setHeader?.('Content-Type', 'application/json; charset=utf-8');
}
