// api/_lib/cors.js
// Die Optionen-Route wird aus vercel.json aufgerufen und braucht die gleiche
// CORS-Logik wie die anderen Handler. Statt einer leicht abweichenden Kopie
// nutzen wir dieselbe Implementierung wie in _lib/http.js.
import { isAllowedOrigin, PROD_FE } from './http.js';

/**
 * Einheitliche CORS-Konfiguration für alle API-Routen
 * - erlaubt PROD + PREVIEW URLs
 * - erlaubt Authorization + Admin + Gate + Rep Header
 * - unterstützt alle gängigen HTTP-Methoden
 */
export function setCors(req, res) {
  const origin = req?.headers?.origin || req?.headers?.Origin || '';
  const allow = isAllowedOrigin(origin) ? origin : PROD_FE;

  // Kern-Header
  res?.setHeader?.('Access-Control-Allow-Origin', allow);
  res?.setHeader?.('Vary', 'Origin');
  res?.setHeader?.('Access-Control-Allow-Credentials', 'true');
  res?.setHeader?.('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');

  // Browser gewünschte Header spiegeln; Baseline immer erlauben
  const requested = req?.headers?.['access-control-request-headers'];
  const baseline = 'Content-Type, Authorization, X-Admin-Secret, X-Gate, X-Rep-Secret, X-Debug';
  const allowHeaders = requested && String(requested).trim()
    ? `${baseline}, ${requested}`
    : baseline;
  res?.setHeader?.('Access-Control-Allow-Headers', allowHeaders);

  // Optional lesbare Response-Header
  res?.setHeader?.('Access-Control-Expose-Headers', 'Content-Type');

  // Preflight-Caching
  res?.setHeader?.('Access-Control-Max-Age', '600');

  // Einheitliches Response-Encoding
  if (!res?.getHeader?.('Content-Type')) {
    res?.setHeader?.('Content-Type', 'application/json; charset=utf-8');
  }
}
