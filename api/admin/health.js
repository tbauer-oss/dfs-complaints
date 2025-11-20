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
import { verifyTransport } from '../_lib/mail.js';
import { monitorEventLoopDelay } from 'node:perf_hooks';

const ADMIN_SECRET = process.env.ADMIN_SECRET || '';
const hasRedisUrl = !!process.env.UPSTASH_REDIS_REST_URL;
const hasRedisToken = !!process.env.UPSTASH_REDIS_REST_TOKEN;
const MAIL_REQUIRED = ['SMTP_HOST', 'SMTP_USER', 'SMTP_PASS'];
const MAIL_OPTIONAL = ['SMTP_PORT', 'SMTP_FROM', 'MAIL_FROM', 'MAIL_REPLY_TO', 'MAIL_QM'];
const JWT_SECRET = process.env.JWT_SECRET?.trim();
const GATE_JWT_TTL = process.env.GATE_JWT_TTL?.trim();
const HEALTH_PING_URL = process.env.HEALTH_PING_URL?.trim();

const STATUS_ORDER = {
  ok: 0,
  warn: 1,
  critical: 2,
};

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

function normalizeCheck(entry, fallbackOrder = 100) {
  const status = entry.status || (entry.ok ? 'ok' : 'critical');
  const order = Number.isFinite(entry.order) ? entry.order : fallbackOrder;
  return {
    ...entry,
    status,
    order,
  };
}

function combineStatus(entries) {
  const worst = entries.reduce((acc, cur) => {
    const status = cur.status || (cur.ok ? 'ok' : 'critical');
    const rank = STATUS_ORDER[status] ?? STATUS_ORDER.critical;
    return Math.max(acc, rank);
  }, STATUS_ORDER.ok);
  return Object.keys(STATUS_ORDER).find((key) => STATUS_ORDER[key] === worst) || 'critical';
}

async function checkRedis() {
  const label = 'Redis / Upstash';
  if (!hasRedisUrl || !hasRedisToken) {
    return {
      ok: false,
      status: 'critical',
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
      status: okResult ? 'ok' : 'critical',
      label,
      message: okResult ? 'Schreiben & Lesen erfolgreich' : 'Rücklesung weicht vom Testwert ab',
      meta: { durationMs },
      order: 1,
    };
  } catch (err) {
    return {
      ok: false,
      status: 'critical',
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
      status: 'ok',
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
      status: 'warn',
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
      status: 'ok',
      label,
      message: 'API_BASE gesetzt',
      details: 'URL geprüft und gültig.',
      meta: { value: base },
      order: 2,
    };
  } catch (err) {
    return {
      ok: false,
      status: 'critical',
      label,
      message: 'Ungültige URL in API_BASE',
      details: err?.message || String(err),
      meta: { value: base },
      order: 2,
    };
  }
}

function checkAdminSecret(req) {
  const label = 'Admin-Secret';
  const providedHeader = typeof req.headers?.['x-admin-secret'] === 'string';

  if (!ADMIN_SECRET) {
    return {
      ok: false,
      status: 'critical',
      label,
      message: 'ADMIN_SECRET fehlt',
      details: 'Bitte eine geheime Zeichenkette setzen, um den Admin-Endpunkt zu schützen.',
      meta: { headerReceived: providedHeader },
      order: 0,
    };
  }

  return {
    ok: true,
    status: 'ok',
    label,
    message: 'ADMIN_SECRET gesetzt',
    details: providedHeader
      ? 'Anfrage enthielt den Admin-Header.'
      : 'Kein X-Admin-Secret-Header vorhanden.',
    meta: { headerReceived: providedHeader },
    order: 0,
  };
}

function checkGateJwtConfig() {
  const label = 'Gate / JWT';
  if (!JWT_SECRET) {
    return {
      ok: false,
      status: 'critical',
      label,
      message: 'JWT_SECRET fehlt',
      details: 'Gate-Tokens können ohne Signatur-Secret nicht ausgestellt werden.',
      meta: { hasSecret: false, ttl: GATE_JWT_TTL || null },
      order: 4,
    };
  }

  const ttlNumber = GATE_JWT_TTL ? Number(GATE_JWT_TTL) : null;
  if (GATE_JWT_TTL && (!Number.isFinite(ttlNumber) || ttlNumber <= 0)) {
    return {
      ok: false,
      status: 'critical',
      label,
      message: 'Ungültiger Wert in GATE_JWT_TTL',
      details: 'Bitte eine positive Zahl in Sekunden konfigurieren.',
      meta: { hasSecret: true, ttl: GATE_JWT_TTL },
      order: 4,
    };
  }

  return {
    ok: true,
    status: 'ok',
    label,
    message: 'JWT_SECRET gültig',
    details: ttlNumber ? `Token-Lebensdauer: ${ttlNumber} Sekunden.` : 'Standard-TTL (15 Minuten) wird genutzt.',
    meta: { hasSecret: true, ttl: ttlNumber || 900 },
    order: 4,
  };
}

async function checkMailConfig() {
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

  let transportVerified = null;
  let transportDurationMs = null;
  let transportError = null;

  if (okResult) {
    const started = Date.now();
    try {
      await verifyTransport();
      transportVerified = true;
      transportDurationMs = Date.now() - started;
      notes.push('SMTP-Transport erfolgreich via verifyTransport() geprüft.');
    } catch (err) {
      transportVerified = false;
      transportDurationMs = Date.now() - started;
      transportError = err?.message || String(err);
      notes.push(`SMTP-Transport konnte nicht aufgebaut werden: ${transportError}`);
    }
  }

  const okFinal = okResult && transportVerified !== false;

  return {
    ok: okFinal,
    status: okFinal ? 'ok' : transportVerified === false ? 'critical' : 'warn',
    label,
    message: okFinal
      ? 'SMTP-Einstellungen vollständig (Verbindung getestet)'
      : okResult
        ? 'SMTP-Server nicht erreichbar'
        : `Fehlende Pflicht-Variablen: ${missingRequired.join(', ')}`,
    details: transportError
      ? transportError
      : missingOptional.length
        ? `Optionale Variablen fehlen: ${missingOptional.join(', ')}`
        : undefined,
    meta: {
      missingRequired,
      missingOptional,
      notes,
      transportVerified,
      transportDurationMs,
      transportError,
    },
    order: 3,
  };
}

