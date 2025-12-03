// api/_lib/appMeta.js – zentrale App-Metadaten (Version, Testmodus)
const APP_META_KEY = process.env.APP_META_KEY || 'dfs:app:meta';
const UPSTASH_URL = process.env.UPSTASH_REDIS_REST_URL || '';
const UPSTASH_TOKEN = process.env.UPSTASH_REDIS_REST_TOKEN || '';

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

async function upstashGet() {
  if (!UPSTASH_URL || !UPSTASH_TOKEN) return null;
  const res = await fetch(`${UPSTASH_URL}/get/${encodeURIComponent(APP_META_KEY)}`, {
    headers: { Authorization: `Bearer ${UPSTASH_TOKEN}` },
    cache: 'no-store',
  });
  if (!res.ok) return null;
  const json = await res.json();
  if (json && typeof json.result === 'string' && json.result) {
    try { return JSON.parse(json.result); } catch (_) {}
  }
  return null;
}

async function upstashSet(meta) {
  if (!UPSTASH_URL || !UPSTASH_TOKEN) return false;
  const body = JSON.stringify(meta);
  const res = await fetch(
    `${UPSTASH_URL}/set/${encodeURIComponent(APP_META_KEY)}/${encodeURIComponent(body)}`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${UPSTASH_TOKEN}` },
    },
  );
  return res.ok;
}

export async function loadAppMeta({ refresh = false } = {}) {
  const now = Date.now();
  if (!refresh && _cachedMeta && now - _cachedAt < CACHE_TTL_MS) {
    return _cachedMeta;
  }

  if (!UPSTASH_URL || !UPSTASH_TOKEN) {
    global.__APP_META__ = global.__APP_META__ || defaultAppMeta();
    _cachedMeta = sanitizeAppMeta(global.__APP_META__);
    _cachedAt = now;
    return _cachedMeta;
  }

  const stored = await upstashGet();
  const meta = sanitizeAppMeta(stored || defaultAppMeta());
  _cachedMeta = meta;
  _cachedAt = now;
  return meta;
}

export async function persistAppMeta(meta) {
  const sanitized = sanitizeAppMeta(meta);
  if (!UPSTASH_URL || !UPSTASH_TOKEN) {
    global.__APP_META__ = sanitized;
    _cachedMeta = sanitized;
    _cachedAt = Date.now();
    return true;
  }
  const ok = await upstashSet(sanitized);
  if (ok) {
    _cachedMeta = sanitized;
    _cachedAt = Date.now();
  }
  return ok;
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
