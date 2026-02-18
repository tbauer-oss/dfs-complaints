export const config = { runtime: 'nodejs' };

import jwt from 'jsonwebtoken';
import { bad, handlePreflight, methodNotAllowed, ok } from '../_lib/http.js';
import {
  getRefreshTokenFromRequest,
  setRefreshCookie,
  signAccessToken,
  signRefreshToken,
  verifyRefreshToken,
} from '../_lib/authTokens.js';

function getRefreshClaims(payload = {}) {
  return {
    sub: payload.sub,
    email: payload.email,
    role: payload.role,
    portalStatus: payload.portalStatus || 'active',
  };
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  if (req.method !== 'POST') return methodNotAllowed(res);

  const refreshToken = getRefreshTokenFromRequest(req);
  if (!refreshToken) {
    console.warn('[auth/refresh] 401 missing_refresh_cookie');
    return bad(res, 'unauthorized', 401, { reason: 'missing_refresh_cookie' });
  }

  let payload;
  try {
    payload = verifyRefreshToken(refreshToken);
  } catch (err) {
    if (err instanceof jwt.TokenExpiredError) {
      console.warn('[auth/refresh] 401 refresh_expired');
      return bad(res, 'unauthorized', 401, { reason: 'refresh_expired' });
    }
    console.warn('[auth/refresh] 401 refresh_invalid');
    return bad(res, 'unauthorized', 401, { reason: 'refresh_invalid' });
  }

  const claims = getRefreshClaims(payload);
  if (!claims.sub || !claims.email) {
    console.warn('[auth/refresh] 401 refresh_invalid');
    return bad(res, 'unauthorized', 401, { reason: 'refresh_invalid' });
  }

  const accessToken = signAccessToken(claims);

  // Refresh-Rotation: bei jedem erfolgreichen Refresh einen neuen Refresh-Token setzen.
  const rotatedRefreshToken = signRefreshToken(claims);
  setRefreshCookie(res, rotatedRefreshToken);

  return ok(res, { accessToken });
}
