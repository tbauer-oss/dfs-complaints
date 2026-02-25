// api/account/password.js
export const config = { runtime: 'nodejs' };

import bcrypt from 'bcryptjs';
import { getAuthUser } from '../_lib/auth.js';
import { query } from '../_lib/db.js';
import { methodNotAllowed, setCors } from '../_lib/http.js';
import { invalidatePortalUserCaches } from '../_lib/portalUserCache.js';

const BCRYPT_PREFIX_PATTERN = /^\$(2[aby])\$/;
const UUID_V4_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const UUID_ANYWHERE_PATTERN = /[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/i;

function sendJson(res, statusCode, payload) {
  res.statusCode = statusCode;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify(payload));
}

async function readJsonBody(req) {
  if (req.body && typeof req.body === 'object') return req.body;

  const parse = (value) => {
    if (typeof value === 'string') {
      const trimmed = value.trim();
      return JSON.parse(trimmed || '{}');
    }
    if (Buffer.isBuffer(value)) {
      const trimmed = value.toString('utf8').trim();
      return JSON.parse(trimmed || '{}');
    }
    return value && typeof value === 'object' ? value : {};
  };

  if (req.body != null) return parse(req.body);

  const raw = await new Promise((resolve, reject) => {
    if (!req || typeof req.on !== 'function') return resolve('');
    let chunks = '';
    req.on('data', (chunk) => {
      chunks += Buffer.isBuffer(chunk) ? chunk.toString('utf8') : String(chunk || '');
    });
    req.on('end', () => resolve(chunks));
    req.on('error', reject);
  });

  return parse(raw);
}

function isDbConnectivityError(err) {
  return String(err?.code || '').toUpperCase() === 'DB_UNAVAILABLE';
}

function normalizeBcryptHash(passwordHash) {
  const hash = String(passwordHash || '').trim();
  if (!hash) return '';
  if (hash.startsWith('$2y$')) return `$2b$${hash.slice(4)}`;
  if (!BCRYPT_PREFIX_PATTERN.test(hash)) return '';
  return hash;
}

function normalizeEmail(value) {
  return String(value || '').trim().toLowerCase();
}

function classifySubjectFormat(subject) {
  if (!subject) return 'empty';
  if (UUID_V4_PATTERN.test(subject)) return 'uuid';
  if (/^(user|portal):/i.test(subject)) return 'prefixed_uuid_or_id';
  if (/^[^\s|]+\|[^\s|]+$/.test(subject)) return 'provider_pipe';
  if (subject.includes('@')) return 'email_like';
  return 'opaque';
}

function extractUuidFromSubject(subject) {
  const raw = String(subject || '').trim();
  if (!raw) return '';
  if (UUID_V4_PATTERN.test(raw)) return raw.toLowerCase();

  const match = raw.match(UUID_ANYWHERE_PATTERN);
  if (!match) return '';
  const candidate = String(match[0] || '').toLowerCase();
  return UUID_V4_PATTERN.test(candidate) ? candidate : '';
}

function getSubjectIdCandidates(subject) {
  const raw = String(subject || '').trim();
  if (!raw) return [];

  const candidates = [];
  const add = (value) => {
    const next = String(value || '').trim();
    if (!next) return;
    if (!candidates.includes(next)) candidates.push(next);
  };

  const extractedUuid = extractUuidFromSubject(raw);
  if (extractedUuid) add(extractedUuid);

  const prefixed = raw.match(/^(?:user|portal):(.+)$/i);
  if (prefixed?.[1]) add(prefixed[1]);

  add(raw);
  return candidates;
}


async function resolvePortalUser({ authSubject, authEmail, isProd }) {
  const subjectFormat = classifySubjectFormat(authSubject);
  const normalizedEmail = normalizeEmail(authEmail);
  const extractedSubjectUuid = extractUuidFromSubject(authSubject);
  const subjectIdCandidates = getSubjectIdCandidates(authSubject);

  const strategies = [];
  for (const candidate of subjectIdCandidates) strategies.push({ type: 'by_id', value: candidate });
  if (normalizedEmail) strategies.push({ type: 'by_email', value: normalizedEmail });

  if (!isProd) {
    console.debug('[account/password] lookup candidates', {
      subjectFormat,
      hasAuthEmail: Boolean(normalizedEmail),
      hasExtractedSubjectUuid: Boolean(extractedSubjectUuid),
      subjectIdCandidatesCount: subjectIdCandidates.length,
      strategies: strategies.map((entry) => entry.type),
    });
  } else {
    console.info('[account/password] lookup_start', {
      code: 'LOOKUP_START',
      subjectFormat,
      strategyCount: strategies.length,
    });
  }

  for (const strategy of strategies) {
    let userResult;
    if (strategy.type === 'by_id') {
      userResult = await query(
        `SELECT id, email_norm, password_hash
         FROM portal_users
         WHERE id::text = $1
         LIMIT 1`,
        [strategy.value],
      );
    } else {
      userResult = await query(
        `SELECT id, email_norm, password_hash
         FROM portal_users
         WHERE email_norm = $1
            OR LOWER(TRIM(COALESCE(email, ''))) = $1
         LIMIT 1`,
        [strategy.value],
      );
    }

    const rows = Number(userResult?.rowCount ?? userResult?.rows?.length ?? 0);
    if (!isProd) {
      console.debug('[account/password] lookup attempt', {
        strategy: strategy.type,
        subjectFormat,
        rows,
      });
    } else {
      console.info('[account/password] lookup_attempt', {
        code: rows > 0 ? 'LOOKUP_HIT' : 'LOOKUP_MISS',
        strategy: strategy.type,
      });
    }

    if (rows > 0) {
      return {
        user: userResult.rows[0],
        debug: {
          strategyUsed: strategy.type,
          subjectFormat,
          rows,
          hasAuthEmail: Boolean(normalizedEmail),
          hasExtractedSubjectUuid: Boolean(extractedSubjectUuid),
          subjectIdCandidatesCount: subjectIdCandidates.length,
        },
      };
    }
  }

  return {
    user: null,
    debug: {
      strategyUsed: 'none',
      subjectFormat,
      rows: 0,
      hasAuthEmail: Boolean(normalizedEmail),
      hasExtractedSubjectUuid: Boolean(extractedSubjectUuid),
      subjectIdCandidatesCount: subjectIdCandidates.length,
    },
  };
}

