// /api/gate/request.js
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, bad } from '../_lib/http.js';

export default async function handler(req, res) {
  // CORS immer so früh wie möglich setzen, auch wenn das eigentliche
  // Handler-Modul später fehlschlägt oder langsam lädt.
  setCors(req, res);
  if (handlePreflight(req, res)) return;

  try {
    const { default: gateRequestHandler } = await import('../auth/gate-request.js');
    return gateRequestHandler(req, res);
  } catch (err) {
    // Falls der eigentliche Handler nicht geladen werden kann, trotzdem
    // eine sinnvolle JSON-Antwort mit CORS-Header senden.
    console.error('gate/request bootstrap failed:', err);
    const message = err?.message || 'internal error';
    return bad(res, message, 500);
  }
}
