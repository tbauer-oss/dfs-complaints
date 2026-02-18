export const config = { runtime: 'nodejs' };

import { handlePreflight, methodNotAllowed, noContent } from '../_lib/http.js';
import { clearRefreshCookie } from '../_lib/authTokens.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  if (req.method !== 'POST') return methodNotAllowed(res);

  clearRefreshCookie(res);
  return noContent(res);
}