export default async function handler(req, res) {
  const isProd = process.env.NODE_ENV === 'production';
  setCors(req, res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return methodNotAllowed(res);

  const auth = getAuthUser(req);
  if (!auth) {
    return sendJson(res, 401, { code: 'UNAUTHORIZED', message: 'Missing or invalid authorization token.' });
  }

  const authSubject = String(auth.sub || '').trim();
  const authEmail = normalizeEmail(auth.email);

  if (!authSubject && !authEmail) {
    return sendJson(res, 401, { code: 'UNAUTHORIZED', message: 'Token subject is missing.' });
  }

  let body;
  try {
    body = await readJsonBody(req);
  } catch {
    return sendJson(res, 400, { code: 'VALIDATION_ERROR', message: 'Request body must be valid JSON.' });
  }

  const presentKeys = body && typeof body === 'object' ? Object.keys(body).sort() : [];
  if (!isProd) {
    console.debug('[account/password] payload keys', presentKeys);
  }

  const currentPassword = body?.currentPassword
    ?? body?.current_password
    ?? body?.oldPassword
    ?? body?.old_password
    ?? body?.password;

  const newPassword = body?.newPassword
    ?? body?.new_password
    ?? body?.newPass
    ?? body?.new_pass;

  const confirmPassword = body?.confirmPassword
    ?? body?.confirm_password
    ?? body?.newPasswordRepeat
    ?? body?.new_password_repeat;

  if (!currentPassword || !newPassword) {
    return sendJson(res, 400, {
      code: 'VALIDATION_ERROR',
      message: 'Both currentPassword and newPassword are required.',
    });
  }

  if (String(newPassword).length < 8) {
    return sendJson(res, 400, {
      code: 'WEAK_PASSWORD',
      message: 'newPassword must be at least 8 characters long.',
    });
  }

  if (confirmPassword != null && String(confirmPassword) !== String(newPassword)) {
    return sendJson(res, 400, {
      code: 'PASSWORD_CONFIRM_MISMATCH',
      message: 'confirmPassword must match newPassword.',
    });
  }

  try {
    const resolution = await resolvePortalUser({ authSubject, authEmail, isProd });
    const user = resolution.user;
    if (!user) {
      if (!isProd) {
        console.debug('[account/password] user not found', resolution.debug);
      } else {
        console.info('[account/password] user_resolution_failed', {
          code: 'USER_NOT_FOUND',
          subjectFormat: resolution.debug.subjectFormat,
        });
      }
      return sendJson(res, 404, { code: 'USER_NOT_FOUND', message: 'User account not found.' });
    }

    if (resolution.debug.hasExtractedSubjectUuid
      && String(user.id) !== extractUuidFromSubject(authSubject)
      && !isProd) {
      console.warn('[account/password] auth subject does not match resolved user id', {
        subjectFormat: resolution.debug.subjectFormat,
        resolvedUserId: user.id,
        strategyUsed: resolution.debug.strategyUsed,
      });
    }

    const currentHash = normalizeBcryptHash(user.password_hash || '');
    if (!currentHash) {
      return sendJson(res, 400, {
        code: 'INVALID_CURRENT_PASSWORD',
        message: 'The current password is incorrect.',
      });
    }

    let ok = false;
    try {
      ok = await bcrypt.compare(currentPassword, currentHash);
    } catch {
      ok = false;
    }

    if (!ok) {
      return sendJson(res, 400, {
        code: 'INVALID_CURRENT_PASSWORD',
        message: 'The current password is incorrect.',
      });
    }

    const hash = await bcrypt.hash(newPassword, 10);

    await query(
      `UPDATE portal_users
       SET password_hash = $1,
           updated_at = NOW()
       WHERE id = $2`,
      [hash, user.id],
    );

    const cacheInfo = await invalidatePortalUserCaches(user.email_norm || auth.email, { logPrefix: 'account/password' });

    return sendJson(res, 200, { ok: true, cacheInvalidated: cacheInfo.cacheInvalidated });
  } catch (err) {
    if (isDbConnectivityError(err)) {
      return sendJson(res, 503, { code: 'DB_UNAVAILABLE', message: 'Database unavailable.' });
    }

    if (String(err?.code || '').toUpperCase() === '22P02') {
      return sendJson(res, 401, { code: 'UNAUTHORIZED', message: 'Invalid authorization subject.' });
    }

    console.error('[account/password] unexpected error', err);
    return sendJson(res, 500, { code: 'INTERNAL_ERROR', message: 'Internal server error.' });
  }
}
