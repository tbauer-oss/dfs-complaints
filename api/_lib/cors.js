// api/_lib/cors.js
const PROD_FE = 'https://dfs-complaints-web.vercel.app';
const PREVIEW = /^https:\/\/dfs-complaints-web-[a-z0-9-]+(?:-[a-z0-9-]+)?\.vercel\.app$/i;
const DIAMON_DOMAIN = /^https:\/\/([a-z0-9-]+\.)?dfs-diamon\.com$/i;

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
  
  // Zulässige Origins: Prod + Preview + lokales Testing (optional)
  const allow =
    origin &&
    (origin === PROD_FE || PREVIEW.test(origin) || DIAMON_DOMAIN.test(origin) || origin.startsWith('http://localhost'))
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
