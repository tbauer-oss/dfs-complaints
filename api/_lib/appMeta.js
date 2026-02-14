import { redis } from './redis.js';
// api/_lib/appMeta.js – zentrale App-Metadaten (Version, Testmodus)
const APP_META_KEY = process.env.APP_META_KEY || 'dfs:app:meta';
const BLOB_TOKEN = (process.env.BLOB_READ_WRITE_TOKEN || process.env.BLOB_TOKEN || '').trim();
const BLOB_BASE_URL = (process.env.BLOB_BASE_URL || 'https://blob.vercel-storage.com').replace(/\/+$/, '');
const BLOB_APP_META_PATH = (process.env.APP_META_BLOB_PATH || 'meta/app-meta.json').replace(/^\/+/, '');

const CACHE_TTL_MS = 30_000;
let _cachedMeta = null;
let _cachedAt = 0;

const nowIso = () => new Date().toISOString();
const envBuild = () => {
  const fromEnv =
    process.env.APP_BUILD ||
    process.env.BUILD_ID ||
    process.env.VERCEL_GIT_COMMIT_SHA ||
    process.env.VERCEL_GIT_COMMIT_REF ||
    '';
  return fromEnv.toString();
};

const boolVal = (value) => {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value !== 0;
  if (typeof value === 'string') {
    const t = value.trim().toLowerCase();
    return ['true', '1', 'yes', 'on'].includes(t);
  }
  return false;
};

const normalizeList = (value) => {
  if (!value) return [];
  if (Array.isArray(value)) {
    return Array.from(
      new Set(
        value
          .flatMap((v) => normalizeList(v))
          .filter((v) => typeof v === 'string' && v.trim())
          .map((v) => v.trim()),
      ),
    );
  }
  if (typeof value === 'string') {
    const tokens = value
      .split(/[;,\n]/g)
      .map((v) => v.trim())
      .filter(Boolean);
    return Array.from(new Set(tokens));
  }
  return [];
};

export function defaultAppMeta() {
  return {
    version: '',
    build: envBuild(),
    notes: '',
    updatedAt: '',
    testMode: false,
    testEmail: '',
    testPushTokens: [],
  };
}

export function sanitizeAppMeta(input = {}) {
  const base = defaultAppMeta();
  const version = (input.version ?? base.version).toString().trim();
  const build = (input.build ?? base.build).toString().trim() || envBuild();
  const notes = (input.notes ?? base.notes).toString();
  const testEmail = (input.testEmail ?? input.testMail ?? '').toString().trim();
  const testPushTokens = normalizeList(
    input.testPushTokens || input.testPush || input.testPushDevices,
  );

  return {
    ...base,
    ...(version ? { version } : {}),
    ...(build ? { build } : {}),
    ...(notes ? { notes } : {}),
    testMode: boolVal(input.testMode),
    ...(testEmail ? { testEmail } : { testEmail: '' }),
    ...(testPushTokens.length > 0 ? { testPushTokens } : { testPushTokens: [] }),
    updatedAt: input.updatedAt || base.updatedAt,
  };
}

async function kvGet() {
  return redis.get(APP_META_KEY);
}

async function kvSet(meta) {
  await redis.set(APP_META_KEY, meta);
  return true;
}

async function blobGet() {
  if (!BLOB_TOKEN) return null;
  const res = await fetch(`${BLOB_BASE_URL}/${BLOB_APP_META_PATH}`, {
    headers: { Authorization: `Bearer ${BLOB_TOKEN}` },
    cache: 'no-store',
  });
  if (!res.ok) return null;
  try {
    return await res.json();
  } catch (_) {
    return null;
  }
}

async function blobSet(meta) {
  if (!BLOB_TOKEN) return false;
  const res = await fetch(`${BLOB_BASE_URL}/${BLOB_APP_META_PATH}`, {
    method: 'PUT',
    headers: {
      Authorization: `Bearer ${BLOB_TOKEN}`,
      'Content-Type': 'application/json; charset=utf-8',
    },
    body: JSON.stringify(meta),
  });
  return res.ok;
}

export async function loadAppMeta({ refresh = false } = {}) {
  const now = Date.now();
  if (!refresh && _cachedMeta && now - _cachedAt < CACHE_TTL_MS) {
    return _cachedMeta;
  }

  let meta = null;

  meta = await kvGet();

  if (!meta && BLOB_TOKEN) {
    meta = await blobGet();
  }

  if (!meta) {
    global.__APP_META__ = global.__APP_META__ || defaultAppMeta();
    meta = global.__APP_META__;
  }

  meta = sanitizeAppMeta(meta || defaultAppMeta());
  _cachedMeta = meta;
  _cachedAt = now;
  return meta;
}

export async function persistAppMeta(meta) {
  const sanitized = sanitizeAppMeta(meta);
  const ok = await kvSet(sanitized);
  if (ok) {
    _cachedMeta = sanitized;
    _cachedAt = Date.now();
    return true;
  }

  if (BLOB_TOKEN) {
    const ok = await blobSet(sanitized);
    if (ok) {
      _cachedMeta = sanitized;
      _cachedAt = Date.now();
      return true;
    }
  }

  global.__APP_META__ = sanitized;
  _cachedMeta = sanitized;
  _cachedAt = Date.now();
  return true;
}

export async function updateAppMeta(partial) {
  const existing = await loadAppMeta({ refresh: true });
  const next = sanitizeAppMeta({ ...existing, ...partial, updatedAt: nowIso() });
  await persistAppMeta(next);
  return next;
}

export function applyTestMailRouting(meta, { to, cc, subject }) {
  const list = normalizeList(to);
  const ccList = normalizeList(cc);
  if (!meta?.testMode) {
    return { to: list, cc: ccList, subject };
  }

  const testTargets = normalizeList(meta.testEmail);
  const prefixedSubject = subject?.toString().startsWith('[TESTSYSTEM]')
    ? subject
    : `[TESTSYSTEM] ${subject || ''}`.trim();

  if (testTargets.length === 0) {
    return { to: [], cc: [], subject: prefixedSubject, suppressed: true, original: { to: list, cc: ccList } };
  }

  return {
    to: testTargets,
    cc: [],
    subject: prefixedSubject,
    testMode: true,
    original: { to: list, cc: ccList },
  };
}

export function applyTestPushRouting(meta, tokens = []) {
  const normalized = normalizeList(tokens);
  if (!meta?.testMode) return { tokens: normalized, testMode: false };

  const allowed = normalizeList(meta.testPushTokens);
  if (allowed.length === 0) {
    return { tokens: [], testMode: true, suppressed: true };
  }

  const filtered = normalized.filter((t) => allowed.includes(t));
  return { tokens: filtered, testMode: true, allowed, suppressed: filtered.length === 0 };
}