async function checkServerAvailability(req) {
  const label = 'Server-Verfügbarkeit';
  const target = HEALTH_PING_URL || (process.env.API_BASE || '').trim() || deriveOrigin(req);

  if (!target) {
    return {
      ok: false,
      status: 'warn',
      label,
      message: 'Keine Basis-URL für Ping vorhanden',
      details: 'Bitte HEALTH_PING_URL oder API_BASE setzen oder den Check mit Host aufrufen.',
      meta: { missingUrl: true },
      order: 5,
    };
  }

  const started = Date.now();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 4000);

  try {
    const res = await fetch(target, { method: 'HEAD', signal: controller.signal });
    clearTimeout(timeout);
    const durationMs = Date.now() - started;
    const slow = durationMs >= 2000;
    const is4xx = res.status >= 400 && res.status < 500;
    const is404 = res.status === 404;

    let status = 'ok';
    let message = 'Server erreichbar';
    const meta = { durationMs, url: target, httpStatus: res.status };

    if (res.ok) {
      status = slow ? 'warn' : 'ok';
      if (slow) message = 'Server erreichbar (langsame Antwort)';
    } else if (is4xx) {
      meta.clientError = true;
      if (is404) {
        status = 'ok';
        message =
          'Server erreichbar (Basis-URL liefert HTTP 404 – ggf. HEALTH_PING_URL oder gültigen Pfad setzen)';
      } else {
        status = 'warn';
        message = 'Server erreichbar – Pfad liefert HTTP 4xx (Authentifizierung/Berechtigung prüfen?)';
      }
    } else {
      status = res.status >= 500 ? 'critical' : 'warn';
      message = res.status >= 500 ? 'Server-Fehler' : 'Server antwortet mit Fehlercode';
    }

    const details = `HTTP ${res.status} – Antwortzeit ${durationMs} ms`;
    return {
      ok: status === 'ok',
      status,
      label,
      message,
      details,
      meta,
      order: 5,
    };
  } catch (err) {
    clearTimeout(timeout);
    return {
      ok: false,
      status: 'critical',
      label,
      message: 'Server nicht erreichbar',
      details: err?.message || String(err),
      meta: { durationMs: Date.now() - started, url: target },
      order: 5,
    };
  }
}

async function checkServerStability() {
  const label = 'Server-Stabilität';
  const histogram = monitorEventLoopDelay({ resolution: 20 });
  histogram.enable();
  await new Promise((resolve) => setTimeout(resolve, 250));
  histogram.disable();

  const meanMs = Number.isFinite(histogram.mean) ? Number(histogram.mean / 1e6) : 0;
  const maxMs = Number.isFinite(histogram.max) ? Number(histogram.max / 1e6) : 0;
  const uptimeSeconds = Math.round(process.uptime());

  let status = 'ok';
  let message = 'Event-Loop stabil';
  if (meanMs > 300 || maxMs > 800) {
    status = 'critical';
    message = 'Event-Loop stark blockiert';
  } else if (meanMs > 120 || maxMs > 400) {
    status = 'warn';
    message = 'Erhöhte Event-Loop-Latenz';
  }

  const notes = [];
  if (uptimeSeconds < 300) {
    notes.push('Server läuft weniger als 5 Minuten (kürzlicher Neustart?).');
  }

  return {
    ok: status === 'ok',
    status,
    label,
    message,
    details: `Ø ${meanMs.toFixed(1)} ms, max ${maxMs.toFixed(1)} ms – Uptime ${Math.round(uptimeSeconds / 60)} min`,
    meta: {
      meanLatencyMs: Number(meanMs.toFixed(1)),
      maxLatencyMs: Number(maxMs.toFixed(1)),
      uptimeSeconds,
      notes,
    },
    order: 6,
  };
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const adminSecretCheck = checkAdminSecret(req);
  if (ADMIN_SECRET && !isAdmin(req)) return bad(res, 'admin unauthorized', 401);
  if (req.method !== 'GET') return methodNotAllowed(res);

  try {
    const redisCheck = await checkRedis();
    const apiCheck = checkApiBase(req);
    const mailCheck = await checkMailConfig();
    const gateJwtCheck = checkGateJwtConfig();
    const availabilityCheck = await checkServerAvailability(req);
    const stabilityCheck = await checkServerStability();

    const rawChecks = {
      adminSecret: adminSecretCheck,
      redis: redisCheck,
      apiBase: apiCheck,
      mail: mailCheck,
      gateJwt: gateJwtCheck,
      availability: availabilityCheck,
      stability: stabilityCheck,
    };

    const checks = Object.entries(rawChecks).reduce((acc, [key, value], index) => {
      acc[key] = normalizeCheck(value, index);
      return acc;
    }, {});

    const status = combineStatus(Object.values(checks));
    return ok(res, {
      ok: status === 'ok',
      status,
      timestamp: new Date().toISOString(),
      checks,
    });
  } catch (err) {
    console.error('admin/health error:', err);
    return bad(res, 'server error', 500);
  }
}
