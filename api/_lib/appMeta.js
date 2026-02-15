import { redis } from './redis.js';

const APP_META_KEY = process.env.APP_META_KEY || 'dfs:app:meta';
const BLOB_TOKEN = (process.env.BLOB_READ_WRITE_TOKEN || process.env.BLOB_TOKEN || '').trim();
const BLOB_BASE_URL = (process.env.BLOB_BASE_URL || 'https://blob.vercel-storage.com').replace(/\/+$/, '');
const BLOB_APP_META_PATH = (process.env.APP_META_BLOB_PATH || 'meta/app-meta.json').replace(/^\/+/, '');

const CACHE_TTL_MS = 30_000;
let cachedMeta = null;
let cachedAt = 0;

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
    const normalized = value.trim().toLowerCase();
    return ['true', '1', 'yes', 'on'].includes(normalized);
  }
  return false;
};

const normalizeList = (value) => {
  if (!value) return [];
  if (Array.isArray(value)) {
    return Array.from(
      new Set(
        value
          .flatMap((entry) => normalizeList(entry))
          .filter((entry) => typeof entry === 'string' && entry.trim())
          .map((entry) => entry.trim()),
      ),
    );
  }
  if (typeof value === 'string') {
    const tokens = value
      .split(/[;,\n]/g)
      .map((entry) => entry.trim())
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

async function blobGet() {
  if (!BLOB_TOKEN) return null;
  const res = await fetch(`${BLOB_BASE_URL}/${BLOB_APP_META_PATH}`, {
    headers: { Authorization: `Bearer ${BLOB_TOKEN}` },
    cache: 'no-store',
  });
  if (!res.ok) return null;
  try {
    return await res.json();
  } catch {
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

async function readKvMeta() {
  const raw = await redis.get(APP_META_KEY);
  if (!raw) return null;
  return sanitizeAppMeta(raw);
}

async function writeKvMeta(meta) {
  await redis.set(APP_META_KEY, meta);
}

export async function loadAppMeta({ refresh = false } = {}) {
  const now = Date.now();
  if (!refresh && cachedMeta && now - cachedAt < CACHE_TTL_MS) {
    return cachedMeta;
  }

  let meta = await readKvMeta();
  if (!meta) {
    const fromBlob = await blobGet();
    meta = sanitizeAppMeta(fromBlob || defaultAppMeta());
    await writeKvMeta(meta);
  }

  cachedMeta = meta;
  cachedAt = now;
  return meta;
}

export async function persistAppMeta(meta) {
  const sanitized = sanitizeAppMeta(meta);
  await writeKvMeta(sanitized);
  cachedMeta = sanitized;
  cachedAt = Date.now();
  if (BLOB_TOKEN) {
    await blobSet(sanitized);
  }
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

  const filtered = normalized.filter((token) => allowed.includes(token));
  return { tokens: filtered, testMode: true, allowed, suppressed: filtered.length === 0 };
}
