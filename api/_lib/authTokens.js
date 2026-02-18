import jwt from 'jsonwebtoken';

const ACCESS_SECRET = String(process.env.ACCESS_JWT_SECRET || process.env.JWT_SECRET || '').trim() || 'devsecret';
const REFRESH_SECRET = String(process.env.REFRESH_JWT_SECRET || ACCESS_SECRET).trim();
const ACCESS_EXPIRES_IN = String(process.env.ACCESS_JWT_EXPIRES_IN || '1h').trim();
const REFRESH_EXPIRES_IN = String(process.env.REFRESH_JWT_EXPIRES_IN || '30d').trim();
const REFRESH_COOKIE_NAME = String(process.env.REFRESH_COOKIE_NAME || 'dfs_refresh_token').trim();
const REFRESH_COOKIE_SAME_SITE = String(process.env.REFRESH_COOKIE_SAMESITE || 'Lax').trim();
const REFRESH_COOKIE_SECURE = String(process.env.REFRESH_COOKIE_SECURE || 'true').toLowerCase() !== 'false';

function toLowerHeaders(headers = {}) {
  return Object.entries(headers).reduce((acc, [k, v]) => {
    acc[String(k || '').toLowerCase()] = v;
    return acc;
  }, {});
}

export function parseCookies(req) {
  const headers = toLowerHeaders(req?.headers || {});
  const raw = headers.cookie || '';
  const cookies = {};
  raw.split(';').forEach((part) => {
    const idx = part.indexOf('=');
    if (idx <= 0) return;
    const key = decodeURIComponent(part.slice(0, idx).trim());
    const value = decodeURIComponent(part.slice(idx + 1).trim());
    if (key) cookies[key] = value;
  });
  return cookies;
}

export function signAccessToken(payload) {
  return jwt.sign(payload, ACCESS_SECRET, { expiresIn: ACCESS_EXPIRES_IN });
}

export function signRefreshToken(payload) {
  return jwt.sign(payload, REFRESH_SECRET, { expiresIn: REFRESH_EXPIRES_IN });
}

export function verifyAccessToken(token) {
  return jwt.verify(token, ACCESS_SECRET);
}

export function verifyRefreshToken(token) {
  return jwt.verify(token, REFRESH_SECRET);
}

function appendSetCookie(res, cookieValue) {
  const prev = res.getHeader('Set-Cookie');
  if (!prev) {
    res.setHeader('Set-Cookie', cookieValue);
    return;
  }
  if (Array.isArray(prev)) {
    res.setHeader('Set-Cookie', [...prev, cookieValue]);
    return;
  }
  res.setHeader('Set-Cookie', [prev, cookieValue]);
}

export function setRefreshCookie(res, token, { clear = false } = {}) {
  const parts = [
    `${REFRESH_COOKIE_NAME}=${clear ? '' : encodeURIComponent(token)}`,
    'Path=/',
    'HttpOnly',
    `SameSite=${REFRESH_COOKIE_SAME_SITE}`,
  ];
  if (REFRESH_COOKIE_SECURE) parts.push('Secure');
  if (clear) {
    parts.push('Max-Age=0');
    parts.push('Expires=Thu, 01 Jan 1970 00:00:00 GMT');
  }
  appendSetCookie(res, parts.join('; '));
}

export function clearRefreshCookie(res) {
  setRefreshCookie(res, '', { clear: true });
}

export function getRefreshTokenFromRequest(req) {
  const cookies = parseCookies(req);
  return cookies[REFRESH_COOKIE_NAME] || '';
}

export const authTokenConfig = {
  accessExpiresIn: ACCESS_EXPIRES_IN,
  refreshExpiresIn: REFRESH_EXPIRES_IN,
  refreshCookieName: REFRESH_COOKIE_NAME,
};
