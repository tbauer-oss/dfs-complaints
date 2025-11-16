// api/admin/health.js
export const config = { runtime: 'nodejs' };

import {
  handlePreflight,
  setCors,
  ok,
  bad,
  methodNotAllowed,
} from '../_lib/http.js';
import { redis } from '../_lib/redis.js';

const ADMIN_SECRET = process.env.ADMIN_SECRET || '';
const hasRedisUrl = !!process.env.UPSTASH_REDIS_REST_URL;
const hasRedisToken = !!process.env.UPSTASH_REDIS_REST_TOKEN;
const MAIL_REQUIRED = ['SMTP_HOST', 'SMTP_USER', 'SMTP_PASS'];
const MAIL_OPTIONAL = ['SMTP_PORT', 'SMTP_FROM', 'MAIL_FROM', 'MAIL_REPLY_TO', 'MAIL_QM'];

function isAdmin(req) {
  const hdr = req.headers?.['x-admin-secret'];
  return typeof hdr === 'string' && !!ADMIN_SECRET && hdr === ADMIN_SECRET;
}

function randomId() {
  return Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2);
}

function deriveOrigin(req) {
  const protoHeader =
    req.headers?.['x-forwarded-proto'] ||
    req.headers?.['x-forwarded-protocol'] ||
    req.headers?.['x-vercel-forwarded-proto'];
  const hostHeader = req.headers?.['x-forwarded-host'] || req.headers?.host;
  const proto = Array.isArray(protoHeader)
    ? protoHeader[0]
    : typeof protoHeader === 'string'
      ? protoHeader.split(',')[0]
      : undefined;
  const host = Array.isArray(hostHeader)
    ? hostHeader[0]
    : typeof hostHeader === 'string'
      ? hostHeader.split(',')[0]
      : undefined;
  if (!host) return null;
  const protocol = (proto || 'https').trim();
  return `${protocol}://${host.trim()}`;
}

async function checkRedis() {
  const label = 'Redis / Upstash';
  if (!hasRedisUrl || !hasRedisToken) {
    return {
      ok: false,
      label,
      message: 'UPSTASH_REDIS_REST_URL/_TOKEN fehlen',
      details: 'Bitte ENV-Variablen prüfen.',
      meta: {
        missingEnv: [
          ...(!hasRedisUrl ? ['UPSTASH_REDIS_REST_URL'] : []),
          ...(!hasRedisToken ? ['UPSTASH_REDIS_REST_TOKEN'] : []),
        ],
      },
      order: 1,
    };
  }

  const key = `dfs:health:${Date.now()}:${randomId()}`;
  const value = `dfs-health-${randomId()}`;
  const started = Date.now();

  try {
    await redis.set(key, value, { ex: 30 });
    const read = await redis.get(key);
    try {
      await redis.del(key);
    } catch (_) {
      /* ignore cleanup errors */
    }
    const durationMs = Date.now() - started;
    const okResult = read === value;
    return {
      ok: okResult,
      label,
      message: okResult ? 'Schreiben & Lesen erfolgreich' : 'Rücklesung weicht vom Testwert ab',
      meta: { durationMs },
      order: 1,
    };
  } catch (err) {
    return {
      ok: false,
      label,
      message: err?.message || String(err),
      meta: { durationMs: Date.now() - started },
      order: 1,
    };
  }
}

function checkApiBase(req) {
  const label = 'API-Konfiguration';
  const base = (process.env.API_BASE || '').trim();
  const derived = deriveOrigin(req);
  if (!base && derived) {
    return {
      ok: true,
      label,
      message: 'API_BASE nicht gesetzt – verwende Request-Host',
      details: `Verwendete Basis: ${derived}`,
      meta: { value: derived, source: 'derived', notes: ['Flutter & Mobile nutzen automatisch diesen Host, sofern kein API_BASE-Dart-Define gesetzt wurde.'] },
      order: 2,
    };
  }
  if (!base) {
    return {
      ok: false,
      label,
      message: 'API_BASE fehlt',
      details: 'Keine ENV gesetzt und Host konnte nicht bestimmt werden.',
      meta: { value: '', notes: ['Bitte API_BASE setzen oder den Check vom Client mit gültigem Host aufrufen.'] },
      order: 2,
    };
  }
  try {
    const url = new URL(base);
    if (!['http:', 'https:'].includes(url.protocol)) {
      throw new Error('Nur http/https erlaubt');
    }
    return {
      ok: true,
      label,
      message: 'API_BASE gesetzt',
      details: 'URL geprüft und gültig.',
      meta: { value: base },
      order: 2,
    };
  } catch (err) {
    return {
      ok: false,
      label,
      message: 'Ungültige URL in API_BASE',
      details: err?.message || String(err),
      meta: { value: base },
      order: 2,
    };
  }
}

function checkMailConfig() {
  const label = 'Mail-Konfiguration';
  const missingRequired = MAIL_REQUIRED.filter((key) => {
    const raw = process.env[key];
    return !raw || !String(raw).trim();
  });
  const missingOptional = MAIL_OPTIONAL.filter((key) => {
    const raw = process.env[key];
    return !raw || !String(raw).trim();
  });

  const okResult = missingRequired.length === 0;
  const notes = [];
  const senderSource =
    process.env.SMTP_FROM?.trim()
      ? 'SMTP_FROM'
      : process.env.MAIL_FROM?.trim()
        ? 'MAIL_FROM'
        : process.env.SMTP_USER?.trim()
          ? 'SMTP_USER'
          : null;
  if (senderSource) {
    notes.push(`Absender wird über ${senderSource} bereitgestellt.`);
  } else {
    notes.push('Kein Absender konfiguriert – bitte SMTP_FROM oder MAIL_FROM setzen.');
  }
  notes.push(
    okResult
      ? 'Mailversand (Registrierung, QM, Support) einsatzbereit.'
      : 'Registrierungs-, QM- und Support-Mails können ohne vollständige SMTP-Konfiguration nicht versendet werden.'
  );

  if (!process.env.SMTP_PORT) {
    notes.push('SMTP_PORT nicht gesetzt – Standard 587 wird genutzt.');
  }

  return {
    ok: okResult,
    label,
    message: okResult
      ? 'SMTP-Einstellungen vollständig'
      : `Fehlende Pflicht-Variablen: ${missingRequired.join(', ')}`,
    details: missingOptional.length
      ? `Optionale Variablen fehlen: ${missingOptional.join(', ')}`
      : undefined,
    meta: { missingRequired, missingOptional, notes },
    order: 3,
  };
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  if (!isAdmin(req)) return bad(res, 'admin unauthorized', 401);
  if (req.method !== 'GET') return methodNotAllowed(res);

  try {
    const redisCheck = await checkRedis();
    const apiCheck = checkApiBase(req);
    const mailCheck = checkMailConfig();
    const checks = { redis: redisCheck, apiBase: apiCheck, mail: mailCheck };
    const okOverall = Object.values(checks).every((entry) => entry.ok);
    return ok(res, {
      ok: okOverall,
      timestamp: new Date().toISOString(),
      checks,
    });
  } catch (err) {
    console.error('admin/health error:', err);
    return bad(res, 'server error', 500);
  }
}
