// =======================================================
// api/_lib/store.js  (ESM) – DFS Complaints Backend
// =======================================================
import { Redis } from '@upstash/redis';
import crypto from 'node:crypto';
import { AsyncLocalStorage } from 'node:async_hooks';
import { loadRepByEmail, loadRepById, repCustomers } from './repsStore.js';
import {
  hasDepartmentOverlap,
  normalizeDepartments,
  normalizeEvaluationText,
  normalizeInternalEvaluationCause,
  normalizeEvaluationTranslations,
  normalizeReportLinksMap,
} from './departments.js';

/* =========================================================
   KV / Redis – ENV robust erkennen (Upstash & Vercel KV)
   ========================================================= */
const REDIS_URL =
  process.env.UPSTASH_REDIS_REST_KV_REST_API_URL ||
  process.env.UPSTASH_REDIS_REST_URL ||
  process.env.KV_REST_API_URL ||
  process.env.REDIS_URL ||
  null;

const REDIS_TOKEN =
  process.env.UPSTASH_REDIS_REST_KV_REST_API_TOKEN ||
  process.env.UPSTASH_REDIS_REST_TOKEN ||
  process.env.KV_REST_API_TOKEN ||
  process.env.REDIS_TOKEN ||
  null;

const REDIS_TIMEOUT_MS = Math.max(0, Number(process.env.REDIS_TIMEOUT_MS || 2500));
const AUDIT_REDIS_DEBUG_LOG_ENABLED =
  String(process.env.AUDIT_REDIS_DEBUG_LOG || 'true').toLowerCase() !== 'false';

const auditRedisDebugContext = new AsyncLocalStorage();

export function runWithAuditRedisContext(ctx = {}, fn = () => {}) {
  if (typeof fn !== 'function') return fn;
  return auditRedisDebugContext.run({ ...ctx }, fn);
}

function getAuditRedisDebugContext() {
  return auditRedisDebugContext.getStore() || {};
}

let _redis = null;
let _redisOverride = null;
export function __setRedisClientForTests(client = null) {
  _redisOverride = client;
  _redis = client;
}
function getRedis() {
  if (_redisOverride) return _redisOverride;
  if (_redis) return _redis;
  if (!REDIS_URL || !REDIS_TOKEN) return null;
  _redis = new Redis({ url: REDIS_URL, token: REDIS_TOKEN });
  return _redis;
}

async function withRedisTimeout(promise, label = 'redis op') {
  if (!REDIS_TIMEOUT_MS) return await promise;
  return await Promise.race([
    promise,
    new Promise((_, reject) => {
      setTimeout(() => {
        const err = new Error(`${label} timed out after ${REDIS_TIMEOUT_MS}ms`);
        err.code = 'REDIS_TIMEOUT';
        reject(err);
      }, REDIS_TIMEOUT_MS);
    }),
  ]);
}

const P = 'dfs:';
const KEY_REP_PUSH = (repId) => `${P}rep:${repId}:pushTokens`;
const KEY_PORTAL_USER = (email) => `${P}portal:user:${email}`;
const KEY_PORTAL_USERS = `${P}portal:users`;
const KEY_PORTAL_ADMIN_UI = `${P}portal:admin:ui`;
const KEY_PORTAL_NEWS = `${P}portal:news`;
const KEY_DOWNLOAD_CATEGORIES = `${P}downloads:categories`;
const KEY_CAPA_COUNTER = (year) => `${P}capa:counter:${year}`;
const KEY_CHANGE_COUNTER = (year) => `${P}change:counter:${year}`;

// ===== In-Memory Fallback (Preview / Dev) =====
const mem = {
  users: new Map(),
  portalUsers: new Map(),
  pending: new Map(),
  complaints: new Map(),
  capaReports: new Map(),
  changeRecords: new Map(),
  fmeas: new Map(),
  auditors: new Map(),
  auditorIndex: new Set(),
  auditPrograms: new Map(),
  audits: new Map(),
  auditFindings: new Map(),
  auditActions: new Map(),
  auditAnnualReports: new Map(),
  counters: { ticket: 1, capa: {}, change: {} },
  catalogConfig: {},
  repPushTokens: new Map(),
  adminPushTokens: [],
  gateCodes: new Map(),
  customerNews: [],
  portalNews: [],
  faqCategories: [],
  faqItems: [],
  downloads: [],
  downloadsCacheVersion: 0,
  downloadCategories: null,
  repDownloadSeen: new Map(),
  adminUiConfig: null,
  auditCounters: {},
  suppliers: new Map(),
  supplierIndex: new Set(),
  supplierPerformance: new Map(),
  supplierPerformanceIndex: new Set(),
  supplierEvaluations: new Map(),
  supplierEvaluationIndex: new Set(),
  supplierEscalations: new Map(),
  supplierEscalationIndex: new Set(),
  supplierEvalConfig: null,
  supplierLookups: null,
};

export function normalizeTilePermission(value) {
  const lc = (value ?? '').toString().trim().toLowerCase();
  if (lc === 'write') return 'write';
  if (lc === 'read') return 'read';
  if (lc === 'none' || lc === 'hidden' || lc === 'hide') return 'none';
  return null;
}

export function sanitizeTilePermissions(raw) {
  const out = {};
  if (!raw || typeof raw !== 'object') return out;
  for (const [tile, perm] of Object.entries(raw)) {
    const tileId = (tile ?? '').toString().trim();
    if (!tileId) continue;
    const normalized = normalizeTilePermission(perm);
    if (normalized) out[tileId] = normalized;
  }
  return out;
}

const DEFAULT_DOWNLOAD_CATEGORIES = [
  'Sicherheitsdatenblätter',
  'Gebrauchsanweisungen',
  'Aufbereitungsanweisungen',
  'Kataloge',
  'Produktflyer',
  'Registrierungsdokumente',
  'sonstige Dokumente',
];

export const SUPPORTED_LANGS = new Set([
  'bg', // Bulgarian
  'cs', // Czech
  'da', // Danish
  'de', // German
  'el', // Greek
  'en', // English
  'es', // Spanish
  'et', // Estonian
  'fi', // Finnish
  'fr', // French
  'hu', // Hungarian
  'id', // Indonesian
  'it', // Italian
  'ja', // Japanese
  'ko', // Korean
  'lt', // Lithuanian
  'lv', // Latvian
  'nb', // Norwegian (Bokmål)
  'nl', // Dutch
  'pl', // Polish
  'pt-pt', // Portuguese (European)
  'pt-br', // Portuguese (Brazilian)
  'ro', // Romanian
  'ru', // Russian
  'sk', // Slovak
  'sl', // Slovenian
  'sv', // Swedish
  'tr', // Turkish
  'uk', // Ukrainian
  'zh', // Chinese (simplified)
]);
const LANG_ALIASES = {
  german: 'de',
  deutsch: 'de',
  englisch: 'en',
  english: 'en',
  french: 'fr',
  français: 'fr',
  francais: 'fr',
  italienisch: 'it',
  italian: 'it',
  spanish: 'es',
  spanisch: 'es',
  español: 'es',
  espanol: 'es',
  dutch: 'nl',
  niederländisch: 'nl',
  niederlaendisch: 'nl',
  portuguese: 'pt-pt',
  português: 'pt-pt',
  portugiesisch: 'pt-pt',
  'pt': 'pt-pt',
  'pt-br': 'pt-br',
  brasilianisch: 'pt-br',
  brazilian: 'pt-br',
  brazilianportuguese: 'pt-br',
  chinese: 'zh',
  chinesisch: 'zh',
  'zh-cn': 'zh',
  'zh-hans': 'zh',
  'zh-hant': 'zh',
  japanese: 'ja',
  japanisch: 'ja',
  korean: 'ko',
  koreanisch: 'ko',
  russian: 'ru',
  russisch: 'ru',
  polish: 'pl',
  polnisch: 'pl',
  swedish: 'sv',
  schwedisch: 'sv',
  norwegian: 'nb',
  norwegisch: 'nb',
  danish: 'da',
  dänisch: 'da',
  daenisch: 'da',
  finnish: 'fi',
  finnisch: 'fi',
  greek: 'el',
  griechisch: 'el',
  turkish: 'tr',
  türkisch: 'tr',
  ukraine: 'uk',
  ukrainian: 'uk',
  ukrainisch: 'uk',
  romanian: 'ro',
  rumänisch: 'ro',
  rumaenisch: 'ro',
  hungarian: 'hu',
  ungarisch: 'hu',
  czech: 'cs',
  tschechisch: 'cs',
  slovak: 'sk',
  slowakisch: 'sk',
  slovenian: 'sl',
  slowenisch: 'sl',
  bulgarian: 'bg',
  bulgarisch: 'bg',
  estonian: 'et',
  estnisch: 'et',
  lithuanian: 'lt',
  litauisch: 'lt',
  latvian: 'lv',
  lettisch: 'lv',
  indonesian: 'id',
  indonesisch: 'id',
  romanisch: 'ro',
};

export function normalizeLangValue(value) {
  const lc = String(value || '').trim().toLowerCase();
  if (!lc) return null;
  if (LANG_ALIASES[lc]) return LANG_ALIASES[lc];
  if (SUPPORTED_LANGS.has(lc)) return lc;
  const two = lc.split(/[-_]/)[0];
  if (SUPPORTED_LANGS.has(two)) return two;
  if (LANG_ALIASES[two]) return LANG_ALIASES[two];
  return null;
}

function normLang(x) {
  return normalizeLangValue(x) || 'de';
}

function _listifyPushTokens(list) {
  if (Array.isArray(list)) return list;
  if (list == null) return [];
  if (typeof list === 'string') return [list];
  if (typeof list === 'object') {
    const hasDirectToken =
      Object.prototype.hasOwnProperty.call(list, 'token') ||
      Object.prototype.hasOwnProperty.call(list, 'deviceToken') ||
      Object.prototype.hasOwnProperty.call(list, 'id');
    if (hasDirectToken) return [list];
    return Object.values(list);
  }
  return [];
}

function _rawPushTokenCount(list) {
  if (Array.isArray(list)) return list.length;
  if (list == null) return 0;
  if (typeof list === 'string') return list.trim() ? 1 : 0;
  if (typeof list === 'object') {
    const hasDirectToken =
      Object.prototype.hasOwnProperty.call(list, 'token') ||
      Object.prototype.hasOwnProperty.call(list, 'deviceToken') ||
      Object.prototype.hasOwnProperty.call(list, 'id');
    if (hasDirectToken) return 1;
    return Object.keys(list).length;
  }
  return 0;
}

function _normalizeLocation(raw) {
  if (!raw || typeof raw !== 'object') return undefined;
  const latNum = Number(raw.lat);
  const lngNum = Number(raw.lng);
  const lat = Number.isFinite(latNum) ? latNum : undefined;
  const lng = Number.isFinite(lngNum) ? lngNum : undefined;
  const city = (raw.city || raw.town || raw.locality || '').toString().trim();
  const country = (raw.country || raw.countryCode || '').toString().trim();
  const label = (raw.label || raw.locationLabel || '').toString().trim();

  if (!lat && !lng && !city && !country && !label) return undefined;
  const out = {};
  if (lat !== undefined) out.lat = lat;
  if (lng !== undefined) out.lng = lng;
  if (city) out.city = city;
  if (country) out.country = country;
  if (label) out.label = label;
  return out;
}

function normalizePushTokens(list) {
  const out = [];
  const seen = new Set();
  const arr = _listifyPushTokens(list);
  for (const entry of arr) {
    const hasMeta = entry && typeof entry === 'object';
    const rawToken = hasMeta ? (entry.token ?? entry.deviceToken ?? entry.id) : entry;
    const token = (rawToken || '').toString().trim();
    if (!token || seen.has(token)) continue;
    seen.add(token);

    const createdRaw = hasMeta ? Number(entry.createdAt) : NaN;
    const createdAt = Number.isFinite(createdRaw) ? createdRaw : Date.now();
    const updatedRaw = hasMeta ? Number(entry.updatedAt) : NaN;
    const updatedAt = Number.isFinite(updatedRaw) ? updatedRaw : createdAt;
    const platform = hasMeta ? (entry.platform || '').toString().trim() : '';
    const locale = hasMeta ? (entry.locale || '').toString().trim() : '';
    const lang = normLang(hasMeta ? entry.lang || '' : '');
    const appVersion = hasMeta ? (entry.appVersion || '').toString().trim() : '';
    const appBuild = hasMeta ? (entry.appBuild || '').toString().trim() : '';
    const location = hasMeta ? _normalizeLocation(entry.location || {}) : undefined;

    out.push({
      token,
      platform: platform || undefined,
      lang,
      locale: locale || undefined,
      createdAt,
      updatedAt,
      ...(appVersion ? { appVersion } : {}),
      ...(appBuild ? { appBuild } : {}),
      ...(location ? { location } : {}),
    });
  }
  return out;
}

const KEY_ADMIN_PUSH = `${P}admin:pushTokens`;
const KEY_GATE = (email) => `${P}gate:${email}`;
const CATALOG_KEYS = ['lab_default', 'lab_esfr', 'dent_default', 'dent_esfr'];
const DEFAULT_GATE_TTL_SECONDS = Math.max(
  0,
  Number(process.env.GATE_CODE_TTL || 60 * 60 * 24 * 7)
);
const KEY_CUSTOMER_NEWS = `${P}news:customer`;
const NEWS_CATEGORY_CODES = [
  'catalogs',
  'technical',
  'regulatory',
  'product',
  'shortage',
  'app',
  'document',
  'qmh',
  'general',
];
export const CUSTOMER_NEWS_CATEGORY_CODES = [...NEWS_CATEGORY_CODES];
const FAQ_AUDIENCE_CODES = ['customer', 'rep', 'both'];
const KEY_FAQ_CATEGORIES = `${P}faq:categories`;
const KEY_FAQ_ITEMS = `${P}faq:items`;
const KEY_DOWNLOADS = `${P}downloads`;
const KEY_REP_DOWNLOAD_SEEN = (repId) => `${P}rep:${repId}:downloads:seen`;
const KEY_GLOBAL_DOWNLOAD_CATEGORIES = '__DFS_DOWNLOAD_CATEGORIES__';
const PUSH_TOKEN_FRESH_MS = Math.max(
  60 * 60 * 1000,
  Number(process.env.PUSH_TOKEN_FRESH_MS || 1000 * 60 * 60 * 24 * 45)
);

function _normalizeCatalogConfig(input) {
  const src = input && typeof input === 'object' ? input : {};
  const out = {};
  for (const key of CATALOG_KEYS) {
    const raw = src[key];
    if (raw == null) continue;
    const val = typeof raw === 'string' ? raw.trim() : String(raw ?? '').trim();
    if (val) out[key] = val;
  }
  return out;
}

// ===== Helper (Redis IO) =====
async function rget(k, rclient = null) {
  try {
    const r = rclient || getRedis();
    if (!r) return null;
    const raw = await withRedisTimeout(r.get(k), `KV GET ${k}`);
    if (typeof raw === 'string') {
      try {
        return JSON.parse(raw);
      } catch (_) {
        return raw;
      }
    }
    return raw;
  } catch (e) {
    console.error('KV GET', k, e);
    return null;
  }
}
const READ_ONLY_METHODS = new Set(['GET', 'HEAD', 'OPTIONS']);

function enforceRedisWritePolicy({ operation, key }) {
  const ctx = getAuditRedisDebugContext();
  const method = (ctx.method || '').toString().toUpperCase();
  if (!method || !READ_ONLY_METHODS.has(method)) return;
  const err = new Error(`Redis write blocked for read-only method ${method}`);
  console.error('[redis-write-guard]', {
    method,
    route: ctx.route,
    auditId: ctx.auditId,
    key,
    stack: (err.stack || '').split('\n').slice(1, 6),
  });
  throw err;
}

async function rset(k, v, rclient = null) {
  try {
    const r = rclient || getRedis();
    if (!r) return null;
    enforceRedisWritePolicy({ operation: 'set', key: k });
    const payload = typeof v === 'string' ? v : JSON.stringify(v);
    logAuditRedisWrite({ operation: 'set', key: k, payload });
    return await withRedisTimeout(r.set(k, payload), `KV SET ${k}`);
  } catch (e) {
    console.error('KV SET', k, e);
    return null;
  }
}
async function rdel(k, rclient = null) {
  try {
    const r = rclient || getRedis();
    if (!r) return null;
    if (typeof r.del !== 'function') return null;
    enforceRedisWritePolicy({ operation: 'del', key: k });
    logAuditRedisWrite({ operation: 'del', key: k });
    return await withRedisTimeout(r.del(k), `KV DEL ${k}`);
  } catch (e) {
    console.error('KV DEL', k, e);
    return null;
  }
}

async function rsadd(k, member, rclient = null) {
  try {
    const r = rclient || getRedis();
    if (!r) return null;
    if (typeof r.sadd !== 'function') return null;
    enforceRedisWritePolicy({ operation: 'sadd', key: k });
    logAuditRedisWrite({ operation: 'sadd', key: k });
    const members = Array.isArray(member) ? member : [member];
    if (members.length === 0) return 0;
    return await withRedisTimeout(r.sadd(k, ...members), `KV SADD ${k}`);
  } catch (e) {
    console.error('KV SADD', k, e);
    return null;
  }
}

async function rsrem(k, member, rclient = null) {
  try {
    const r = rclient || getRedis();
    if (!r) return null;
    if (typeof r.srem !== 'function') return null;
    enforceRedisWritePolicy({ operation: 'srem', key: k });
    logAuditRedisWrite({ operation: 'srem', key: k });
    const members = Array.isArray(member) ? member : [member];
    if (members.length === 0) return 0;
    return await withRedisTimeout(r.srem(k, ...members), `KV SREM ${k}`);
  } catch (e) {
    console.error('KV SREM', k, e);
    return null;
  }
}

async function rsmembers(k, rclient = null) {
  try {
    const r = rclient || getRedis();
    if (!r) return [];
    if (typeof r.smembers !== 'function') return [];
    return await withRedisTimeout(r.smembers(k), `KV SMEMBERS ${k}`);
  } catch (e) {
    console.error('KV SMEMBERS', k, e);
    return [];
  }
}

async function rincr(k, rclient = null) {
  try {
    const r = rclient || getRedis();
    if (!r) return null;
    enforceRedisWritePolicy({ operation: 'incr', key: k });
    logAuditRedisWrite({ operation: 'incr', key: k });
    return await withRedisTimeout(r.incr(k), `KV INCR ${k}`);
  } catch (e) {
    console.error('KV INCR', k, e);
    return null;
  }
}

function logAuditRedisWrite({ operation, key, payload }) {
  if (!AUDIT_REDIS_DEBUG_LOG_ENABLED) return;
  const keyStr = String(key || '');

  const ctx = getAuditRedisDebugContext();
  const stack = (new Error().stack || '')
    .split('\n')
    .slice(2, 7)
    .map((l) => l.trim());
  const auditIdMatch = keyStr.match(/audit:(?:[^:]+:)?([^:]+)/);

  console.warn('[audit-redis-write]', {
    operation,
    key: keyStr,
    method: ctx.method,
    route: ctx.route,
    auditId: ctx.auditId || auditIdMatch?.[1],
    stack,
    payloadType: typeof payload,
  });
}

// ===== Key-Scan kompatibel zu Upstash =====
async function rkeys(pattern, rclient = null) {
  const r = rclient || getRedis();
  if (!r) return [];
  if (typeof r.keys === 'function') {
    try { return await withRedisTimeout(r.keys(pattern), `KV KEYS ${pattern}`); } catch { /* continue */ }
  }
  if (typeof r.scan === 'function') {
    let cursor = 0, out = [];
    do {
      const res = await withRedisTimeout(
        r.scan(cursor, { match: pattern, count: 1000 }),
        `KV SCAN ${pattern}`
      );
      if (Array.isArray(res)) {
        cursor = Number(res[0]);
        out.push(...(res[1] || []));
      } else {
        cursor = Number(res.cursor || 0);
        out.push(...(res.members || res.keys || []));
      }
    } while (cursor !== 0);
    return out;
  }
  return [];
}

/* ============== Catalog Configuration ============== */
const CATALOG_KEY = `${P}catalogs:config`;

export async function catalogConfigGet() {
  const r = getAuditRedis();
  if (r) {
    const raw = await rget(CATALOG_KEY);
    if (raw && typeof raw === 'string') {
      try { return _normalizeCatalogConfig(JSON.parse(raw)); }
      catch { return _normalizeCatalogConfig({}); }
    }
    return _normalizeCatalogConfig(raw);
  }
  return _normalizeCatalogConfig(mem.catalogConfig);
}

export async function catalogConfigSet(updates = {}) {
  const next = { ...(await catalogConfigGet()) };

  for (const key of CATALOG_KEYS) {
    if (!Object.prototype.hasOwnProperty.call(updates, key)) continue;
    const raw = updates[key];
    const val = raw == null ? '' : (typeof raw === 'string' ? raw : String(raw));
    const trimmed = val.trim();
    if (trimmed) next[key] = trimmed;
    else delete next[key];
  }

  const r = getAuditRedis();
  if (r) {
    if (Object.keys(next).length === 0) await rdel(CATALOG_KEY); else await rset(CATALOG_KEY, next);
  }

  // Für In-Memory-Fallback immer aktualisieren (auch bei Redis, falls offline)
  mem.catalogConfig = { ...next };

  return next;
}

/* ============== Customer News (Infoscreen) ============== */
function _text(value, max = 400) {
  if (value === undefined || value === null) return '';
  let s = String(value);
  s = s.replace(/\r\n/g, '\n').trim();
  if (max > 0 && s.length > max) {
    s = `${s.slice(0, max - 1).trim()}…`;
  }
  return s;
}

function _normalizeCategoryName(name) {
  return _text(name, 160);
}

function _normalizeIntlMap(raw, maxLen = 400) {
  const out = {};
  if (raw && typeof raw === 'object') {
    for (const [key, value] of Object.entries(raw)) {
      const lang = normalizeLangValue(key);
      const txt = _text(value, maxLen);
      if (!lang || !txt) continue;
      out[lang] = txt;
    }
  }
  return out;
}

function _resolveIntlValue(map = {}, { preferred, fallback }) {
  if (preferred && map[preferred]) return map[preferred];
  if (preferred && preferred !== 'de' && map['de']) return map['de'];
  const first = Object.values(map).find((v) => v && v.trim());
  if (first) return first;
  if (fallback && fallback.trim()) return fallback.trim();
  return '';
}

function _safeUrl(value) {
  const raw = (value ?? '').toString().trim();
  if (!raw) return '';
  if (!/^https?:\/\//i.test(raw)) return '';
  return raw;
}

function _newsCategory(value) {
  const raw = (value ?? '').toString().trim().toLowerCase();
  if (NEWS_CATEGORY_CODES.includes(raw)) return raw;
  return 'general';
}

function _parseTs(value, fallback) {
  if (typeof value === 'number' && Number.isFinite(value)) return Number(value);
  if (typeof value === 'string' && value.trim()) {
    const n = Date.parse(value);
    if (!Number.isNaN(n)) return n;
  }
  return fallback;
}

function _normalizeAcknowledgements(raw) {
  if (!raw) return [];
  const list = Array.isArray(raw) ? raw : [raw];
  const safe = new Map();
  for (const entry of list) {
    if (!entry || typeof entry !== 'object') continue;
    const email = _text(entry.email ?? entry.mail ?? '', 180).toLowerCase();
    const name = _text(entry.name ?? entry.displayName ?? '', 240);
    const id = _text(entry.id ?? entry.userId ?? '', 120);
    const at = _parseTs(entry.at, Date.now()) ?? Date.now();
    if (!email && !name && !id) continue;
    const key = email || id || name || crypto.randomUUID();
    safe.set(key, {
      email: email || null,
      name: name || null,
      id: id || null,
      at,
    });
  }
  return Array.from(safe.values());
}

function _normalizeStoredNews(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const now = Date.now();
  const id = (raw.id ?? '').toString().trim();
  if (!id) return null;
  const title = _text(raw.title ?? '', 220);
  const summary = _text(raw.summary ?? raw.text ?? '', 4000);
  if (!title || !summary) return null;
  const createdAt = _parseTs(raw.createdAt, now) ?? now;
  const updatedAt = _parseTs(raw.updatedAt, createdAt) ?? createdAt;
  const publishedAt = _parseTs(raw.publishedAt, createdAt) ?? createdAt;
  const linkUrl = _safeUrl(raw.linkUrl ?? '');
  const linkLabel = _text(raw.linkLabel ?? '', 160);
  const audience = _normalizeNewsAudience(raw.audience ?? null);
  const acknowledgedBy = _normalizeAcknowledgements(raw.acknowledgedBy ?? raw.acknowledged ?? []);
  return {
    id,
    title,
    summary,
    category: _newsCategory(raw.category),
    linkLabel: linkLabel || null,
    linkUrl: linkUrl || null,
    pinned: Boolean(raw.pinned),
    draft: Boolean(raw.draft),
    createdAt,
    updatedAt,
    publishedAt,
    audience,
    acknowledgedBy,
    kind: raw.kind || 'news',
  };
}

function _sortNews(list = []) {
  return [...list].sort((a, b) => {
    if (a.pinned && !b.pinned) return -1;
    if (!a.pinned && b.pinned) return 1;
    return (b.publishedAt || 0) - (a.publishedAt || 0);
  });
}

async function _loadCustomerNews() {
  let list = null;
  const r = getAuditRedis();
  if (r) {
    const raw = await rget(KEY_CUSTOMER_NEWS);
    if (Array.isArray(raw)) {
      list = raw;
    } else if (typeof raw === 'string' && raw.trim()) {
      try { list = JSON.parse(raw); }
      catch { list = []; }
    } else if (raw && typeof raw === 'object') {
      list = raw.items || raw.list || [];
    }
  }
  if (!Array.isArray(list)) {
    list = Array.isArray(mem.customerNews) ? mem.customerNews : [];
  }
  const normalized = [];
  for (const entry of list) {
    const norm = _normalizeStoredNews(entry);
    if (norm) normalized.push(norm);
  }
  mem.customerNews = normalized.map((item) => ({ ...item }));
  return normalized;
}

async function _persistCustomerNews(list) {
  const safeList = _sortNews(list).map((item) => ({ ...item }));
  mem.customerNews = safeList.map((item) => ({ ...item }));
  const r = getAuditRedis();
  if (r) {
    await rset(KEY_CUSTOMER_NEWS, safeList);
  } else {
    global.__DFS_CUSTOMER_NEWS__ = safeList;
  }
  return safeList;
}

function _normalizeNewsPayload(input = {}, existing = null) {
  const now = Date.now();
  const base = existing ? { ...existing } : {};
  const title = _text(input.title ?? base.title ?? '', 220);
  const summary = _text(input.summary ?? base.summary ?? '', 4000);
  if (!title) throw new Error('title required');
  if (!summary) throw new Error('summary required');
  const published = _parseTs(input.publishedAt, base.publishedAt ?? now) ?? now;
  const created = base.createdAt ?? now;
  const linkLabel = _text(input.linkLabel ?? '', 160);
  const linkUrl = _safeUrl((input.linkUrl ?? base.linkUrl) ?? '');
  const audience = _normalizeNewsAudience(input.audience ?? base.audience ?? null);
  const acknowledgedBy = _normalizeAcknowledgements(input.acknowledgedBy ?? base.acknowledgedBy ?? base.acknowledged ?? []);
  return {
    id: (input.id ?? base.id ?? '').toString().trim() || `news_${now}_${Math.random().toString(36).slice(2, 8)}`,
    title,
    summary,
    category: _newsCategory(input.category ?? base.category ?? ''),
    linkLabel: linkLabel || null,
    linkUrl: linkUrl || null,
    pinned: input.pinned !== undefined ? Boolean(input.pinned) : Boolean(base.pinned),
    draft: input.draft !== undefined ? Boolean(input.draft) : Boolean(base.draft),
    createdAt: created,
    updatedAt: now,
    publishedAt: published,
    audience,
    acknowledgedBy,
  };
}

function _normalizeNewsAudience(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const emails = _uniqueStrings([...(raw.emails || []), raw.email, raw.to])
    .map((entry) => (entry ?? '').toString().trim().toLowerCase())
    .filter(Boolean);
  const departments = normalizeDepartments(raw.departments || raw.department || []);
  const roles = _uniqueStrings(raw.roles || raw.role || [])
    .map((entry) => (entry ?? '').toString().trim().toLowerCase())
    .filter(Boolean);
  if (!emails.length && !departments.length && !roles.length) return null;
  return { emails, departments, roles };
}

function _newsAudienceMatchesUser(audience, user) {
  if (!audience) return true;
  const email = (user?.email || '').toString().trim().toLowerCase();
  const departments = normalizeDepartments(
    user?.assignedDepartments || user?.departments || user?.department || []
  );
  const role = (user?.role || '').toString().trim().toLowerCase();

  const hasEmails = Array.isArray(audience.emails) && audience.emails.length > 0;
  const hasDepartments = Array.isArray(audience.departments) && audience.departments.length > 0;
  const hasRoles = Array.isArray(audience.roles) && audience.roles.length > 0;
  if (!hasEmails && !hasDepartments && !hasRoles) return true;

  if (hasEmails && email && audience.emails.some((target) => target === email)) return true;
  if (hasDepartments && departments.length && departments.some((dep) => audience.departments.includes(dep))) return true;
  if (hasRoles && role && audience.roles.includes(role)) return true;
  return false;
}

function _hasAcknowledged(entry, user) {
  if (!entry || !user) return false;
  const email = _nm(user.email);
  const userId = _nm(user.id || user.userId);
  const name = (user.displayName || user.name || '').toString().trim().toLowerCase();
  if (!email && !name && !userId) return false;
  return (entry.acknowledgedBy || []).some((ack) => {
    const ackEmail = (ack?.email || '').toString().trim().toLowerCase();
    const ackId = (ack?.id || '').toString().trim().toLowerCase();
    const ackName = (ack?.name || '').toString().trim().toLowerCase();
    if (userId && ackId && ackId === userId) return true;
    if (email && ackEmail && ackEmail === email) return true;
    if (name && ackName && ackName === name) return true;
    return false;
  });
}

export async function customerNewsList({ limit = 0, includeDrafts = false } = {}) {
  const list = await _loadCustomerNews();
  const now = Date.now();
  const filtered = includeDrafts
      ? list
      : list.filter((item) => !item.draft && (item.publishedAt ?? now) <= now);
  const sorted = _sortNews(filtered);
  if (limit && limit > 0) {
    const max = Math.min(Number(limit) || 0, 200);
    return sorted.slice(0, max || sorted.length);
  }
  return sorted;
}

export async function customerNewsUpsert(data) {
  const list = await _loadCustomerNews();
  const targetId = (data?.id ?? '').toString().trim();
  const idx = targetId ? list.findIndex((item) => item.id === targetId) : -1;
  const existing = idx >= 0 ? list[idx] : null;
  const normalized = _normalizeNewsPayload(data, existing);
  if (idx >= 0) {
    list[idx] = normalized;
  } else {
    list.push(normalized);
  }
  await _persistCustomerNews(list);
  return normalized;
}

export async function customerNewsDelete(id) {
  const list = await _loadCustomerNews();
  const target = (id ?? '').toString().trim();
  if (!target) return false;
  const next = list.filter((item) => item.id !== target);
  await _persistCustomerNews(next);
  return next.length !== list.length;
}

/* ============== Portal News (Mitarbeiter) ============== */

async function _loadPortalNews() {
  if (mem.portalNews?.length > 0) return mem.portalNews;
  const r = getRedis();
  let list = [];
  if (r) {
    const raw = await rget(KEY_PORTAL_NEWS);
    if (Array.isArray(raw)) {
      list = raw;
    } else if (raw && typeof raw === 'object') {
      list = raw.items || raw.list || [];
    }
  } else if (Array.isArray(global.__DFS_PORTAL_NEWS__)) {
    list = global.__DFS_PORTAL_NEWS__;
  }

  if (!Array.isArray(list)) list = mem.portalNews;

  const normalized = [];
  for (const entry of list || []) {
    const norm = _normalizeNewsPayload(entry);
    if (norm) normalized.push(norm);
  }
  mem.portalNews = normalized.map((item) => ({ ...item }));
  return normalized;
}

async function _persistPortalNews(list) {
  const safeList = _sortNews(list).map((item) => ({ ...item }));
  mem.portalNews = safeList.map((item) => ({ ...item }));
  const r = getRedis();
  if (r) {
    await rset(KEY_PORTAL_NEWS, safeList);
  } else {
    global.__DFS_PORTAL_NEWS__ = safeList;
  }
  return safeList;
}

export async function portalNewsList({ limit = 0, includeDrafts = false } = {}) {
  const list = await _loadPortalNews();
  const now = Date.now();
  const filtered = includeDrafts
    ? list
    : list.filter((item) => !item.draft && (item.publishedAt ?? now) <= now);
  const sorted = _sortNews(filtered);
  if (limit && limit > 0) {
    const max = Math.min(Number(limit) || 0, 200);
    return sorted.slice(0, max || sorted.length);
  }
  return sorted;
}

export async function portalNewsForUser(user, { limit = 0, includeDrafts = false } = {}) {
  const list = await portalNewsList({ includeDrafts });
  const targetedNews = list
    .filter((item) => _newsAudienceMatchesUser(item.audience, user))
    .map((item) => ({
      ...item,
      kind: item.kind || 'news',
      acknowledged: _hasAcknowledged(item, user),
    }));
  const personalEvents = await _personalEventsForUser(user);
  const combined = _sortNews([...targetedNews, ...personalEvents]);
  if (limit && limit > 0) {
    const max = Math.min(Number(limit) || 0, 200);
    return combined.slice(0, max || combined.length);
  }
  return combined;
}

function _namesFromUser(user = {}) {
  const names = new Set();
  const display = (user.displayName || user.name || '').toString().trim().toLowerCase();
  if (display) names.add(display);
  const email = (user.email || '').toString();
  if (email.includes('@')) names.add(email.split('@')[0].toLowerCase());
  return Array.from(names).filter(Boolean);
}

function _userDepartments(user = {}) {
  return normalizeDepartments(user?.assignedDepartments || user?.departments || user?.department || []);
}

function _complaintDepartments(complaint = {}) {
  return normalizeDepartments(complaint?.internalDepartments || complaint?.departments || complaint?.department || []);
}

function _hasDepartment(departments, target) {
  const wanted = (target || '').toString().trim().toLowerCase();
  if (!wanted) return false;
  return normalizeDepartments(departments).some((dep) => dep.toLowerCase() === wanted);
}

function _isComplaintOpen(complaint = {}) {
  const status = Number(complaint?.status || 0);
  const decision = (complaint?.decision || '').toString();
  if (decision === 'rejected') return false;
  return status !== Status.CLOSED;
}

function _complaintMatchesDepartment(complaint, departments) {
  if (!Array.isArray(departments) || departments.length === 0) return false;
  if (!_isComplaintOpen(complaint)) return false;
  const depList = _complaintDepartments(complaint);
  if (depList.length === 0) return false;
  return hasDepartmentOverlap(depList, departments);
}

function _complaintNeedsSalesFollowup(complaint, departments) {
  if (!_hasDepartment(departments, 'vertrieb')) return false;
  if (!_isComplaintOpen(complaint)) return false;
  const missingOrderOrInvoice = !((complaint?.orderNumber || '').toString().trim() || (complaint?.invoiceNumber || '').toString().trim());
  const missingAgentCode = !(complaint?.salesAgentCode || '').toString().trim();
  return missingOrderOrInvoice || missingAgentCode;
}

function _capaDepartment(capa = {}) {
  return (capa?.sections?.d1?.area || capa?.sections?.area || capa?.department || '').toString().trim();
}

function _isCapaOpen(capa = {}) {
  const status = (capa?.status || '').toString().trim().toLowerCase();
  return ['open', 'inprogress', 'in_progress', 'in progress'].includes(status);
}

function _capaMatchesDepartment(capa, departments) {
  if (!Array.isArray(departments) || departments.length === 0) return false;
  if (!_isCapaOpen(capa)) return false;
  const capaDept = _capaDepartment(capa);
  if (!capaDept) return false;
  return departments.some((dep) => dep.toLowerCase() === capaDept.toLowerCase());
}

function _complaintMatchesUser(c, user) {
  const email = _nm(user?.email);
  const names = _namesFromUser(user);
  if (!email && names.length === 0) return false;

  const complaintEmails = _emailsFromComplaint(c);
  if (email && complaintEmails.some((e) => e === email)) return true;

  const payload = c?.payload || {};
  const rawNames = [
    c?.contact,
    payload.name,
    payload.contact,
    payload.reporter,
    payload.reporterName,
    payload.customerName,
  ]
    .map((n) => (n ?? '').toString().trim().toLowerCase())
    .filter(Boolean);

  return names.some((n) => rawNames.some((val) => val.includes(n) || n.includes(val)));
}

function _statusLabel(status) {
  switch (status) {
    case Status.RECEIVED: return 'eingegangen';
    case Status.IN_PROGRESS: return 'in Bearbeitung';
    case Status.NEEDS_INFO: return 'Rückfrage';
    case Status.REWORK: return 'Nacharbeit';
    case Status.CLOSED: return 'geschlossen';
    default: return 'aktualisiert';
  }
}

function _eventFromComplaint(c, { reason = '' } = {}) {
  const title = `Reklamation ${c.ticket || ''}`.trim();
  const statusLabel = _statusLabel(c.status);
  const summary = [c.product, c.description, statusLabel, reason]
    .map((p) => (p || '').toString().trim())
    .filter(Boolean)
    .join(' · ');
  const safeTitle = title.length > 0 ? title : 'Reklamation';
  return {
    id: `complaint_${c.ticket || crypto.randomUUID()}`,
    title: safeTitle,
    summary: summary || 'Aktualisierung in deiner Reklamation',
    category: 'internal',
    linkLabel: 'Reklamation öffnen',
    linkUrl: c.ticket ? `/admin?ticket=${c.ticket}` : null,
    pinned: false,
    draft: false,
    createdAt: c.createdAt || Date.now(),
    updatedAt: c.updatedAt || Date.now(),
    publishedAt: c.updatedAt || c.createdAt || Date.now(),
    audience: null,
    kind: 'task',
    acknowledged: false,
    acknowledgedBy: [],
  };
}

function _eventFromCapa(capa, { reason = '' } = {}) {
  const summaryParts = [
    capa.title,
    capa.status ? `Status: ${capa.status}` : '',
    capa.capaNumber,
    reason,
  ].map((p) => (p || '').toString().trim()).filter(Boolean);
  return {
    id: `capa_${capa.id || capa.capaNumber || crypto.randomUUID()}`,
    title: capa.capaNumber ? `CAPA ${capa.capaNumber}` : 'CAPA Update',
    summary: summaryParts.join(' · ') || 'Neue CAPA-Aktivität',
    category: 'internal',
    linkLabel: 'CAPA öffnen',
    linkUrl: capa.id ? `/admin?capa=${capa.id}` : null,
    pinned: false,
    draft: false,
    createdAt: capa.createdAt || Date.now(),
    updatedAt: capa.updatedAt || Date.now(),
    publishedAt: capa.updatedAt || capa.createdAt || Date.now(),
    audience: null,
    kind: 'task',
    acknowledged: false,
    acknowledgedBy: [],
  };
}

async function _personalEventsForUser(user = {}) {
  const email = _nm(user?.email);
  const names = _namesFromUser(user);
  const departments = _userDepartments(user);
  if (!email && names.length === 0 && departments.length === 0) return [];

  const events = new Map();
  const addEvent = (entry) => {
    if (!entry?.id) return;
    if (!events.has(entry.id)) events.set(entry.id, entry);
  };

  try {
    const complaints = await complaintsAll();
    for (const c of complaints || []) {
      const isPersonal = _complaintMatchesUser(c, user);
      const deptMatch = _complaintMatchesDepartment(c, departments);
      const salesFollowup = _complaintNeedsSalesFollowup(c, departments);
      if (!isPersonal && !deptMatch && !salesFollowup) continue;

      const complaintDeps = _complaintDepartments(c);
      const overlappingDeps = complaintDeps.filter((dep) =>
        departments.some((userDep) => userDep.toLowerCase() === dep.toLowerCase())
      );
      const reasonParts = [];
      if (deptMatch && overlappingDeps.length > 0) {
        reasonParts.push(`Offene Aufgabe für ${overlappingDeps.join(', ')}`);
      } else if (deptMatch) {
        reasonParts.push('Offene Aufgabe für deine Abteilung');
      }
      if (salesFollowup) {
        reasonParts.push('Rechnungs-/Auftragsnummer oder Bearbeiterkürzel fehlen');
      }
      addEvent(_eventFromComplaint(c, { reason: reasonParts.join(' · ') }));
    }
  } catch (e) {
    console.warn('[portal feed] complaint aggregation failed', e?.message || e);
  }

  try {
    const capas = await capaAll();
    for (const capa of capas || []) {
      const responsible = (capa.responsibleUserId || '').toString().trim().toLowerCase();
      const responsibleName = responsible.includes('@') ? responsible.split('@')[0] : responsible;
      const matchesEmail = email && responsible === email;
      const matchesName = names.some((n) => responsibleName && (responsibleName.includes(n) || n.includes(responsibleName)));
      const deptMatch = _capaMatchesDepartment(capa, departments);
      if (!matchesEmail && !matchesName && !deptMatch) continue;

      const reason = deptMatch ? `Offene CAPA in ${_capaDepartment(capa) || 'deiner Abteilung'}` : '';
      addEvent(_eventFromCapa(capa, { reason }));
    }
  } catch (e) {
    console.warn('[portal feed] capa aggregation failed', e?.message || e);
  }

  return Array.from(events.values());
}

export async function portalNewsUpsert(data) {
  const list = await _loadPortalNews();
  const targetId = (data?.id ?? '').toString().trim();
  const idx = targetId ? list.findIndex((item) => item.id === targetId) : -1;
  const existing = idx >= 0 ? list[idx] : null;
  const normalized = _normalizeNewsPayload(data, existing);
  if (idx >= 0) {
    list[idx] = normalized;
  } else {
    list.push(normalized);
  }
  await _persistPortalNews(list);
  return normalized;
}

export async function portalNewsDelete(id) {
  const list = await _loadPortalNews();
  const target = (id ?? '').toString().trim();
  if (!target) return false;
  const next = list.filter((item) => item.id !== target);
  await _persistPortalNews(next);
  return next.length !== list.length;
}

export async function portalNewsAcknowledge(id, user) {
  const list = await _loadPortalNews();
  const targetId = (id ?? '').toString().trim();
  if (!targetId) throw new Error('id required');
  const idx = list.findIndex((item) => item.id === targetId);
  if (idx < 0) throw new Error('news entry not found');

  const existing = list[idx];
  const email = _nm(user?.email);
  const userId = _nm(user?.id || user?.userId);
  const name = _text(user?.displayName ?? user?.name ?? '', 240);
  const acknowledgedBy = _normalizeAcknowledgements([
    ...(existing.acknowledgedBy || []),
    { email, name, id: userId, at: Date.now() },
  ]);

  const updated = {
    ...existing,
    acknowledgedBy,
    updatedAt: Date.now(),
  };
  list[idx] = updated;
  await _persistPortalNews(list);
  return updated;
}

/* ============== FAQ / Knowledge Base ============== */
export { FAQ_AUDIENCE_CODES };

function _normalizeFaqAudience(value) {
  const raw = (value ?? '').toString().trim().toLowerCase();
  if (FAQ_AUDIENCE_CODES.includes(raw)) return raw;
  return 'both';
}

function _faqAudienceMatches(entryAudience, requested) {
  const target = _normalizeFaqAudience(requested);
  if (target === 'both') return true;
  const normalized = _normalizeFaqAudience(entryAudience);
  if (normalized === 'both') return true;
  return normalized === target;
}

function _orderValue(value, fallback = 0) {
  const num = Number(value);
  return Number.isFinite(num) ? num : fallback;
}

function _normalizeStoredFaqCategory(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const id = (raw.id ?? '').toString().trim();
  const preferredLang = normLang(raw.lang || raw.language || raw.primaryLang);
  const titleIntl = _normalizeIntlMap(raw.titleIntl, 200);
  const descriptionIntl = _normalizeIntlMap(raw.descriptionIntl, 2000);
  const fallbackTitle = _text(raw.title ?? raw.name ?? '', 200);
  const fallbackDescription = _text(raw.description ?? '', 2000);

  if (fallbackTitle && !titleIntl[preferredLang]) titleIntl[preferredLang] = fallbackTitle;
  if (fallbackDescription && !descriptionIntl[preferredLang]) descriptionIntl[preferredLang] = fallbackDescription;

  const title = _resolveIntlValue(titleIntl, { preferred: preferredLang, fallback: fallbackTitle });
  const description = _resolveIntlValue(descriptionIntl, { preferred: preferredLang, fallback: fallbackDescription });
  if (!id || !title) return null;
  return {
    id,
    title,
    titleIntl,
    description: description || null,
    descriptionIntl,
    order: _orderValue(raw.order, 0),
    active: raw.active === undefined ? true : Boolean(raw.active),
  };
}

function _normalizeStoredFaqEntry(raw, categories) {
  if (!raw || typeof raw !== 'object') return null;
  const id = (raw.id ?? '').toString().trim();
  const categoryId = (raw.categoryId ?? '').toString().trim();
  const preferredLang = normLang(raw.lang || raw.language);
  const question = _text(raw.question ?? '', 500);
  const answer = _text(raw.answer ?? '', 8000);
  const questionIntl = _normalizeIntlMap(raw.questionIntl, 500);
  const answerIntl = _normalizeIntlMap(raw.answerIntl, 8000);
  const resolvedQuestion = _resolveIntlValue(questionIntl, { preferred: preferredLang, fallback: question }) || question;
  const resolvedAnswer = _resolveIntlValue(answerIntl, { preferred: preferredLang, fallback: answer }) || answer;
  if (resolvedQuestion && !questionIntl[preferredLang]) questionIntl[preferredLang] = resolvedQuestion;
  if (resolvedAnswer && !answerIntl[preferredLang]) answerIntl[preferredLang] = resolvedAnswer;
  if (!id || !categoryId || !resolvedQuestion || !resolvedAnswer) return null;

  if (Array.isArray(categories) && categories.length > 0) {
    const exists = categories.some((cat) => cat.id === categoryId);
    if (!exists) return null;
  }

  const createdAt = _parseTs(raw.createdAt, Date.now());
  const updatedAt = _parseTs(raw.updatedAt, createdAt);

  return {
    id,
    categoryId,
    question: resolvedQuestion,
    answer: resolvedAnswer,
    questionIntl,
    answerIntl,
    audience: _normalizeFaqAudience(raw.audience),
    order: _orderValue(raw.order, 0),
    active: raw.active === undefined ? true : Boolean(raw.active),
    createdAt,
    updatedAt,
  };
}

function _normalizeFaqCategoryPayload(input = {}, existing = null) {
  const now = Date.now();
  const base = existing ? { ...existing } : {};

  const preferredLang = normLang(input.lang || input.language || input.primaryLang);
  const titleIntl = {
    ...(base.titleIntl || {}),
    ..._normalizeIntlMap(input.titleIntl, 200),
  };
  const descriptionIntl = {
    ...(base.descriptionIntl || {}),
    ..._normalizeIntlMap(input.descriptionIntl, 2000),
  };

  const fallbackTitle = _text(input.title ?? input.name ?? base.title ?? '', 200);
  const fallbackDescription = _text(input.description ?? base.description ?? '', 2000);

  if (fallbackTitle && !titleIntl[preferredLang]) titleIntl[preferredLang] = fallbackTitle;
  if (fallbackDescription && !descriptionIntl[preferredLang]) descriptionIntl[preferredLang] = fallbackDescription;

  const resolvedTitle = _resolveIntlValue(titleIntl, { preferred: preferredLang, fallback: fallbackTitle });
  const resolvedDescription = _resolveIntlValue(descriptionIntl, { preferred: preferredLang, fallback: fallbackDescription });

  if (!resolvedTitle) throw new Error('title required');

  return {
    id:
      (input.id ?? base.id ?? '').toString().trim() ||
      `faq_cat_${now}_${Math.random().toString(36).slice(2, 8)}`,
    title: resolvedTitle,
    titleIntl,
    description: resolvedDescription || null,
    descriptionIntl,
    order: _orderValue(input.order, base.order ?? 0),
    active: input.active !== undefined ? Boolean(input.active) : Boolean(base.active ?? true),
  };
}

function _normalizeFaqEntryPayload(input = {}, existing = null, categories = []) {
  const now = Date.now();
  const base = existing ? { ...existing } : {};
  const categoryId = (input.categoryId ?? base.categoryId ?? '').toString().trim();
  if (!categoryId) throw new Error('categoryId required');
  if (Array.isArray(categories) && categories.length > 0) {
    const exists = categories.some((cat) => cat.id === categoryId);
    if (!exists) throw new Error('category not found');
  }

  const preferredLang = normLang(input.lang || input.language || input.primaryLang);
  const questionIntl = {
    ...(base.questionIntl || {}),
    ..._normalizeIntlMap(input.questionIntl, 500),
  };
  const answerIntl = {
    ...(base.answerIntl || {}),
    ..._normalizeIntlMap(input.answerIntl, 8000),
  };

  const fallbackQuestion = _text(input.question ?? base.question ?? '', 500);
  const fallbackAnswer = _text(input.answer ?? base.answer ?? '', 8000);

  if (fallbackQuestion && !questionIntl[preferredLang]) {
    questionIntl[preferredLang] = fallbackQuestion;
  }
  if (fallbackAnswer && !answerIntl[preferredLang]) {
    answerIntl[preferredLang] = fallbackAnswer;
  }

  const normalizedQuestion = _resolveIntlValue(questionIntl, { preferred: preferredLang, fallback: fallbackQuestion });
  const normalizedAnswer = _resolveIntlValue(answerIntl, { preferred: preferredLang, fallback: fallbackAnswer });

  if (!normalizedQuestion || !normalizedAnswer) throw new Error('question and answer required');

  return {
    id:
      (input.id ?? base.id ?? '').toString().trim() ||
      `faq_${now}_${Math.random().toString(36).slice(2, 8)}`,
    categoryId,
    question: normalizedQuestion,
    answer: normalizedAnswer,
    questionIntl,
    answerIntl,
    audience: _normalizeFaqAudience(input.audience ?? base.audience ?? 'both'),
    order: _orderValue(input.order, base.order ?? 0),
    active: input.active !== undefined ? Boolean(input.active) : Boolean(base.active ?? true),
    createdAt: base.createdAt ?? now,
    updatedAt: now,
  };
}

function _sortFaqCategories(list = []) {
  return [...list].sort((a, b) => {
    if ((a.order ?? 0) !== (b.order ?? 0)) return (a.order ?? 0) - (b.order ?? 0);
    return (a.title || '').localeCompare(b.title || '');
  });
}

function _sortFaqItems(list = [], categories = []) {
  const orderMap = new Map(categories.map((cat, idx) => [cat.id, idx]));
  return [...list].sort((a, b) => {
    const catOrderA = orderMap.has(a.categoryId) ? orderMap.get(a.categoryId) : Number.MAX_SAFE_INTEGER;
    const catOrderB = orderMap.has(b.categoryId) ? orderMap.get(b.categoryId) : Number.MAX_SAFE_INTEGER;
    if (catOrderA !== catOrderB) return catOrderA - catOrderB;
    if ((a.order ?? 0) !== (b.order ?? 0)) return (a.order ?? 0) - (b.order ?? 0);
    return (a.updatedAt ?? a.createdAt ?? 0) - (b.updatedAt ?? b.createdAt ?? 0);
  });
}

async function _loadFaqCategories() {
  let list = null;
  const r = getRedis();
  if (r) {
    const raw = await rget(KEY_FAQ_CATEGORIES);
    if (Array.isArray(raw)) {
      list = raw;
    } else if (typeof raw === 'string' && raw.trim()) {
      try { list = JSON.parse(raw); }
      catch { list = []; }
    }
  }

  if (!Array.isArray(list)) {
    if (Array.isArray(global.__DFS_FAQ_CATEGORIES__)) list = global.__DFS_FAQ_CATEGORIES__;
    else list = Array.isArray(mem.faqCategories) ? mem.faqCategories : [];
  }

  const normalized = [];
  for (const entry of Array.isArray(list) ? list : []) {
    const norm = _normalizeStoredFaqCategory(entry);
    if (norm) normalized.push(norm);
  }

  mem.faqCategories = normalized.map((item) => ({ ...item }));
  return normalized;
}

async function _loadFaqItems(categories = null) {
  const cats = Array.isArray(categories) ? categories : await _loadFaqCategories();
  let list = null;
  const r = getRedis();
  if (r) {
    const raw = await rget(KEY_FAQ_ITEMS);
    if (Array.isArray(raw)) {
      list = raw;
    } else if (typeof raw === 'string' && raw.trim()) {
      try { list = JSON.parse(raw); }
      catch { list = []; }
    }
  }

  if (!Array.isArray(list)) {
    if (Array.isArray(global.__DFS_FAQ_ITEMS__)) list = global.__DFS_FAQ_ITEMS__;
    else list = Array.isArray(mem.faqItems) ? mem.faqItems : [];
  }

  const normalized = [];
  for (const entry of Array.isArray(list) ? list : []) {
    const norm = _normalizeStoredFaqEntry(entry, cats);
    if (norm) normalized.push(norm);
  }

  mem.faqItems = normalized.map((item) => ({ ...item }));
  return normalized;
}

async function _persistFaqCategories(list) {
  const safeList = _sortFaqCategories(list).map((item) => ({ ...item }));
  mem.faqCategories = safeList.map((item) => ({ ...item }));
  const r = getRedis();
  if (r) {
    await rset(KEY_FAQ_CATEGORIES, safeList);
  } else {
    global.__DFS_FAQ_CATEGORIES__ = safeList;
  }
  return safeList;
}

async function _persistFaqItems(list, categories = null) {
  const cats = Array.isArray(categories) ? categories : await _loadFaqCategories();
  const safeList = _sortFaqItems(list, cats).map((item) => ({ ...item }));
  mem.faqItems = safeList.map((item) => ({ ...item }));
  const r = getRedis();
  if (r) {
    await rset(KEY_FAQ_ITEMS, safeList);
  } else {
    global.__DFS_FAQ_ITEMS__ = safeList;
  }
  return safeList;
}

export async function faqList({ audience = 'customer', includeInactive = false } = {}) {
  const categories = await _loadFaqCategories();
  const items = await _loadFaqItems(categories);
  const requestedAudience = _normalizeFaqAudience(audience);

  const cats = includeInactive ? categories : categories.filter((cat) => cat.active);
  const allowedCatIds = new Set(cats.map((cat) => cat.id));

  const visibleItems = items.filter((item) => {
    if (!allowedCatIds.has(item.categoryId)) return false;
    if (!includeInactive && !item.active) return false;
    return _faqAudienceMatches(item.audience, requestedAudience);
  });

  const sortedCats = _sortFaqCategories(cats);
  const sortedItems = _sortFaqItems(visibleItems, sortedCats);
  return { categories: sortedCats, items: sortedItems };
}

export async function faqUpsertCategory(data) {
  const categories = await _loadFaqCategories();
  const targetId = (data?.id ?? '').toString().trim();
  const idx = targetId ? categories.findIndex((cat) => cat.id === targetId) : -1;
  const existing = idx >= 0 ? categories[idx] : null;
  const normalized = _normalizeFaqCategoryPayload(data, existing);
  if (idx >= 0) categories[idx] = normalized; else categories.push(normalized);
  await _persistFaqCategories(categories);
  return normalized;
}

export async function faqUpsertEntry(data) {
  const categories = await _loadFaqCategories();
  if (!Array.isArray(categories) || categories.length === 0) throw new Error('no categories configured');
  const items = await _loadFaqItems(categories);
  const targetId = (data?.id ?? '').toString().trim();
  const idx = targetId ? items.findIndex((item) => item.id === targetId) : -1;
  const existing = idx >= 0 ? items[idx] : null;
  const normalized = _normalizeFaqEntryPayload(data, existing, categories);
  if (idx >= 0) items[idx] = normalized; else items.push(normalized);
  await _persistFaqItems(items, categories);
  return normalized;
}

export async function faqDeleteCategory(id) {
  const target = (id ?? '').toString().trim();
  if (!target) return false;
  const categories = await _loadFaqCategories();
  const items = await _loadFaqItems(categories);
  const nextCategories = categories.filter((cat) => cat.id !== target);
  const nextItems = items.filter((item) => item.categoryId !== target);
  await Promise.all([
    _persistFaqCategories(nextCategories),
    _persistFaqItems(nextItems, nextCategories),
  ]);
  return nextCategories.length !== categories.length;
}

export async function faqDeleteEntry(id) {
  const target = (id ?? '').toString().trim();
  if (!target) return false;
  const categories = await _loadFaqCategories();
  const items = await _loadFaqItems(categories);
  const nextItems = items.filter((item) => item.id !== target);
  await _persistFaqItems(nextItems, categories);
  return nextItems.length !== items.length;
}

/* ============== Diagnose /api/diag/kv ============== */
export async function kvStatus() {
  const r = getRedis();
  if (!r) {
    return {
      ok: true, useRedis: false,
      reason: 'missing Upstash/Vercel KV ENV',
      needed: ['KV_REST_API_URL & KV_REST_API_TOKEN', 'oder', 'UPSTASH_REDIS_REST_URL & UPSTASH_REDIS_REST_TOKEN'],
    };
  }
  const t0 = Date.now();
  try {
    const pong = await r.ping();
    const pingMs = Date.now() - t0;
    const keys = await rkeys(`${P}*`);
    const counts = {
      users: keys.filter(k => k.startsWith(`${P}user:`)).length,
      pending: keys.filter(k => k.startsWith(`${P}pending:`)).length,
      complaints: keys.filter(k => k.startsWith(`${P}complaint:`)).length,
      total: keys.length,
    };
    return { ok: true, useRedis: true, ping: pong, pingMs, prefix: P, counts };
  } catch (e) {
    return { ok: false, useRedis: true, error: e?.message || String(e) };
  }
}

/* ============== Tickets ============== */
export async function nextTicket() {
  const r = getRedis();
  if (r) {
    const n = await r.incr(`${P}counter:ticket`);
    return `DFS_CP${String(n).padStart(6, '0')}`;
  }
  const n = mem.counters.ticket++;
  return `DFS_CP${String(n).padStart(6, '0')}`;
}

/* ============== Users ============== */
async function _loadUserRecord(email) {
  if (!email) return null;
  const key = `${P}user:${String(email).toLowerCase()}`;
  const r = getRedis();
  const raw = r ? await rget(key) : mem.users.get(String(email).toLowerCase()) ?? null;
  if (!raw || typeof raw !== 'object') return raw;
  const normalized = normalizePushTokens(raw.pushTokens);
  if (normalized.length > 0) raw.pushTokens = normalized; else delete raw.pushTokens;
  raw.lang = normLang(raw.lang || '');
  return raw;
}

export async function userByEmail(email) {
  const raw = await _loadUserRecord(email);
  if (!raw) return raw;

  if (hasPortalMarker(raw)) {
    try { await migratePortalLikeUser(raw); }
    catch (e) { console.error('[store] portal migration failed (userByEmail):', e); }
    return null;
  }

  if (!raw.type) raw.type = 'customer';
  if (!raw.kind) raw.kind = 'customer';
  return raw;
}

export async function userSave(u) {
  const email = String(u?.email || '').toLowerCase();
  if (!email) return false;
  const key = `${P}user:${email}`;
  const r = getRedis();
  const toSave = { ...u, email };
  if (!toSave.type) toSave.type = 'customer';
  if (!toSave.kind) toSave.kind = 'customer';
  if (Array.isArray(toSave.pushTokens)) {
    const normalized = normalizePushTokens(toSave.pushTokens);
    if (normalized.length > 0) toSave.pushTokens = normalized;
    else delete toSave.pushTokens;
  }
  if (!toSave.lang) toSave.lang = normLang(toSave.lang || '');
  if (r) await rset(key, toSave); else mem.users.set(email, toSave);
  return true;
}

export async function userDelete(email) {
  email = String(email || '').toLowerCase();
  if (!email) return true;

  const r = getRedis();

  if (r) {
    const repOfKey = `${P}repOf:${email}`;
    const legacyRepOfKey = `${P}repOf${email}`; // frühe Variante ohne Doppelpunkt

    try {
      const repIds = new Set();
      const addId = (value) => {
        const id = String(value ?? '').trim();
        if (id) repIds.add(id);
      };

      const repId = await r.get(repOfKey).catch(() => null);
      addId(repId);

      const legacyRepId = await r.get(legacyRepOfKey).catch(() => null);
      addId(legacyRepId);

      if (repIds.size === 0) {
        const all = await r.smembers(`${P}reps:all`).catch(() => []);
        if (Array.isArray(all)) {
          for (const id of all) {
            addId(id);
          }
        }
      }

      const cleanupJobs = [
        r.del(repOfKey).catch(() => {}),
        r.del(legacyRepOfKey).catch(() => {}),
      ];
      for (const id of repIds) {
        cleanupJobs.push(
          r.srem(`${P}rep:${id}:customers`, email).catch(() => {}),
        );
      }
      await Promise.all(cleanupJobs);
    } catch (e) {
      console.error('[store] userDelete rep cleanup failed:', e);
    }
  }

  const key = `${P}user:${email}`;
  if (r) await rdel(key); else mem.users.delete(email);
  return true;
}

export async function usersList() {
  const r = getRedis();
  const rawList = r
    ? await Promise.all((await rkeys(`${P}user:*`)).map(k => rget(k)))
    : Array.from(mem.users.values());

  const customers = [];
  for (const u of rawList) {
    if (!u || typeof u !== 'object') continue;
    if (hasPortalMarker(u)) {
      try { await migratePortalLikeUser(u); }
      catch (e) { console.error('[store] portal migration failed (usersList):', e); }
      continue;
    }

    if (!isCustomerUser(u)) continue;

    const normalized = normalizePushTokens(u.pushTokens);
    if (normalized.length > 0) u.pushTokens = normalized; else delete u.pushTokens;
    u.lang = normLang(u.lang || '');
    if (!u.type) u.type = 'customer';
    if (!u.kind) u.kind = 'customer';
    customers.push(u);
  }

  return customers;
}

/* ============== Portal Users (Mitarbeiter) ============== */
const hasPortalMarker = (u) => !!u && (
  Object.prototype.hasOwnProperty.call(u, 'portalStatus') ||
  Object.prototype.hasOwnProperty.call(u, 'role') ||
  ['portal', 'staff'].includes(String(u?.kind || u?.type || '').toLowerCase())
);

// Portal-Accounts sollen nie in der Kundendatenbank landen – diese Helper trennen strikt
// nach Kundendaten (users:customer) und Portal-Mitarbeitern (portalUsers:staff).
const isCustomerUser = (u) => {
  if (!u || typeof u !== 'object') return false;
  const type = String(u.type || u.kind || '').toLowerCase();
  if (type === 'portal' || type === 'staff') return false;
  if (hasPortalMarker(u)) return false;
  return true;
};

async function migratePortalLikeUser(u) {
  const email = String(u?.email || '').toLowerCase();
  if (!email) return null;
  const migrated = normalizePortalUser({ ...u, email });
  if (!migrated) return null;
  await portalUserSave(migrated);
  await userDelete(email);
  return migrated;
}

function normalizePortalUser(u) {
  if (!u || typeof u !== 'object') return null;
  const normalized = { ...u, kind: u.kind || 'portal', type: u.type || 'staff' };
  if (Array.isArray(normalized.pushTokens)) {
    const tokens = normalizePushTokens(normalized.pushTokens);
    if (tokens.length > 0) normalized.pushTokens = tokens; else delete normalized.pushTokens;
  }
  normalized.assignedDepartments = normalizeDepartments(normalized.assignedDepartments);
  normalized.lang = normLang(normalized.lang || '');
  normalized.isSales = normalized.isSales === true || normalized.isSales === 'true' || normalized.isSales === 1 || normalized.isSales === '1';
  normalized.isPRRC = normalized.isPRRC === true || normalized.isPRRC === 'true' || normalized.isPRRC === 1 || normalized.isPRRC === '1';
  const tilePermissions = sanitizeTilePermissions(normalized.tilePermissions);
  if (Object.keys(tilePermissions).length > 0) normalized.tilePermissions = tilePermissions; else delete normalized.tilePermissions;
  return normalized;
}

export async function portalUserByEmail(email) {
  if (!email) return null;
  const normalizedEmail = String(email).toLowerCase();
  const key = KEY_PORTAL_USER(normalizedEmail);
  const r = getRedis();
  const raw = r ? await rget(key) : mem.portalUsers.get(normalizedEmail) ?? null;
  if (raw && typeof raw === 'object') return normalizePortalUser(raw);

  // Legacy-Migration: Portal-User aus der Kundendatenbank holen und verschieben
  const legacy = await _loadUserRecord(normalizedEmail);
  if (hasPortalMarker(legacy)) {
    const migrated = await migratePortalLikeUser(legacy);
    if (migrated) return migrated;
  }

  return null;
}

export async function portalUserSave(u) {
  const email = String(u?.email || '').toLowerCase();
  if (!email) return false;
  const key = KEY_PORTAL_USER(email);
  const r = getRedis();
  const toSave = normalizePortalUser({ ...u, email });
  if (!toSave) return false;
  if (r) await rset(key, toSave); else mem.portalUsers.set(email, toSave);
  return true;
}

export async function portalUserDelete(email) {
  email = String(email || '').toLowerCase();
  if (!email) return true;
  const key = KEY_PORTAL_USER(email);
  const r = getRedis();
  if (r) await rdel(key); else mem.portalUsers.delete(email);
  return true;
}

export async function portalUsersList() {
  const r = getRedis();
  if (r) {
    const keys = await rkeys(`${P}portal:user:*`);
    const vals = await Promise.all(keys.map(k => rget(k)));
    return vals
      .filter(Boolean)
      .map(normalizePortalUser)
      .filter(Boolean);
  }
  return Array.from(mem.portalUsers.values())
    .map(normalizePortalUser)
    .filter(Boolean);
}

function _uniqueStrings(list) {
  const out = new Set();
  for (const entry of list || []) {
    const val = (entry ?? '').toString().trim();
    if (val) out.add(val);
  }
  return Array.from(out.values());
}

function sanitizeRoleTileVisibility(raw) {
  const out = {};
  if (!raw || typeof raw !== 'object') return out;
  for (const [role, tiles] of Object.entries(raw)) {
    const roleKey = (role ?? '').toString().trim();
    if (!roleKey) continue;
    if (Array.isArray(tiles)) {
      const filtered = _uniqueStrings(tiles);
      if (filtered.length) out[roleKey] = filtered;
    }
  }
  return out;
}

function sanitizeMenuLayout(raw) {
  if (!raw || typeof raw !== 'object') return null;

  const base = Array.isArray(raw) ? { sections: raw } : raw;
  const sections = [];
  for (const entry of Array.isArray(base.sections) ? base.sections : []) {
    if (!entry || typeof entry !== 'object') continue;
    const title = (entry.title ?? '').toString().trim();
    if (!title) continue;
    const subtitle = (entry.subtitle ?? '').toString().trim();
    const tiles = _uniqueStrings(Array.isArray(entry.tiles) ? entry.tiles : []);
    sections.push({ title, subtitle, tiles });
  }

  const rawScale = Number(base.tileScale);
  const tileScale = Number.isFinite(rawScale) ? Math.min(Math.max(rawScale, 0.5), 2) : 1;
  const archived = _uniqueStrings(Array.isArray(base.archived) ? base.archived : []);

  return {
    sections,
    tileScale,
    archived,
  };
}

function sanitizeNavOrder(raw) {
  if (!Array.isArray(raw)) return [];
  return _uniqueStrings(raw);
}

function sanitizePortalAdminUi(raw) {
  if (typeof raw === 'string') {
    try {
      raw = JSON.parse(raw.trim());
    } catch (_) {
      raw = {};
    }
  }

  const normalized = typeof raw === 'object' && raw ? raw : {};
  const result = {};

  const tiles = sanitizeRoleTileVisibility(normalized.roleTileVisibility);
  if (Object.keys(tiles).length > 0) result.roleTileVisibility = tiles;

  const layout = sanitizeMenuLayout(normalized.menuLayout ?? normalized.sections);
  if (layout) result.menuLayout = layout;

  const navOrder = sanitizeNavOrder(normalized.navOrder);
  if (navOrder.length > 0) result.navOrder = navOrder;

  return result;
}

export async function loadPortalAdminUi() {
  const r = getRedis();
  let stored = null;

  if (r) {
    stored = await rget(KEY_PORTAL_ADMIN_UI);
  }

  if (!stored && mem.adminUiConfig) return mem.adminUiConfig;

  const sanitized = sanitizePortalAdminUi(stored || {});
  mem.adminUiConfig = sanitized;
  return sanitized;
}

export async function savePortalAdminUi(config) {
  const current = await loadPortalAdminUi();
  const patch = sanitizePortalAdminUi(config || {});
  const next = { ...current };

  if (patch.roleTileVisibility) {
    next.roleTileVisibility = { ...(current.roleTileVisibility || {}), ...patch.roleTileVisibility };
  }

  if (patch.menuLayout) {
    next.menuLayout = patch.menuLayout;
  }

  if (patch.navOrder) {
    next.navOrder = patch.navOrder;
  }

  const r = getRedis();
  if (!r) throw new Error('portal admin UI config requires Redis/KV');

  const persisted = await rset(KEY_PORTAL_ADMIN_UI, next);
  if (!persisted) throw new Error('failed to persist portal admin UI config');
  mem.adminUiConfig = next;
  return next;
}

export async function pushTokensForEmail(email) {
  const user = await userByEmail(email);
  if (!user) return [];
  const normalized = normalizePushTokens(user.pushTokens);
  if (user.pushTokens && normalized.length !== user.pushTokens.length) {
    try { await userSave({ ...user, pushTokens: normalized }); }
    catch (e) { console.error('pushTokensForEmail/save', e); }
  }
  return normalized;
}

export async function pushTokenRegister(email, token, meta = {}) {
  const mail = String(email || '').trim().toLowerCase();
  const tok = (token || '').toString().trim();
  if (!mail || !tok) return null;
  const user = (await userByEmail(mail)) || { email: mail, createdAt: Date.now() };
  const tokens = normalizePushTokens(user.pushTokens);
  const now = Date.now();
  const platform = (meta?.platform || '').toString().trim();
  const locale = (meta?.locale || '').toString().trim();
  const lang = normLang(meta?.lang || user.lang || '');
  const appVersion = (meta?.appVersion ?? meta?.version ?? '').toString().trim();
  const appBuild = (meta?.appBuild ?? meta?.build ?? '').toString().trim();
  const location = _normalizeLocation(meta?.location || meta);

  const existingIdx = tokens.findIndex(t => t.token === tok);
  if (existingIdx >= 0) {
    const prevLoc = tokens[existingIdx].location;
    const nextLoc = location || prevLoc;
    tokens[existingIdx] = {
      ...tokens[existingIdx],
      platform: platform || tokens[existingIdx].platform,
      lang,
      locale: locale || tokens[existingIdx].locale,
      appVersion: appVersion || tokens[existingIdx].appVersion,
      appBuild: appBuild || tokens[existingIdx].appBuild,
      ...(nextLoc ? { location: nextLoc } : {}),
      updatedAt: now,
    };
  } else {
    tokens.push({
      token: tok,
      platform: platform || undefined,
      lang,
      locale: locale || undefined,
      createdAt: now,
      updatedAt: now,
      ...(appVersion ? { appVersion } : {}),
      ...(appBuild ? { appBuild } : {}),
      ...(location ? { location } : {}),
    });
  }

  user.pushTokens = tokens;
  user.lang = lang || user.lang;
  await userSave(user);
  return tokens[existingIdx >= 0 ? existingIdx : tokens.length - 1];
}

export async function pushTokenRemove(email, token) {
  const mail = String(email || '').trim().toLowerCase();
  const tok = (token || '').toString().trim();
  if (!mail || !tok) return false;
  const user = await userByEmail(mail);
  if (!user) return false;
  const tokens = normalizePushTokens(user.pushTokens).filter(t => t.token !== tok);
  if (tokens.length > 0) user.pushTokens = tokens; else delete user.pushTokens;
  await userSave(user);
  return true;
}

export async function recordUserLogin(email, meta = {}) {
  const mail = String(email || '').trim().toLowerCase();
  if (!mail) return null;
  const user = await userByEmail(mail);
  if (!user) return null;

  const now = Date.now();
  const appVersion = (meta?.appVersion ?? meta?.version ?? '').toString().trim();
  const appBuild = (meta?.appBuild ?? meta?.build ?? '').toString().trim();

  const updated = {
    ...user,
    lastLoginAt: now,
  };
  if (appVersion) updated.lastLoginAppVersion = appVersion;
  if (appBuild) updated.lastLoginAppBuild = appBuild;

  await userSave(updated);
  return updated;
}

export async function repPushTokens(repId) {
  const id = (repId || '').toString().trim();
  if (!id) return [];

  const key = KEY_REP_PUSH(id);
  const r = getRedis();
  if (r) {
    const raw = await rget(key);
    let list = null;
    if (Array.isArray(raw)) list = raw;
    else if (typeof raw === 'string' && raw.trim()) {
      try { list = JSON.parse(raw); }
      catch { list = []; }
    } else if (raw && typeof raw === 'object') {
      list = raw;
    }
    const normalized = normalizePushTokens(list);
    if (!Array.isArray(list) || normalized.length !== _rawPushTokenCount(list)) {
      try { await rset(key, normalized); }
      catch (e) { console.error('repPushTokens/normalize', e); }
    }
    return normalized;
  }
  const list = normalizePushTokens(mem.repPushTokens.get(id));
  mem.repPushTokens.set(id, list);
  return list;
}

export async function repPushTokenRegister(repId, token, meta = {}) {
  const id = (repId || '').toString().trim();
  const tok = (token || '').toString().trim();
  if (!id || !tok) return null;

  const now = Date.now();
  const platform = (meta?.platform || '').toString().trim();
  const locale = (meta?.locale || '').toString().trim();
  let lang = normLang(meta?.lang || '');
  const appVersion = (meta?.appVersion ?? meta?.version ?? '').toString().trim();
  const appBuild = (meta?.appBuild ?? meta?.build ?? '').toString().trim();
  const location = _normalizeLocation(meta?.location || meta);

  try {
    const rep = await loadRepById(id).catch(() => null);
    if (rep?.lang) lang = normLang(lang || rep.lang || '');
  } catch (e) {
    console.warn('[store] repPushTokenRegister loadRep failed', e?.message || e);
  }

  const existing = await repPushTokens(id);
  const idx = existing.findIndex(t => t.token === tok);
  if (idx >= 0) {
    const prevLoc = existing[idx].location;
    const nextLoc = location || prevLoc;
    existing[idx] = {
      ...existing[idx],
      platform: platform || existing[idx].platform,
      lang,
      locale: locale || existing[idx].locale,
      appVersion: appVersion || existing[idx].appVersion,
      appBuild: appBuild || existing[idx].appBuild,
      ...(nextLoc ? { location: nextLoc } : {}),
      updatedAt: now,
    };
  } else {
    existing.push({
      token: tok,
      platform: platform || undefined,
      lang,
      locale: locale || undefined,
      ...(appVersion ? { appVersion } : {}),
      ...(appBuild ? { appBuild } : {}),
      ...(location ? { location } : {}),
      createdAt: now,
      updatedAt: now,
    });
  }

  const r = getRedis();
  if (r) {
    try { await rset(KEY_REP_PUSH(id), existing); }
    catch (e) { console.error('repPushTokenRegister/save', e); }
  }

  mem.repPushTokens.set(id, existing);

  return existing[idx >= 0 ? idx : existing.length - 1];
}

export async function repPushTokenRemove(repId, token) {
  const id = (repId || '').toString().trim();
  const tok = (token || '').toString().trim();
  if (!id || !tok) return false;

  const list = (await repPushTokens(id)).filter(t => t.token !== tok);
  const r = getRedis();
  if (list.length > 0) {
    if (r) {
      try { await rset(KEY_REP_PUSH(id), list); }
      catch (e) { console.error('repPushTokenRemove/save', e); }
    }
    mem.repPushTokens.set(id, list);
  } else {
    if (r) {
      try { await rdel(KEY_REP_PUSH(id)); }
      catch (e) { console.error('repPushTokenRemove/del', e); }
    }
    mem.repPushTokens.delete(id);
  }
  return true;
}

export async function adminPushTokens() {
  const key = KEY_ADMIN_PUSH;
  const r = getRedis();
  if (r) {
    const raw = await rget(key);
    let list = null;
    if (Array.isArray(raw)) list = raw;
    else if (typeof raw === 'string' && raw.trim()) {
      try { list = JSON.parse(raw); }
      catch { list = []; }
    } else if (raw && typeof raw === 'object') {
      list = raw;
    }
    const normalized = normalizePushTokens(list);
    if (!Array.isArray(list) || normalized.length !== _rawPushTokenCount(list)) {
      try { await rset(key, normalized); }
      catch (e) { console.error('adminPushTokens/normalize', e); }
    }
    return normalized;
  }
  const normalized = normalizePushTokens(mem.adminPushTokens);
  mem.adminPushTokens = normalized;
  return normalized;
}

export async function adminPushTokenRegister(token, meta = {}) {
  const tok = (token || '').toString().trim();
  if (!tok) return null;
  const now = Date.now();
  const platform = (meta?.platform || '').toString().trim();
  const locale = (meta?.locale || '').toString().trim();
  const lang = normLang(meta?.lang || '');

  const list = await adminPushTokens();
  const idx = list.findIndex(t => t.token === tok);
  if (idx >= 0) {
    list[idx] = {
      ...list[idx],
      platform: platform || list[idx].platform,
      lang,
      locale: locale || list[idx].locale,
      updatedAt: now,
    };
  } else {
    list.push({
      token: tok,
      platform: platform || undefined,
      lang,
      locale: locale || undefined,
      createdAt: now,
      updatedAt: now,
    });
  }

  const r = getRedis();
  if (r) {
    try { await rset(KEY_ADMIN_PUSH, list); }
    catch (e) { console.error('adminPushTokenRegister/save', e); }
  }

  mem.adminPushTokens = list;

  return list[idx >= 0 ? idx : list.length - 1];
}

export async function adminPushTokenRemove(token) {
  const tok = (token || '').toString().trim();
  if (!tok) return false;
  const list = (await adminPushTokens()).filter(t => t.token !== tok);
  const r = getRedis();
  if (list.length > 0) {
    if (r) {
      try { await rset(KEY_ADMIN_PUSH, list); }
      catch (e) { console.error('adminPushTokenRemove/save', e); }
    }
    mem.adminPushTokens = list;
  } else {
    if (r) {
      try { await rdel(KEY_ADMIN_PUSH); }
      catch (e) { console.error('adminPushTokenRemove/del', e); }
    }
    mem.adminPushTokens = [];
  }
  return true;
}

/* ============== Pending Registrations ============== */
export async function pendingSave(e) {
  const mail = String(e?.email || '').toLowerCase();
  if (!mail) return false;
  const key = `${P}pending:${mail}`;
  const r = getRedis();
  if (r) await rset(key, e); else mem.pending.set(mail, e);
  return true;
}

export async function pendingGet(email) {
  email = String(email || '').toLowerCase();
  const key = `${P}pending:${email}`;
  const r = getRedis();
  if (r) return await rget(key);
  return mem.pending.get(email) ?? null;
}

export async function pendingDelete(email) {
  email = String(email || '').toLowerCase();
  const key = `${P}pending:${email}`;
  const r = getRedis();
  if (r) await rdel(key); else mem.pending.delete(email);
  return true;
}

export async function pendingList() {
  const r = getRedis();
  if (r) {
    const keys = await rkeys(`${P}pending:*`);
    const vals = await Promise.all(keys.map(k => rget(k)));
    return vals.filter(Boolean);
  }
  return Array.from(mem.pending.values());
}

/* ============== Complaints Core ============== */

export const Status = {
  RECEIVED: 1,
  IN_PROGRESS: 2,
  NEEDS_INFO: 3,
  REWORK: 4,
  CLOSED: 5,
};

const PII_EMAIL_KEYS = new Set([
  'email', 'customeremail', 'customer_email', 'contactemail', 'contact_email',
  'useremail', 'user_email', 'customer_mail', 'customermail',
].map(key => key.toLowerCase()));

const PII_EMPTY_KEYS = new Set([
  'company', 'contact', 'contactperson', 'contact_person', 'contactname', 'contact_name',
  'customername', 'customer_name', 'customercontact', 'customer_contact',
  'phone', 'customerphone', 'customer_phone', 'contactphone', 'contact_phone', 'userphone', 'user_phone',
  'street', 'street1', 'street2', 'address', 'address1', 'address2',
  'customerstreet', 'customer_street', 'customeraddress', 'customer_address',
  'zip', 'zipcode', 'postalcode', 'postal_code', 'customerzip', 'customer_zip',
  'city', 'customercity', 'customer_city', 'country',
  'firstname', 'first_name', 'lastname', 'last_name',
  'customerfirstname', 'customer_firstname', 'customerlastname', 'customer_lastname',
  'customernumber', 'customer_no', 'customerno', 'customerid', 'customer_id',
].map(key => key.toLowerCase()));

function _placeholderFromEmail(email) {
  const base = (email || '').toString().replace(/[^a-z0-9]/gi, '').slice(-6) || 'user';
  const rnd = Math.floor(Math.random() * 1e6).toString(36);
  return `deleted-user-${base}-${rnd}`.toLowerCase();
}

function _scrubValue(value, placeholderEmail) {
  if (value == null) return value;
  if (Array.isArray(value)) return value.map((v) => _scrubValue(v, placeholderEmail));
  if (typeof value !== 'object') return value;

  const out = { ...value };
  for (const [key, val] of Object.entries(out)) {
    const lower = key.toLowerCase();
    if (PII_EMAIL_KEYS.has(lower)) {
      out[key] = placeholderEmail;
      continue;
    }
    if (PII_EMPTY_KEYS.has(lower)) {
      out[key] = '';
      continue;
    }
    out[key] = _scrubValue(val, placeholderEmail);
  }
  return out;
}

function normalizeReportLinkFallback(reportLinks = {}, fallback) {
  const normalized = normalizeReportLinksMap(reportLinks);
  if (fallback && !normalized.de && !normalized.en) {
    const url = (fallback ?? '').toString().trim();
    if (url && (/^https?:\/\//i.test(url) || url.startsWith('data:'))) {
      normalized.en = url;
    }
  }
  return normalized;
}

function normalizeComplaintRecord(c = {}) {
  const normalized = { ...c };
  normalized.internalDepartments = normalizeDepartments(c.internalDepartments);
  const evalText = normalizeEvaluationText(c.internalEvaluationText_de);
  normalized.internalEvaluationText_de = evalText;
  normalized.internalEvaluationCause = normalizeInternalEvaluationCause(c.internalEvaluationCause);
  const translations = normalizeEvaluationTranslations(c.internalEvaluationTranslations);
  if (Object.keys(translations).length > 0) normalized.internalEvaluationTranslations = translations; else delete normalized.internalEvaluationTranslations;
  normalized.internalEvaluationNewForAdmin = c.internalEvaluationNewForAdmin ? true : false;

  const qmSummary = normalizeEvaluationText(c.qmCustomerSummary);
  if (qmSummary) normalized.qmCustomerSummary = qmSummary; else delete normalized.qmCustomerSummary;
  const qmTranslations = normalizeEvaluationTranslations(c.qmCustomerSummaryTranslations);
  if (Object.keys(qmTranslations).length > 0) normalized.qmCustomerSummaryTranslations = qmTranslations; else delete normalized.qmCustomerSummaryTranslations;

  const qmMeasures = normalizeEvaluationText(c.qmMeasures);
  if (qmMeasures) normalized.qmMeasures = qmMeasures; else delete normalized.qmMeasures;
  const qmMeasuresTranslations = normalizeEvaluationTranslations(c.qmMeasuresTranslations);
  if (Object.keys(qmMeasuresTranslations).length > 0) normalized.qmMeasuresTranslations = qmMeasuresTranslations; else delete normalized.qmMeasuresTranslations;

  const internalReportLinks = normalizeReportLinksMap(c.internalReportLinks);
  if (Object.keys(internalReportLinks).length > 0) normalized.internalReportLinks = internalReportLinks; else delete normalized.internalReportLinks;

  const mergedReportLinks = normalizeReportLinksMap(c.reportLinks);
  const externalReportLinks = normalizeReportLinkFallback(
    c.externalReportLinks || mergedReportLinks,
    c.reportLink,
  );
  if (Object.keys(externalReportLinks).length > 0) normalized.externalReportLinks = externalReportLinks; else delete normalized.externalReportLinks;
  if (Object.keys(mergedReportLinks).length > 0) normalized.reportLinks = mergedReportLinks; else delete normalized.reportLinks;
  if (!normalized.reportLink) {
    normalized.reportLink = externalReportLinks.de || externalReportLinks.en || Object.values(externalReportLinks)[0];
  }
  const rawGoodwill = c.isGoodwill ?? c.goodwill ?? c.isKulanz;
  normalized.isGoodwill = rawGoodwill === true || rawGoodwill === 'true' || rawGoodwill === 1 || rawGoodwill === '1';

  const trim = (v) => {
    const s = (v ?? '').toString().trim();
    return s.length > 0 ? s : null;
  };
  const parseDate = (v) => {
    const n = Number(v);
    if (Number.isFinite(n) && n > 0) return n;
    const s = (v ?? '').toString().trim();
    const parsed = Date.parse(s);
    return Number.isFinite(parsed) ? parsed : null;
  };

  normalized.orderNumber = trim(c.orderNumber);
  normalized.invoiceNumber = trim(c.invoiceNumber);
  normalized.salesAgentCode = trim(c.salesAgentCode);
  const prrcClass = trim(c.prrcClassification);
  if (prrcClass) normalized.prrcClassification = prrcClass; else delete normalized.prrcClassification;
  const prrcComment = trim(c.prrcComment);
  if (prrcComment) normalized.prrcComment = prrcComment; else delete normalized.prrcComment;
  const prrcUserId = trim(c.prrcUserId);
  if (prrcUserId) normalized.prrcUserId = prrcUserId; else delete normalized.prrcUserId;
  const prrcTs = parseDate(c.prrcTimestamp);
  if (prrcTs) normalized.prrcTimestamp = prrcTs; else delete normalized.prrcTimestamp;
  const boolVal = (v) => v === true || v === 'true' || v === 1 || v === '1';
  const prrcClassUpper = (prrcClass ?? '').toString().trim().toUpperCase();
  const incidentClass = ['B', 'C', 'D'].includes(prrcClassUpper);
  const hasClassification = (prrcClass ?? '').toString().trim().isNotEmpty;
  const potentiallyReportable = incidentClass || (!hasClassification && boolVal(c.isPotentiallyReportable));
  if (potentiallyReportable) normalized.isPotentiallyReportable = true; else delete normalized.isPotentiallyReportable;
  const reportCheck = boolVal(c.prrcReportCheck);
  if (potentiallyReportable && reportCheck) normalized.prrcReportCheck = true; else delete normalized.prrcReportCheck;
  const reportCheckComment = trim(c.prrcReportCheckComment);
  if (potentiallyReportable && reportCheckComment) normalized.prrcReportCheckComment = reportCheckComment; else delete normalized.prrcReportCheckComment;
  const reportableFlag = potentiallyReportable && boolVal(c.prrcReportableCase);
  const reportableAt = parseDate(c.prrcReportableAt);
  if (reportableFlag) {
    normalized.prrcReportableCase = true;
    normalized.prrcReportableAt = reportableAt || Date.now();
  } else {
    delete normalized.prrcReportableCase;
    delete normalized.prrcReportableAt;
  }
  normalized.salesCompleted = c.salesCompleted === true || c.salesCompleted === 'true' || c.salesCompleted === 1 || c.salesCompleted === '1';
  const completedAt = parseDate(c.salesCompletedAt);
  if (completedAt) normalized.salesCompletedAt = completedAt; else delete normalized.salesCompletedAt;
  const completedBy = trim(c.salesCompletedBy);
  if (completedBy) normalized.salesCompletedBy = completedBy; else delete normalized.salesCompletedBy;

  // Verknüpfte FMEA-Risiko-Nummern (Mehrfachwerte zulassen)
  const linked = Array.isArray(c.fmeaRiskNumbers)
    ? c.fmeaRiskNumbers.map(v => (v ?? '').toString().trim()).filter(Boolean)
    : [];
  if (linked.length > 0) normalized.fmeaRiskNumbers = Array.from(new Set(linked)); else delete normalized.fmeaRiskNumbers;
  return normalized;
}

export async function complaintSave(c) {
  if (!c?.ticket) c.ticket = await nextTicket();
  const normalized = normalizeComplaintRecord(c);
  const key = `${P}complaint:${normalized.ticket}`;
  const r = getRedis();
  if (r) await rset(key, normalized); else mem.complaints.set(normalized.ticket, normalized);
  return normalized;
}

export async function complaintDelete(ticket) {
  if (!ticket) return false;
  const key = `${P}complaint:${ticket}`;
  const r = getRedis();
  if (r) await rdel(key); else mem.complaints.delete(ticket);
  return true;
}

export async function complaintGet(ticket) {
  const key = `${P}complaint:${ticket}`;
  const r = getRedis();
  if (r) return await rget(key);
  return mem.complaints.get(ticket) ?? null;
}

export async function complaintUpdate(ticket, patch) {
  const cur = await complaintGet(ticket);
  if (!cur) return null;
  const updated = { ...cur, ...patch, updatedAt: Date.now() };
  const normalized = normalizeComplaintRecord(updated);
  await complaintSave(normalized);
  return normalized;
}

/* ============== Mail-Normalisierung ============== */
function _nm(v) { return (v ?? '').toString().trim().toLowerCase(); }

function _emailsFromComplaint(c) {
  const out = new Set();
  const p = c?.payload || {};
  [_nm(c?.email), _nm(c?.customerEmail), _nm(c?.userEmail),
   _nm(c?.account?.email), _nm(c?.user?.email),
   _nm(p?.email), _nm(p?.customerEmail),
   _nm(p?.userEmail), _nm(p?.account?.email), _nm(p?.user?.email)]
    .forEach(e => e && out.add(e));
  return Array.from(out);
}

/* ============== Complaint-Filter nach Email ============== */
export async function complaintsByEmail(email) {
  const target = _nm(email);
  if (!target) return [];
  const r = getRedis();
  const extract = (c) => _emailsFromComplaint(c).includes(target);

  if (r) {
    const keys = await rkeys(`${P}complaint:*`);
    const vals = await Promise.all(keys.map(k => rget(k)));
    const list = vals.filter(v => extract(v));
    list.sort((a, b) => (b?.createdAt || 0) - (a?.createdAt || 0));
    return list;
  }
  const list = Array.from(mem.complaints.values()).filter(v => extract(v));
  list.sort((a, b) => (b?.createdAt || 0) - (a?.createdAt || 0));
  return list;
}

/* ============== Komplettlisten / Admin / Rep ============== */
export async function complaintsAll() {
  const r = getRedis();
  if (r) {
    const keys = await rkeys(`${P}complaint:*`);
    const vals = await Promise.all(keys.map(k => rget(k)));
    return vals.filter(Boolean);
  }
  return Array.from(mem.complaints.values());
}

export async function complaintByTicket(ticket) {
  return await complaintGet(ticket);
}

export async function complaintsOpen() {
  const all = await complaintsAll();
  const open = all.filter(c => {
    const s = Number(c?.status || 0);
    const dec = (c?.decision || '').toString();
    if (dec === 'rejected') return false;
    return s !== Status.CLOSED;
  });
  open.sort((a, b) => (b?.createdAt || 0) - (a?.createdAt || 0));
  return open;
}

/* ============== Mehrfach-Abruf (Emails[]) ============== */
export async function complaintsByEmails(emails, { status = '' } = {}) {
  const mails = (Array.isArray(emails) ? emails : []).map(_nm).filter(Boolean);
  if (mails.length === 0) return [];

  const all = [];
  for (const m of mails) {
    try {
      const list = await complaintsByEmail(m);
      if (Array.isArray(list)) all.push(...list);
    } catch (e) { console.warn('[store] complaintsByEmail failed for', m, e?.message); }
  }

  // Dedup Tickets
  const seen = new Set();
  const dedup = [];
  for (const c of all) {
    const t = (c?.ticket ?? '').toString().trim();
    if (!t || seen.has(t)) continue;
    seen.add(t);
    dedup.push(c);
  }

  // Filter optional nach Status
  const s = (status ?? '').toString().trim();
  const filtered = s ? dedup.filter(c => String(c?.status ?? '') === s) : dedup;

  filtered.sort((a, b) => {
    const ta = a?.updatedAt ?? a?.createdAt ?? 0;
    const tb = b?.updatedAt ?? b?.createdAt ?? 0;
    return (tb || 0) - (ta || 0);
  });

  return filtered;
}

/* ============== Vertreter-spezifische Sammelabfrage ============== */
export async function complaintsForRepEmails(emails, { status = '' } = {}) {
  const wanted = new Set((Array.isArray(emails) ? emails : []).map(_nm).filter(Boolean));
  if (wanted.size === 0) return [];

  const all = await complaintsAll();
  const wantStatus = (status ?? '').toString().trim();

  const seen = new Set();
  const out = [];

  for (const c of (all || [])) {
    const t = (c?.ticket ?? '').toString().trim();
    if (!t || seen.has(t)) continue;
    if (wantStatus && String(c?.status ?? '') !== wantStatus) continue;

    const mails = _emailsFromComplaint(c);
    if (!mails.some(m => wanted.has(m))) continue;

    seen.add(t);
    out.push(c);
  }

  out.sort((a, b) => {
    const ta = a?.updatedAt ?? a?.createdAt ?? 0;
    const tb = b?.updatedAt ?? b?.createdAt ?? 0;
    return (tb || 0) - (ta || 0);
  });

  return out;
}

function _freshestToken(tokens = []) {
  let best = null;
  let ts = 0;
  for (const t of tokens || []) {
    const cur = Number(t?.updatedAt ?? t?.createdAt ?? 0);
    if (!Number.isFinite(cur)) continue;
    if (cur > ts) {
      ts = cur;
      best = t;
    }
  }
  return { token: best, ts };
}

export function isPushTokenFresh(token) {
  const ts = Number(token?.updatedAt ?? token?.createdAt ?? 0);
  if (!Number.isFinite(ts) || ts <= 0) return false;
  return (Date.now() - ts) <= PUSH_TOKEN_FRESH_MS;
}

export async function activityForUser(email) {
  const mail = _nm(email);
  if (!mail) return null;
  const user = await userByEmail(mail);
  if (!user) return null;

  const complaints = await complaintsByEmail(mail).catch(() => []);
  const openTickets = complaints.filter(c => (c?.status ?? 0) !== Status.CLOSED).length;
  const lastComplaint = complaints?.[0] || null;
  const lastComplaintAt = lastComplaint
    ? Number(lastComplaint.updatedAt ?? lastComplaint.createdAt ?? 0) || null
    : null;

  const tokens = normalizePushTokens(user.pushTokens);
  const { token: freshest, ts: pushTs } = _freshestToken(tokens);
  const appVersion = (freshest?.appVersion || user.lastLoginAppVersion || '').toString();
  const appBuild = (freshest?.appBuild || user.lastLoginAppBuild || '').toString();

  return {
    kind: 'customer',
    email: user.email || mail,
    company: user.company || '',
    contact: user.contact || '',
    lastLoginAt: Number(user.lastLoginAt) || null,
    lastComplaintAt,
    lastComplaintTicket: lastComplaint?.ticket || null,
    openTickets,
    pushValid: freshest ? isPushTokenFresh(freshest) : false,
    pushUpdatedAt: pushTs || null,
    pushPlatform: freshest?.platform || '',
    appVersion: appVersion || '',
    appBuild: appBuild || '',
    location: freshest?.location || undefined,
    tokens: tokens.length,
  };
}

export async function activityForRep({ repId, email } = {}) {
  const id = (repId || '').toString().trim();
  const mail = _nm(email);

  let rep = null;
  if (id) rep = await loadRepById(id).catch(() => null);
  if (!rep && mail) rep = await loadRepByEmail(mail).catch(() => null);
  if (!rep) return null;

  const customers = await repCustomers(rep.id).catch(() => []);
  const complaints = await complaintsForRepEmails(customers || []).catch(() => []);
  const openTickets = complaints.filter(c => (c?.status ?? 0) !== Status.CLOSED).length;
  const lastComplaint = complaints?.[0] || null;
  const lastComplaintAt = lastComplaint
    ? Number(lastComplaint.updatedAt ?? lastComplaint.createdAt ?? 0) || null
    : null;

  const tokens = await repPushTokens(rep.id);
  const { token: freshest, ts: pushTs } = _freshestToken(tokens);
  const appVersion = (freshest?.appVersion || rep.lastLoginAppVersion || '').toString();
  const appBuild = (freshest?.appBuild || rep.lastLoginAppBuild || '').toString();

  const customerProfiles = await Promise.all((customers || []).map(async (mail) => {
    const user = await userByEmail(mail).catch(() => null);
    return {
      email: mail,
      company: user?.company || '',
      contact: user?.contact || '',
    };
  }));

  return {
    kind: 'rep',
    repId: rep.id,
    email: rep.email || mail,
    name: `${rep.firstName || ''} ${rep.lastName || ''}`.trim(),
    region: rep.region || '',
    customers: customers || [],
    customerProfiles,
    lastLoginAt: Number(rep.lastLoginAt) || null,
    lastComplaintAt,
    lastComplaintTicket: lastComplaint?.ticket || null,
    openTickets,
    pushValid: freshest ? isPushTokenFresh(freshest) : false,
    pushUpdatedAt: pushTs || null,
    pushPlatform: freshest?.platform || '',
    appVersion: appVersion || '',
    appBuild: appBuild || '',
    location: freshest?.location || undefined,
    tokens: tokens.length,
  };
}

/* ============== DSGVO: User + Complaints anonymisieren ============== */
export async function anonymizeUserAndComplaints(email) {
  const mail = _nm(email);
  if (!mail) return { user: false, complaints: 0 };

  const placeholder = _placeholderFromEmail(mail);
  const placeholderEmail = `${placeholder}@anon.dfs.invalid`;
  const now = Date.now();

  const user = await userByEmail(mail).catch(() => null);
  let anonymizedUser = false;
  if (user) {
    const scrubbed = _scrubValue({ ...user }, placeholderEmail) || {};
    scrubbed.email = placeholderEmail;
    scrubbed.revoked = true;
    scrubbed.revokedAt = now;
    scrubbed.selfDeleted = true;
    scrubbed.deletedAt = now;
    scrubbed.anonymized = true;
    scrubbed.anonymizedAt = now;
    delete scrubbed.pushTokens;
    delete scrubbed.passhash;
    try { await userDelete(mail); } catch (e) { console.warn('[store] anonymize user delete failed:', e); }
    await userSave(scrubbed);
    anonymizedUser = true;
  } else {
    try { await userDelete(mail); } catch (_) {}
  }

  const list = await complaintsByEmail(mail).catch(() => []);
  const complaints = Array.isArray(list) ? list.length : 0;

  return { user: anonymizedUser, complaints, placeholderEmail };
}

/* ============== Downloads für Vertreter ============== */
function _mergeDefaultCategories(list = []) {
  const seen = new Set();
  const out = [];
  const add = (name) => {
    const clean = _normalizeCategoryName(name);
    if (!clean) return;
    const key = clean.toLowerCase();
    if (seen.has(key)) return;
    seen.add(key);
    out.push(clean);
  };
  for (const name of DEFAULT_DOWNLOAD_CATEGORIES) add(name);
  for (const name of list) add(name);
  return out;
}

async function _loadDownloadCategories() {
  if (Array.isArray(mem.downloadCategories)) return [...mem.downloadCategories];
  const r = getRedis();
  let list = null;
  if (r) {
    const raw = await rget(KEY_DOWNLOAD_CATEGORIES);
    if (Array.isArray(raw)) list = raw;
    else if (typeof raw === 'string' && raw.trim()) {
      try { list = JSON.parse(raw); }
      catch { list = []; }
    }
  } else if (global[KEY_GLOBAL_DOWNLOAD_CATEGORIES]) {
    list = global[KEY_GLOBAL_DOWNLOAD_CATEGORIES];
  }

  if (!Array.isArray(list)) list = [];
  const normalized = list.length ? list.map(_normalizeCategoryName).filter(Boolean) : [];
  const merged = normalized.length ? normalized : _mergeDefaultCategories();
  mem.downloadCategories = [...merged];
  return [...merged];
}

async function _persistDownloadCategories(list) {
  const safe = list.map(_normalizeCategoryName).filter(Boolean);
  mem.downloadCategories = [...safe];
  const r = getRedis();
  if (r) await rset(KEY_DOWNLOAD_CATEGORIES, safe);
  else global[KEY_GLOBAL_DOWNLOAD_CATEGORIES] = [...safe];
  return safe;
}

export async function downloadCategoriesWithCounts() {
  const [categories, downloads] = await Promise.all([
    _loadDownloadCategories(),
    downloadsList({ includeInactive: true }),
  ]);
  const counts = new Map();
  for (const item of downloads) {
    const cat = _normalizeCategoryName(item.category);
    const key = cat || '';
    counts.set(key, (counts.get(key) || 0) + 1);
  }
  return categories.map((name) => ({ name, count: counts.get(name) || 0 }));
}

export async function addDownloadCategory(name) {
  const clean = _normalizeCategoryName(name);
  if (!clean) throw new Error('name required');
  const categories = await _loadDownloadCategories();
  const lower = clean.toLowerCase();
  if (categories.some((c) => c.toLowerCase() === lower)) return categories;
  const next = [...categories, clean];
  await _persistDownloadCategories(next);
  return next;
}

export async function deleteDownloadCategory(name, { force = false } = {}) {
  const clean = _normalizeCategoryName(name);
  if (!clean) throw new Error('name required');
  const categories = await _loadDownloadCategories();
  const lower = clean.toLowerCase();
  if (!categories.some((c) => c.toLowerCase() === lower)) return { deleted: false, removedDownloads: [] };

  const downloads = await downloadsList({ includeInactive: true });
  const affected = downloads.filter((d) => _normalizeCategoryName(d.category).toLowerCase() === lower);
  if (affected.length && !force) {
    const err = new Error('category has downloads');
    err.code = 'HAS_DOWNLOADS';
    err.details = { count: affected.length };
    throw err;
  }

  const nextCategories = categories.filter((c) => c.toLowerCase() !== lower);
  await _persistDownloadCategories(nextCategories);

  const removedDownloads = [];
  if (affected.length) {
    for (const item of affected) {
      await downloadsDelete(item.id);
      removedDownloads.push(item.id);
    }
  }

  return { deleted: true, removedDownloads };
}

function _normalizeDownloadBadge(value) {
  const raw = (value ?? '').toString().trim().toLowerCase();
  if (raw === 'new' || raw === 'change') return raw;
  return '';
}

const DOWNLOAD_LANG_CODES = new Set([
  'de', 'en', 'fr', 'it', 'es', 'pt', 'nl', 'da', 'sv', 'nb', 'fi', 'pl', 'cs', 'sk', 'hu', 'ro', 'bg',
  'hr', 'sr', 'bs', 'sl', 'sq', 'el', 'tr', 'lt', 'lv', 'et', 'ga', 'mt', 'uk', 'ru', 'is',
]);

function _normalizeDownloadLanguage(value) {
  const raw = (value ?? '').toString().trim().toLowerCase();
  if (!raw) return '';
  return DOWNLOAD_LANG_CODES.has(raw) ? raw : '';
}

function _safeDownloadUrl(value) {
  const raw = (value ?? '').toString().trim();
  if (!raw) return '';
  if (/^https?:\/\//i.test(raw)) return raw;
  if (raw.startsWith('data:')) return raw;
  return '';
}

function _normalizeDownload(input = {}, existing = null, { bumpVersion = true } = {}) {
  const now = Date.now();
  const base = existing || {};
  const title = _text(input.title ?? base.title ?? '', 240);
  if (!title) throw new Error('title required');
  const description = _text(input.description ?? base.description ?? '', 1000);
  const category = _text(input.category ?? base.category ?? '', 120);
  const badge = _normalizeDownloadBadge(input.badge ?? base.badge ?? '');
  const active = input.active !== undefined ? Boolean(input.active) : Boolean(base.active ?? true);
  const language = _normalizeDownloadLanguage(input.language ?? base.language ?? '');

  const allowedInput = Array.isArray(input.allowedRepresentatives)
    ? input.allowedRepresentatives
    : Array.isArray(base.allowedRepresentatives)
      ? base.allowedRepresentatives
      : [];
  const allowedRepresentatives = Array.from(new Set(
    allowedInput
      .map((v) => (v ?? '').toString().trim())
      .filter(Boolean)
  ));

  const fileName = _text(input.fileName ?? input.name ?? base.fileName ?? '', 240);
  const downloadUrl = _safeDownloadUrl(input.downloadUrl ?? input.url ?? base.downloadUrl ?? '') || null;
  const mime = _text(input.mime ?? base.mime ?? '', 120) || null;
  const size = Number.isFinite(input.size) ? Math.max(0, Number(input.size))
    : Number.isFinite(base.size) ? Math.max(0, Number(base.size))
    : 0;
  const uploadedAt = _parseTs(input.uploadedAt ?? base.uploadedAt, now) ?? now;

  if (!downloadUrl) throw new Error('downloadUrl required');

  const prevVersion = Number.isFinite(base.version) ? Number(base.version) : 0;
  const version = bumpVersion ? Math.max(prevVersion + 1, 1) : Math.max(prevVersion || 1, 1);

  return {
    id: (input.id ?? base.id ?? '').toString().trim() || `dl_${now}_${Math.random().toString(36).slice(2, 8)}`,
    title,
    description: description || '',
    category: category || '',
    badge,
    active,
    language,
    fileName: fileName || '',
    downloadUrl,
    mime,
    size,
    uploadedAt,
    allowedRepresentatives,
    createdAt: Number.isFinite(base.createdAt) ? Number(base.createdAt) : now,
    updatedAt: now,
    version,
  };
}

async function _loadDownloads() {
  const r = getRedis();
  let list = null;

  if (r) {
    const raw = await rget(KEY_DOWNLOADS);
    if (Array.isArray(raw)) list = raw;
    else if (typeof raw === 'string' && raw.trim()) {
      try { list = JSON.parse(raw); }
      catch { list = []; }
    } else if (raw && typeof raw === 'object') {
      list = raw.items || raw.list || [];
    }
  } else if (Array.isArray(mem.downloads) && mem.downloads.length) {
    return mem.downloads.map((d) => ({ ...d }));
  } else if (global.__DFS_DOWNLOADS__ && Array.isArray(global.__DFS_DOWNLOADS__)) {
    list = global.__DFS_DOWNLOADS__;
  }

  if (!Array.isArray(list)) list = [];
  const normalized = [];
  for (const item of list) {
    try {
      const norm = _normalizeDownload(item, { ...item, version: Number(item?.version) || 0 }, { bumpVersion: false });
      normalized.push(norm);
    } catch (_) { /* ignore */ }
  }
  mem.downloads = normalized.map((d) => ({ ...d }));
  mem.downloadsCacheVersion += 1;
  return normalized;
}

async function _persistDownloads(list) {
  const safe = list.map((d) => ({ ...d }));
  mem.downloads = safe.map((d) => ({ ...d }));
  mem.downloadsCacheVersion += 1;
  const r = getRedis();
  if (r) await rset(KEY_DOWNLOADS, safe);
  else global.__DFS_DOWNLOADS__ = safe;
  return safe;
}

export async function downloadsList({ includeInactive = false } = {}) {
  const list = await _loadDownloads();
  const filtered = includeInactive ? list : list.filter((d) => d.active !== false);
  return [...filtered].sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0));
}

export async function downloadsUpsert(payload = {}) {
  const list = await _loadDownloads();
  const targetId = (payload?.id ?? '').toString().trim();
  const idx = targetId ? list.findIndex((d) => d.id === targetId) : -1;
  const existing = idx >= 0 ? list[idx] : null;
  const normalized = _normalizeDownload(payload, existing);
  if (idx >= 0) list[idx] = normalized; else list.push(normalized);
  await _persistDownloads(list);
  return normalized;
}

export async function downloadsDelete(id) {
  const target = (id ?? '').toString().trim();
  if (!target) return false;
  const list = await _loadDownloads();
  const next = list.filter((d) => d.id !== target);
  await _persistDownloads(next);
  return next.length !== list.length;
}

async function _loadRepDownloadSeen(repId) {
  const key = KEY_REP_DOWNLOAD_SEEN(repId);
  const fromMem = mem.repDownloadSeen.get(repId);
  if (fromMem) return { ...fromMem };
  const r = getRedis();
  let data = null;
  if (r) {
    const raw = await rget(key);
    if (raw && typeof raw === 'object') data = raw;
    else if (typeof raw === 'string' && raw.trim()) {
      try { data = JSON.parse(raw); }
      catch { data = {}; }
    }
  }
  if (!data || typeof data !== 'object') data = {};
  mem.repDownloadSeen.set(repId, { ...data });
  return data;
}

async function _persistRepDownloadSeen(repId, map) {
  mem.repDownloadSeen.set(repId, { ...map });
  const r = getRedis();
  if (r) await rset(KEY_REP_DOWNLOAD_SEEN(repId), map);
  else {
    if (!global.__DFS_REP_DOWNLOAD_SEEN__) global.__DFS_REP_DOWNLOAD_SEEN__ = new Map();
    global.__DFS_REP_DOWNLOAD_SEEN__.set(repId, { ...map });
  }
  return map;
}

export async function markDownloadsSeen(repId, ids = []) {
  const list = await downloadsList({ includeInactive: true });
  const map = await _loadRepDownloadSeen(repId);
  const idSet = new Set(ids.map((x) => (x || '').toString().trim()).filter(Boolean));
  if (!idSet.size) return map;
  for (const item of list) {
    if (idSet.has(item.id)) {
      map[item.id] = item.version;
    }
  }
  await _persistRepDownloadSeen(repId, map);
  return map;
}

export async function repDownloadsWithBadges(repId, { includeInactive = false } = {}) {
  const list = await downloadsList({ includeInactive });
  const seen = await _loadRepDownloadSeen(repId);
  return list
    .filter((item) => !item.allowedRepresentatives?.length || item.allowedRepresentatives.includes(repId))
    .map((item) => {
      const seenVersion = Number(seen?.[item.id] ?? 0);
      const showBadge = item.badge && (!seenVersion || seenVersion < item.version);
      return { ...item, badge: showBadge ? item.badge : '' };
    });
}

export async function removeRepFromDownloadPermissions(repId) {
  const target = (repId ?? '').toString().trim();
  if (!target) return [];
  const list = await downloadsList({ includeInactive: true });
  let changed = false;
  const next = list.map((item) => {
    if (!Array.isArray(item.allowedRepresentatives) || !item.allowedRepresentatives.length) return item;
    const filtered = item.allowedRepresentatives.filter((id) => id !== target);
    if (filtered.length === item.allowedRepresentatives.length) return item;
    changed = true;
    return { ...item, allowedRepresentatives: filtered };
  });
  if (changed) {
    await _persistDownloads(next);
  }
  return next;
}

/* ============== Gate Codes ============== */
function _gateEmail(email) {
  return String(email || '').trim().toLowerCase();
}

export async function gateStoreSet(email, entry = {}, options = {}) {
  const mail = _gateEmail(email);
  const codeHash = String(entry?.codeHash || '').trim();
  if (!mail || !codeHash) return false;

  const record = {
    email: mail,
    codeHash,
    used: Boolean(entry?.used),
    createdAt: Number.isFinite(entry?.createdAt) ? entry.createdAt : Date.now(),
  };

  if (entry?.meta && typeof entry.meta === 'object') {
    record.meta = { ...entry.meta };
  }

  const ttlRaw = options?.ttlSeconds ?? DEFAULT_GATE_TTL_SECONDS;
  const ttlSeconds = Number.isFinite(ttlRaw) && ttlRaw > 0 ? Math.round(ttlRaw) : null;

  const r = getRedis();
  if (r) {
    try {
      if (ttlSeconds) await r.set(KEY_GATE(mail), record, { ex: ttlSeconds });
      else await r.set(KEY_GATE(mail), record);
    } catch (e) {
      console.error('[store] gateStoreSet failed:', e);
      throw e;
    }
  }

  // Immer auch im Memory-Cache aktualisieren (hilft für lokale Tests)
  mem.gateCodes.set(mail, record);

  return record;
}

export async function gateStoreGet(email) {
  const mail = _gateEmail(email);
  if (!mail) return null;
  const r = getRedis();
  if (r) {
    const raw = await rget(KEY_GATE(mail));
    if (!raw) return mem.gateCodes.get(mail) ?? null;
    if (typeof raw === 'string') {
      try { return JSON.parse(raw); }
      catch { return null; }
    }
    if (typeof raw === 'object') return raw;
    return null;
  }
  return mem.gateCodes.get(mail) ?? null;
}

export async function gateStoreDelete(email) {
  const mail = _gateEmail(email);
  if (!mail) return true;
  const r = getRedis();
  if (r) {
    try { await rdel(KEY_GATE(mail)); }
    catch (e) { console.error('[store] gateStoreDelete failed:', e); }
  }
  mem.gateCodes.delete(mail);
  return true;
}

/* ============== CAPA / 8D-Reports ============== */
const CAPA_STATUS = new Set(['open', 'inProgress', 'closed']);

const emptySections = () => ({
  d1: { teamMembers: [] },
  d2: { immediateActions: [] },
  d3: { causes: [] },
  d4: { correctiveActions: [] },
  d5: { verification: {} },
  d6: { preventiveActions: [] },
  d7: { lessons: [] },
  d8: { approvals: [] },
});

function normalizeString(v) { return (v ?? '').toString(); }

function normalizeDateValue(v) {
  if (!v && v !== 0) return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

function normalizeArray(list) {
  return Array.isArray(list) ? list.filter(Boolean) : [];
}

function normalizeCapaSections(raw = {}) {
  const base = emptySections();
  const d1 = raw.d1 || {};
  base.d1 = {
    area: normalizeString(d1.area || ''),
    date: normalizeDateValue(d1.date),
    teamLead: normalizeString(d1.teamLead || ''),
    product: normalizeString(d1.product || ''),
    batch: normalizeString(d1.batch || ''),
    problem: normalizeString(d1.problem || ''),
    teamMembers: normalizeArray(d1.teamMembers || []).map(m => ({
      name: normalizeString(m?.name || ''),
      role: normalizeString(m?.role || ''),
    })).filter(m => m.name || m.role),
  };

  const d2 = raw.d2 || {};
  base.d2 = {
    immediateActions: normalizeArray(d2.immediateActions || []).map(a => ({
      action: normalizeString(a?.action || ''),
      doneAt: normalizeDateValue(a?.doneAt),
      notes: normalizeString(a?.notes || ''),
      selected: a?.selected === true || a?.selected === 'true' || a?.selected === 1,
    })).filter(a => a.action || a.notes),
    details: normalizeString(d2.details || ''),
  };

  const d3 = raw.d3 || {};
  base.d3 = {
    causes: normalizeArray(d3.causes || []).map(c => ({
      why: normalizeString(c?.why || ''),
      root: normalizeString(c?.root || ''),
    })).filter(c => c.why || c.root),
    summary: normalizeString(d3.summary || ''),
  };

  const d4 = raw.d4 || {};
  base.d4 = {
    correctiveActions: normalizeArray(d4.correctiveActions || []).map(c => ({
      description: normalizeString(c?.description || ''),
      owner: normalizeString(c?.owner || ''),
      dueDate: normalizeDateValue(c?.dueDate),
      completedAt: normalizeDateValue(c?.completedAt),
      status: normalizeString(c?.status || ''),
      changeType: normalizeString(c?.changeType || ''),
      notes: normalizeString(c?.notes || ''),
    })).filter(c => c.description || c.owner || c.status),
  };

  const d5 = raw.d5 || {};
  base.d5 = {
    description: normalizeString(d5.description || ''),
    date: normalizeDateValue(d5.date),
    effective: d5.effective === true || d5.effective === 'true' || d5.effective === 1,
    followUp: normalizeString(d5.followUp || ''),
  };

  const d6 = raw.d6 || {};
  base.d6 = {
    preventiveActions: normalizeArray(d6.preventiveActions || []).map(p => normalizeString(p)).filter(Boolean),
  };

  const d7 = raw.d7 || {};
  base.d7 = {
    lessons: normalizeArray(d7.lessons || []).map(l => normalizeString(l)).filter(Boolean),
    transfer: normalizeString(d7.transfer || ''),
  };

  const d8 = raw.d8 || {};
  base.d8 = {
    approvals: normalizeArray(d8.approvals || []).map(a => ({
      name: normalizeString(a?.name || ''),
      role: normalizeString(a?.role || ''),
      date: normalizeDateValue(a?.date),
      signature: normalizeString(a?.signature || ''),
    })).filter(a => a.name || a.role),
    closingNote: normalizeString(d8.closingNote || ''),
  };

  return base;
}

function normalizeCapaStatus(status) {
  const raw = (status ?? '').toString().trim();
  const lc = raw.toLowerCase();
  if (CAPA_STATUS.has(lc)) return lc;
  if (['open', 'offen'].includes(lc)) return 'open';
  if (['inprogress', 'in bearbeitung'].includes(lc)) return 'inProgress';
  if (['done', 'closed', 'abgeschlossen'].includes(lc)) return 'closed';
  return 'open';
}

export async function nextCapaNumber() {
  const r = getRedis();
  const year = new Date().getFullYear().toString().slice(-2);
  const key = KEY_CAPA_COUNTER(year);
  if (r) {
    const n = await withRedisTimeout(r.incr(key), 'capa counter');
    return `DFS-CAPA-${year}_${String(n).padStart(4, '0')}`;
  }
  const current = mem.counters.capa[year] ?? 1;
  mem.counters.capa[year] = current + 1;
  return `DFS-CAPA-${year}_${String(current).padStart(4, '0')}`;
}

function normalizeCapaRecord(data = {}) {
  const now = Date.now();
  const normalized = { ...data };
  normalized.id = (normalized.id || normalized.capaNumber || crypto.randomUUID()).toString();
  normalized.capaNumber = normalizeString(normalized.capaNumber || '');
  if (!normalized.capaNumber) normalized.capaNumber = normalized.id.startsWith('CAPA-') ? normalized.id : null;
  normalized.title = normalizeString(normalized.title || normalized.problem || '');
  normalized.status = normalizeCapaStatus(normalized.status);
  normalized.responsibleUserId = normalizeString(normalized.responsibleUserId || '');
  normalized.complaintId = normalizeString(normalized.complaintId || '');
  normalized.changeId = normalizeString(normalized.changeId || '');
  const linkedRisks = Array.isArray(normalized.fmeaRiskNumbers)
    ? normalized.fmeaRiskNumbers.map(v => normalizeString(v)).filter(Boolean)
    : [];
  if (linkedRisks.length > 0) normalized.fmeaRiskNumbers = Array.from(new Set(linkedRisks)); else delete normalized.fmeaRiskNumbers;
  normalized.sections = normalizeCapaSections(normalized.sections || {});
  normalized.createdAt = normalizeDateValue(normalized.createdAt) || now;
  normalized.updatedAt = normalizeDateValue(normalized.updatedAt) || now;
  normalized.language = normalizeString(normalized.language || 'de');
  return normalized;
}

function capaKey(id) {
  return `${P}capa:${id}`;
}

async function capaFindByNumber(capaNumber) {
  if (!capaNumber) return null;
  const r = getRedis();
  if (r) {
    const keys = await rkeys(`${P}capa:*`);
    const vals = await Promise.all(keys.map(k => rget(k)));
    return vals.find(v => (v?.capaNumber || '').toString() === capaNumber) || null;
  }
  for (const v of mem.capaReports.values()) {
    if ((v?.capaNumber || '').toString() === capaNumber) return v;
  }
  return null;
}

export async function capaSave(record) {
  const data = normalizeCapaRecord(record);
  if (!data.capaNumber) data.capaNumber = await nextCapaNumber();
  const key = capaKey(data.id);
  const r = getRedis();
  if (r) await rset(key, data); else mem.capaReports.set(data.id, data);
  return data;
}

export async function capaGet(idOrNumber) {
  if (!idOrNumber) return null;
  const key = capaKey(idOrNumber);
  const r = getRedis();
  const direct = r ? await rget(key) : mem.capaReports.get(idOrNumber) ?? null;
  if (direct) return normalizeCapaRecord({ ...direct, id: idOrNumber });
  const byNumber = await capaFindByNumber(idOrNumber);
  return byNumber ? normalizeCapaRecord({ ...byNumber, id: byNumber.id || idOrNumber }) : null;
}

export async function capaAll() {
  const r = getRedis();
  if (r) {
    const keys = await rkeys(`${P}capa:*`);
    const vals = await Promise.all(keys.map(k => rget(k)));
    const list = [];
    keys.forEach((key, index) => {
      const val = vals[index];
      if (!val) return;
      const id = key.replace(`${P}capa:`, '');
      list.push(normalizeCapaRecord({ ...val, id }));
    });
    list.sort((a, b) => (b?.updatedAt || 0) - (a?.updatedAt || 0));
    return list;
  }
  const list = Array.from(mem.capaReports.values()).map(v => normalizeCapaRecord(v));
  list.sort((a, b) => (b?.updatedAt || 0) - (a?.updatedAt || 0));
  return list;
}

export async function capaUpdate(id, patch) {
  const current = await capaGet(id);
  if (!current) return null;
  const updated = { ...current, ...patch, sections: { ...current.sections, ...(patch?.sections || {}) }, updatedAt: Date.now() };
  return await capaSave(updated);
}

export async function capaDelete(id) {
  if (!id) return false;
  const key = capaKey(id);
  const r = getRedis();
  if (r) await rdel(key); else mem.capaReports.delete(id);
  return true;
}

const CHANGE_TYPES = new Set(['process', 'document', 'product', 'system', 'other']);
const CHANGE_PRODUCT_IMPACT = new Set(['none', 'low', 'relevant']);
const CHANGE_DOC_IMPACT = new Set(['none', 'editorial', 'content']);
const CHANGE_PROCESS_IMPACT = new Set(['none', 'yes']);
const CHANGE_REG_IMPACT = new Set(['none', 'yes']);
const CHANGE_SAFETY = new Set(['none', 'potential']);
const CHANGE_RISK_DELTA = new Set(['none', 'increased']);
const CHANGE_FURTHER_ANALYSIS = new Set(['no', 'yes']);
const CHANGE_DECISIONS = new Set(['approved', 'approvedWithConditions', 'furtherEvaluation']);
const CHANGE_FOLLOW_UPS = new Set(['prrc', 'fmea', 'capa']);
const CHANGE_STATUS = new Set(['open', 'inProgress', 'closed', 'waitingPrrc']);
const CHANGE_PRRC_DECISIONS = new Set(['approved', 'rejected']);
const CHANGE_ESCALATION_STATUS = new Set(['open', 'inProgress', 'closed']);

function normalizeChangeEnum(value, allowed, fallback) {
  const raw = (value ?? '').toString().trim();
  if (!raw) return fallback;
  if (allowed.has(raw)) return raw;
  const lc = raw.toLowerCase();
  if (allowed.has(lc)) return lc;
  return fallback;
}

export async function nextChangeNumber() {
  const r = getRedis();
  const year = new Date().getFullYear().toString().slice(-2);
  const key = KEY_CHANGE_COUNTER(year);
  if (r) {
    const n = await withRedisTimeout(r.incr(key), 'change counter');
    return `DFS-CHG-${year}_${String(n).padStart(4, '0')}`;
  }
  const current = mem.counters.change[year] ?? 1;
  mem.counters.change[year] = current + 1;
  return `DFS-CHG-${year}_${String(current).padStart(4, '0')}`;
}

function normalizeChangeRecord(data = {}) {
  const now = Date.now();
  const normalized = { ...data };
  normalized.id = (normalized.id || normalized.changeId || crypto.randomUUID()).toString();
  normalized.changeId = normalizeString(normalized.changeId || '');
  if (!normalized.changeId) normalized.changeId = normalized.id.startsWith('DFS-CHG-') ? normalized.id : null;
  normalized.title = normalizeString(normalized.title || '');
  normalized.description = normalizeString(normalized.description || '');
  normalized.justification = normalizeString(normalized.justification || '');
  normalized.changeType = normalizeChangeEnum(normalized.changeType, CHANGE_TYPES, 'other');
  normalized.initiator = normalizeString(normalized.initiator || normalized.createdBy || '');
  normalized.createdAt = normalizeDateValue(normalized.createdAt) || now;
  normalized.updatedAt = normalizeDateValue(normalized.updatedAt) || now;
  normalized.affectedDocuments = normalizeArray(normalized.affectedDocuments || [])
    .map(v => normalizeString(v))
    .filter(Boolean);
  normalized.affectedProcesses = normalizeArray(normalized.affectedProcesses || [])
    .map(v => normalizeString(v))
    .filter(Boolean);
  normalized.affectedProcessOther = normalizeString(normalized.affectedProcessOther || '');
  normalized.trigger = normalizeString(normalized.trigger || '');

  normalized.productImpact = normalizeChangeEnum(normalized.productImpact, CHANGE_PRODUCT_IMPACT, 'none');
  normalized.documentationImpact = normalizeChangeEnum(normalized.documentationImpact, CHANGE_DOC_IMPACT, 'none');
  normalized.processImpact = normalizeChangeEnum(normalized.processImpact, CHANGE_PROCESS_IMPACT, 'none');
  normalized.regulatoryImpact = normalizeChangeEnum(normalized.regulatoryImpact, CHANGE_REG_IMPACT, 'none');
  normalized.safetyRelevance = normalizeChangeEnum(normalized.safetyRelevance, CHANGE_SAFETY, 'none');
  normalized.riskChange = normalizeChangeEnum(normalized.riskChange, CHANGE_RISK_DELTA, 'none');
  normalized.furtherAnalysis = normalizeChangeEnum(normalized.furtherAnalysis, CHANGE_FURTHER_ANALYSIS, 'no');

  normalized.decision = normalizeChangeEnum(normalized.decision, CHANGE_DECISIONS, '');
  normalized.followUps = normalizeArray(normalized.followUps || [])
    .map(v => normalizeChangeEnum(v, CHANGE_FOLLOW_UPS, ''))
    .filter(Boolean);
  normalized.followUpLink = normalizeString(normalized.followUpLink || '');
  normalized.decisionNote = normalizeString(normalized.decisionNote || '');
  normalized.decisionBy = normalizeString(normalized.decisionBy || '');
  normalized.decisionAt = normalizeDateValue(normalized.decisionAt);
  normalized.prrcDecision = normalizeChangeEnum(normalized.prrcDecision, CHANGE_PRRC_DECISIONS, '');
  normalized.prrcNote = normalizeString(normalized.prrcNote || '');
  normalized.prrcBy = normalizeString(normalized.prrcBy || '');
  normalized.prrcAt = normalizeDateValue(normalized.prrcAt);
  normalized.fmeaId = normalizeString(normalized.fmeaId || '');
  normalized.fmeaStatus = normalizeChangeEnum(normalized.fmeaStatus, CHANGE_ESCALATION_STATUS, '');
  normalized.capaId = normalizeString(normalized.capaId || '');
  normalized.capaStatus = normalizeChangeEnum(normalized.capaStatus, CHANGE_ESCALATION_STATUS, '');

  normalized.evaluator = normalizeString(normalized.evaluator || '');
  normalized.evaluatedAt = normalizeDateValue(normalized.evaluatedAt);

  normalized.implementationOwner = normalizeString(normalized.implementationOwner || '');
  normalized.plannedDate = normalizeDateValue(normalized.plannedDate);
  normalized.implementedAt = normalizeDateValue(normalized.implementedAt);
  normalized.implemented = normalized.implemented === true || normalized.implemented === 'true' || normalized.implemented === 1;
  normalized.documentsUpdated = normalized.documentsUpdated === true || normalized.documentsUpdated === 'true' || normalized.documentsUpdated === 1;
  normalized.status = normalizeChangeEnum(normalized.status, CHANGE_STATUS, 'open');
  normalized.implementationBy = normalizeString(normalized.implementationBy || '');

  normalized.history = normalizeArray(normalized.history || [])
    .map(h => ({
      action: normalizeString(h?.action || ''),
      actor: normalizeString(h?.actor || ''),
      at: normalizeDateValue(h?.at) || now,
      note: normalizeString(h?.note || ''),
      fields: normalizeArray(h?.fields || []).map(v => normalizeString(v)).filter(Boolean),
    }))
    .filter(h => h.action);

  return normalized;
}

function changeKey(id) {
  return `${P}change:${id}`;
}

async function changeFindByNumber(changeId) {
  if (!changeId) return null;
  const r = getRedis();
  if (r) {
    const keys = await rkeys(`${P}change:*`);
    const vals = await Promise.all(keys.map(k => rget(k)));
    const index = vals.findIndex(v => (v?.changeId || '').toString() === changeId);
    if (index < 0) return null;
    const id = keys[index].replace(`${P}change:`, '');
    return { ...vals[index], id };
  }
  for (const [id, v] of mem.changeRecords.entries()) {
    if ((v?.changeId || '').toString() === changeId) return { ...v, id };
  }
  return null;
}

export async function changeSave(record = {}) {
  const data = normalizeChangeRecord(record);
  const key = changeKey(data.id);
  const r = getRedis();
  if (r) await rset(key, data); else mem.changeRecords.set(data.id, data);
  return data;
}

export async function changeGet(idOrNumber) {
  const key = changeKey(idOrNumber);
  const r = getRedis();
  if (r) {
    const direct = await rget(key);
    if (direct) return normalizeChangeRecord({ ...direct, id: idOrNumber });
  } else if (mem.changeRecords.has(idOrNumber)) {
    return normalizeChangeRecord({ ...mem.changeRecords.get(idOrNumber), id: idOrNumber });
  }
  const byNumber = await changeFindByNumber(idOrNumber);
  return byNumber ? normalizeChangeRecord(byNumber) : null;
}

export async function changeAll() {
  const r = getRedis();
  if (r) {
    const keys = await rkeys(`${P}change:*`);
    const list = await Promise.all(keys.map(k => rget(k)));
    return list.map((v, index) => {
      const id = keys[index].replace(`${P}change:`, '');
      return normalizeChangeRecord({ ...v, id });
    });
  }
  return Array.from(mem.changeRecords.entries()).map(([id, v]) => normalizeChangeRecord({ ...v, id }));
}

export async function changeUpdate(id, patch = {}) {
  const current = await changeGet(id);
  if (!current) return null;
  const updated = normalizeChangeRecord({
    ...current,
    ...patch,
    updatedAt: Date.now(),
  });
  return await changeSave(updated);
}

export async function changeDelete(id) {
  const key = changeKey(id);
  const r = getRedis();
  if (r) await rdel(key); else mem.changeRecords.delete(id);
}

/* =========================================================
   FMEA / Risikomanagement (MDR-TD-bezogen)
   ========================================================= */

const KEY_FMEA = (id) => `${P}fmea:${id}`;

function normalizeRiskValue(v) {
  const n = Number(v);
  if (!Number.isFinite(n)) return null;
  if (n < 1) return 1;
  if (n > 5) return 5;
  return Math.round(n);
}

function normalizeRiskLevel(score, thresholds = { red: 15, yellow: 8 }) {
  if (!score && score !== 0) return null;
  if (score >= thresholds.red) return 'red';
  if (score >= thresholds.yellow) return 'yellow';
  return 'green';
}

function normalizeRiskEntry(raw = {}, { nextNumber = 1, thresholds } = {}) {
  const now = Date.now();
  const risk = { ...raw };
  risk.id = (risk.id || crypto.randomUUID()).toString();
  risk.riskNumber = (risk.riskNumber || `R-${String(nextNumber).padStart(3, '0')}`).toString();

  risk.category = (risk.category || '').toString();
  risk.hazard = (risk.hazard || '').toString();
  risk.hazardSituation = (risk.hazardSituation || '').toString();
  risk.harm = (risk.harm || '').toString();
  risk.causes = (risk.causes || '').toString();
  risk.affectedArea = (risk.affectedArea || '').toString();
  risk.processReference = (risk.processReference || '').toString();
  risk.documents = (risk.documents || '').toString();
  risk.proposedAction = (risk.proposedAction || '').toString();
  risk.actionTaken = (risk.actionTaken || '').toString();
  risk.riskBenefitAnalysis = (risk.riskBenefitAnalysis || '').toString();

  risk.severity = normalizeRiskValue(risk.severity);
  risk.occurrence = normalizeRiskValue(risk.occurrence);
  risk.severityAfter = normalizeRiskValue(risk.severityAfter);
  risk.occurrenceAfter = normalizeRiskValue(risk.occurrenceAfter);

  const beforeScore = risk.severity && risk.occurrence ? risk.severity * risk.occurrence : null;
  const afterScore = risk.severityAfter && risk.occurrenceAfter ? risk.severityAfter * risk.occurrenceAfter : null;
  risk.riskScore = beforeScore;
  risk.riskScoreAfter = afterScore;
  risk.riskLevel = beforeScore ? normalizeRiskLevel(beforeScore, thresholds) : null;
  risk.riskLevelAfter = afterScore ? normalizeRiskLevel(afterScore, thresholds) : null;

  risk.newHazard = risk.newHazard === true || risk.newHazard === 'true' || risk.newHazard === 1;
  risk.residualRiskOk =
    risk.residualRiskOk === true || risk.residualRiskOk === 'true' || risk.residualRiskOk === 1;

  risk.linkedComplaints = Array.isArray(risk.linkedComplaints)
    ? Array.from(new Set(risk.linkedComplaints.map(v => (v ?? '').toString().trim()).filter(Boolean)))
    : [];
  risk.linkedCapas = Array.isArray(risk.linkedCapas)
    ? Array.from(new Set(risk.linkedCapas.map(v => (v ?? '').toString().trim()).filter(Boolean)))
    : [];

  risk.createdAt = risk.createdAt || now;
  risk.updatedAt = now;
  return risk;
}

function normalizeFmeaRecord(raw = {}) {
  const now = Date.now();
  const thresholds = {
    red: Number(raw?.riskMatrix?.red) || 15,
    yellow: Number(raw?.riskMatrix?.yellow) || 8,
  };

  const base = { ...raw };
  base.id = (base.id || crypto.randomUUID()).toString();
  base.title = (base.title || base.mdrTd || '').toString();
  base.mdrTd = (base.mdrTd || '').toString();
  base.productGroup = (base.productGroup || '').toString();
  base.medicalProduct = (base.medicalProduct || '').toString();
  base.moderator = (base.moderator || '').toString();
  const revisionNumber = Number(base.revision);
  base.revision = Number.isFinite(revisionNumber) && revisionNumber > 0
    ? Math.round(revisionNumber).toString()
    : '1';
  base.prrcApproved = base.prrcApproved === true || base.prrcApproved === 'true' || base.prrcApproved === 1;
  base.prrcName = (base.prrcName || '').toString();
  base.prrcDate = base.prrcDate ? normalizeDateValue(base.prrcDate) : null;
  base.createdAt = normalizeDateValue(base.createdAt) || now;
  base.updatedAt = normalizeDateValue(base.updatedAt) || now;
  base.updatedBy = (base.updatedBy || '').toString();
  base.createdBy = (base.createdBy || '').toString();
  base.riskMatrix = { red: thresholds.red, yellow: thresholds.yellow };

  const risks = Array.isArray(base.risks) ? base.risks : [];
  const normalizedRisks = risks.map((r, idx) =>
    normalizeRiskEntry(r, { nextNumber: idx + 1, thresholds: base.riskMatrix })
  );
  base.risks = normalizedRisks;
  base.riskCounter = Math.max(
    normalizedRisks.reduce((max, r) => {
      const parsed = Number((r?.riskNumber || '').toString().replace(/[^0-9]/g, ''));
      return Number.isFinite(parsed) ? Math.max(max, parsed) : max;
    }, 0),
    Number(base.riskCounter) || 0,
  );

  return base;
}

async function fmeaAllFromRedis() {
  const keys = await rkeys(`${P}fmea:*`);
  const vals = await Promise.all(keys.map(k => rget(k)));
  const list = [];
  keys.forEach((key, index) => {
    const val = vals[index];
    if (!val) return;
    const id = key.replace(`${P}fmea:`, '');
    list.push(normalizeFmeaRecord({ ...val, id }));
  });
  list.sort((a, b) => (b?.updatedAt || 0) - (a?.updatedAt || 0));
  return list;
}

export async function fmeaAll() {
  const r = getRedis();
  if (r) return await fmeaAllFromRedis();
  const list = Array.from(mem.fmeas?.values?.() || []).map(v => normalizeFmeaRecord(v));
  list.sort((a, b) => (b?.updatedAt || 0) - (a?.updatedAt || 0));
  return list;
}

export async function fmeaGet(id) {
  if (!id) return null;
  const key = KEY_FMEA(id);
  const r = getRedis();
  const direct = r ? await rget(key) : mem.fmeas?.get?.(id) ?? null;
  return direct ? normalizeFmeaRecord({ ...direct, id }) : null;
}

export async function fmeaSave(record) {
  const data = normalizeFmeaRecord(record);
  const key = KEY_FMEA(data.id);
  const r = getRedis();
  if (r) await rset(key, data); else {
    if (!mem.fmeas) mem.fmeas = new Map();
    mem.fmeas.set(data.id, data);
  }
  return data;
}

export async function fmeaUpdate(id, patch) {
  const current = await fmeaGet(id);
  if (!current) return null;
  const updated = normalizeFmeaRecord({ ...current, ...patch, updatedAt: Date.now() });
  return await fmeaSave(updated);
}

export async function fmeaDelete(id) {
  if (!id) return false;
  const key = KEY_FMEA(id);
  const r = getRedis();
  if (r) await rdel(key); else mem.fmeas?.delete?.(id);
  return true;
}

function nextRiskNumberForFmea(fmea) {
  const counter = Number(fmea?.riskCounter || 0);
  const numbers = Array.isArray(fmea?.risks)
    ? fmea.risks
        .map(r => Number((r?.riskNumber || '').toString().replace(/[^0-9]/g, '')))
        .filter(n => Number.isFinite(n))
    : [];
  const maxExisting = numbers.length ? Math.max(...numbers) : 0;
  return Math.max(counter, maxExisting) + 1;
}

export async function fmeaAddRisk(fmeaId, riskData = {}) {
  const current = await fmeaGet(fmeaId);
  if (!current) return null;
  const nextNumber = nextRiskNumberForFmea(current);
  const risk = normalizeRiskEntry(riskData, { nextNumber, thresholds: current.riskMatrix });
  const updated = { ...current, risks: [...(current.risks || []), risk], riskCounter: nextNumber, updatedAt: Date.now() };
  await fmeaSave(updated);
  await syncFmeaRiskLinks(updated, risk, null);
  return { fmea: updated, risk };
}

function findRiskIndex(fmea, riskIdOrNumber) {
  if (!fmea?.risks) return -1;
  const needle = (riskIdOrNumber || '').toString();
  return fmea.risks.findIndex(
    (r) => r.id === needle || (r.riskNumber && r.riskNumber.toString() === needle)
  );
}

export async function fmeaUpdateRisk(fmeaId, riskId, patch = {}) {
  const current = await fmeaGet(fmeaId);
  if (!current) return null;
  const idx = findRiskIndex(current, riskId);
  if (idx < 0) return null;
  const existing = current.risks[idx];
  const updatedRisk = normalizeRiskEntry({ ...existing, ...patch }, {
    nextNumber: existing?.riskNumber || idx + 1,
    thresholds: current.riskMatrix,
  });
  const risks = [...current.risks];
  risks.splice(idx, 1, updatedRisk);
  const updated = { ...current, risks, updatedAt: Date.now() };
  await fmeaSave(updated);
  await syncFmeaRiskLinks(updated, updatedRisk, existing);
  return { fmea: updated, risk: updatedRisk };
}

export async function fmeaDeleteRisk(fmeaId, riskId) {
  const current = await fmeaGet(fmeaId);
  if (!current) return null;
  const idx = findRiskIndex(current, riskId);
  if (idx < 0) return null;
  const existing = current.risks[idx];
  const risks = [...current.risks];
  risks.splice(idx, 1);
  const updated = { ...current, risks, updatedAt: Date.now() };
  await fmeaSave(updated);
  await syncFmeaRiskLinks(updated, null, existing);
  return updated;
}

export async function fmeaDuplicateRisk(fmeaId, riskId) {
  const current = await fmeaGet(fmeaId);
  if (!current) return null;
  const idx = findRiskIndex(current, riskId);
  if (idx < 0) return null;
  const toClone = current.risks[idx];
  const nextNumber = nextRiskNumberForFmea(current);
  const cloned = normalizeRiskEntry(
    { ...toClone, id: undefined, riskNumber: undefined, createdAt: Date.now(), linkedComplaints: [], linkedCapas: [] },
    { nextNumber, thresholds: current.riskMatrix }
  );
  const risks = [...current.risks];
  risks.splice(idx + 1, 0, cloned);
  const updated = { ...current, risks, riskCounter: nextNumber, updatedAt: Date.now() };
  await fmeaSave(updated);
  return { fmea: updated, risk: cloned };
}

async function syncFmeaRiskLinks(fmea, risk, prevRisk) {
  // Sorge dafür, dass Verknüpfungen bidirektional gepflegt bleiben (Reklamationen/CAPA)
  const riskNumber = (risk?.riskNumber || prevRisk?.riskNumber || '').toString();
  if (!riskNumber) return;

  const nextComplaints = new Set(risk?.linkedComplaints || []);
  const prevComplaints = new Set(prevRisk?.linkedComplaints || []);
  for (const ticket of nextComplaints) {
    const comp = await complaintGet(ticket).catch(() => null);
    if (!comp) continue;
    const list = Array.from(new Set([...(comp.fmeaRiskNumbers || []).map(String), riskNumber]));
    await complaintSave({ ...comp, fmeaRiskNumbers: list });
  }
  for (const ticket of prevComplaints) {
    if (nextComplaints.has(ticket)) continue;
    const comp = await complaintGet(ticket).catch(() => null);
    if (!comp) continue;
    const list = (comp.fmeaRiskNumbers || []).map(String).filter(n => n !== riskNumber);
    await complaintSave({ ...comp, fmeaRiskNumbers: list });
  }

  const nextCapas = new Set(risk?.linkedCapas || []);
  const prevCapas = new Set(prevRisk?.linkedCapas || []);
  for (const capaId of nextCapas) {
    const capa = await capaGet(capaId).catch(() => null);
    if (!capa) continue;
    const list = Array.from(new Set([...(capa.fmeaRiskNumbers || []).map(String), riskNumber]));
    await capaSave({ ...capa, fmeaRiskNumbers: list });
  }
  for (const capaId of prevCapas) {
    if (nextCapas.has(capaId)) continue;
    const capa = await capaGet(capaId).catch(() => null);
    if (!capa) continue;
    const list = (capa.fmeaRiskNumbers || []).map(String).filter(n => n !== riskNumber);
    await capaSave({ ...capa, fmeaRiskNumbers: list });
  }
}

/* =====================================================================
   AUDITS – Auditprogramm, Audits, Findings, Actions, Annual Reports
   ===================================================================== */

const AUDIT_TILE_ID = 'audits';

const KEY_AUDITOR = (id) => `${P}audit:auditor:${id}`;
const KEY_AUDITORS_INDEX = `${P}auditors:index`;
const KEY_AUDIT_PROGRAM = (id) => `${P}audit:program:${id}`;
const KEY_AUDIT_PROGRAMS_INDEX = `${P}audit:programs:index`;
const KEY_AUDIT_INDEX = `${P}audits:index`;
const LEGACY_KEY_AUDIT_INDEX = `${P}audit:index`;
const KEY_AUDIT = (id) => `${P}audit:${id}`;
const KEY_AUDIT_FINDING = (id) => `${P}audit:finding:${id}`;
const KEY_AUDIT_FINDINGS_INDEX = `${P}audit:findings:index`;
const KEY_AUDIT_ACTION = (id) => `${P}audit:action:${id}`;
const KEY_AUDIT_ACTIONS_INDEX = `${P}audit:actions:index`;
const KEY_AUDIT_REPORT = (id) => `${P}audit:annualReport:${id}`;
const KEY_AUDIT_REPORTS_INDEX = `${P}audit:annualReports:index`;
const KEY_AUDIT_COUNTERS = `${P}audit:counters`;
const KEY_AUDIT_COUNTER_YEAR = (year) => `${P}audit:counter:${year}`;
const KEY_AUDIT_PLAN = (id) => `${P}audit:${id}:plan`;
const LEGACY_KEY_AUDIT_PLAN = (id) => `${P}audit:plan:${id}`;

function isAuditObjectKey(key) {
  const keyStr = String(key || '');
  const auditPrefix = `${P}audit:`;
  return (
    keyStr.startsWith(auditPrefix) &&
    !keyStr.startsWith(`${P}audit:auditor:`) &&
    !keyStr.startsWith(`${P}audit:program:`) &&
    !keyStr.startsWith(`${P}audit:finding:`) &&
    !keyStr.startsWith(`${P}audit:action:`) &&
    !keyStr.startsWith(`${P}audit:annualReport:`) &&
    !keyStr.startsWith(KEY_AUDIT_COUNTERS) &&
    !keyStr.includes(':plan')
  );
}

// Redis previously acted as the primary store for auditors/audits which caused
// every PATCH/PUT to write fresh keys like dfs:audit:auditor:<uuid>. The UI
// sends full audit payloads, so each edit overwrote Redis with partially
// normalized auditor data and produced phantom auditors. To keep audit updates
// deterministic — and to fully retire the legacy audit persistence layer — we
// now disable all legacy audit/auditor Redis access by default. Only an
// explicit opt-in via environment variables will re-enable it.
// Legacy audit/auditor Redis access is hard-disabled to avoid unintended key creation.
const AUDITOR_REDIS_WRITE_ENABLED = false;
const AUDITOR_REDIS_READ_ENABLED = false;
const AUDIT_REDIS_ENABLED = false;
const AUDIT_CACHE_TTL_SECONDS = 0;

function getAuditRedisForRead() {
  if (!AUDIT_REDIS_ENABLED) return null;
  return getRedis();
}

function getAuditRedisForWrite() {
  if (!AUDIT_REDIS_ENABLED) return null;
  return getRedis();
}

function getAuditRedis() {
  return getAuditRedisForRead();
}

function getAuditorRedisForWrite() {
  if (!AUDITOR_REDIS_WRITE_ENABLED) return null;
  return getRedis();
}

function getAuditorRedisForRead() {
  if (!AUDITOR_REDIS_READ_ENABLED) return null;
  return getRedis();
}

let auditStoresHydrated = false;

function normalizeAuditIndex(raw) {
  if (Array.isArray(raw)) return raw.map((id) => id && id.toString()).filter(Boolean);
  if (typeof raw === 'string') {
    try {
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed)) return parsed.map((id) => id && id.toString()).filter(Boolean);
    } catch (_) {
      /* ignore */
    }
  }
  return [];
}

function currentAuditIndexIds() {
  ensureAuditStores();
  return Array.from(mem.auditIndex || new Set());
}

function currentAuditProgramIndexIds() {
  ensureAuditStores();
  return Array.from(mem.auditProgramIndex || new Set());
}

function currentAuditFindingIndexIds() {
  ensureAuditStores();
  return Array.from(mem.auditFindingIndex || new Set());
}

function currentAuditActionIndexIds() {
  ensureAuditStores();
  return Array.from(mem.auditActionIndex || new Set());
}

function currentAuditReportIndexIds() {
  ensureAuditStores();
  return Array.from(mem.auditReportIndex || new Set());
}

function currentAuditorIndexIds() {
  ensureAuditStores();
  return Array.from(mem.auditorIndex || new Set());
}

const AUDIT_FINDING_SEVERITY = {
  CONFORMITY: 'Konformität',
  HINT: 'Hinweis',
  MINOR: 'Minor',
  MAJOR: 'Major',
  CRITICAL: 'Critical',
};

function ensureAuditStores() {
  if (!mem.auditors) mem.auditors = new Map();
  if (!mem.auditorIndex) mem.auditorIndex = new Set();
  if (!mem.auditPrograms) mem.auditPrograms = new Map();
  if (!mem.auditProgramIndex) mem.auditProgramIndex = new Set();
  if (!mem.audits) mem.audits = new Map();
  if (!mem.auditIndex) mem.auditIndex = new Set();
  if (!mem.auditFindings) mem.auditFindings = new Map();
  if (!mem.auditFindingIndex) mem.auditFindingIndex = new Set();
  if (!mem.auditActions) mem.auditActions = new Map();
  if (!mem.auditActionIndex) mem.auditActionIndex = new Set();
  if (!mem.auditAnnualReports) mem.auditAnnualReports = new Map();
  if (!mem.auditReportIndex) mem.auditReportIndex = new Set();
  if (!mem.auditCounters) mem.auditCounters = {};
}

async function hydrateAuditStores() {
  auditStoresHydrated = true;
  const rAuditor = getAuditorRedisForRead();
  const r = getAuditRedisForRead();
  if (!rAuditor && !r) return;

  mem.auditors = new Map();
  mem.auditorIndex = new Set();
  mem.auditPrograms = new Map();
  mem.auditProgramIndex = new Set();
  mem.audits = new Map();
  mem.auditIndex = new Set();
  mem.auditFindings = new Map();
  mem.auditFindingIndex = new Set();
  mem.auditActions = new Map();
  mem.auditActionIndex = new Set();
  mem.auditAnnualReports = new Map();
  mem.auditReportIndex = new Set();

  const AUDITOR_PREFIX = `${P}audit:auditor:`;
  const PROGRAM_PREFIX = `${P}audit:program:`;
  const AUDIT_PREFIX = `${P}audit:`;
  const FINDING_PREFIX = `${P}audit:finding:`;
  const ACTION_PREFIX = `${P}audit:action:`;
  const REPORT_PREFIX = `${P}audit:annualReport:`;

  const [auditorIndexIds, programIndexIds, auditIndexIds, findingIndexIds, actionIndexIds, reportIndexIds, counters] =
    await Promise.all([
      rAuditor ? rsmembers(KEY_AUDITORS_INDEX, rAuditor) : [],
      r ? rsmembers(KEY_AUDIT_PROGRAMS_INDEX, r) : [],
      r ? rsmembers(KEY_AUDIT_INDEX, r) : [],
      r ? rsmembers(KEY_AUDIT_FINDINGS_INDEX, r) : [],
      r ? rsmembers(KEY_AUDIT_ACTIONS_INDEX, r) : [],
      r ? rsmembers(KEY_AUDIT_REPORTS_INDEX, r) : [],
      r ? rget(KEY_AUDIT_COUNTERS, r) : null,
    ]);

  const load = async (rclient, keys, normalize, target, deriveIdFromKey = null, trackIndexSet = null) => {
    for (const key of keys) {
      const raw = await rget(key, rclient);
      if (!raw || typeof raw !== 'object') continue;
      const record = { ...raw };
      if (!record.id && typeof deriveIdFromKey === 'function') {
        record.id = deriveIdFromKey(key);
      }
      const normalized = normalize(record);
      target.set(normalized.id, normalized);
      if (trackIndexSet) trackIndexSet.add(String(normalized.id));
    }
  };

  const idFromSuffix = (prefix) => (key) => (key.startsWith(prefix) ? key.slice(prefix.length) : undefined);

  const auditorIndexSet = new Set(normalizeAuditIndex(auditorIndexIds));
  mem.auditorIndex = auditorIndexSet;
  const auditorKeys = Array.from(auditorIndexSet).map(KEY_AUDITOR);
  await load(rAuditor, auditorKeys, normalizeAuditor, mem.auditors, idFromSuffix(AUDITOR_PREFIX), mem.auditorIndex);

  const programIndexSet = new Set(normalizeAuditIndex(programIndexIds));
  mem.auditProgramIndex = programIndexSet;
  let programKeys = Array.from(programIndexSet).map(KEY_AUDIT_PROGRAM);
  let programIndexFromScan = false;
  if (programKeys.length === 0 && r) {
    programKeys = await rkeys(`${P}audit:program:*`, r);
    programIndexFromScan = programKeys.length > 0;
  }
  await load(r, programKeys, normalizeAuditProgram, mem.auditPrograms, idFromSuffix(PROGRAM_PREFIX), mem.auditProgramIndex);
  if (programIndexFromScan) await persistAuditProgramIndex(r);

  const auditIndexSet = new Set(normalizeAuditIndex(auditIndexIds));
  const legacyIndexIds = auditIndexSet.size === 0 && r ? normalizeAuditIndex(await rget(LEGACY_KEY_AUDIT_INDEX, r)) : [];
  if (legacyIndexIds.length > 0) legacyIndexIds.forEach((id) => auditIndexSet.add(id));
  let auditIndexFromScan = false;
  if (auditIndexSet.size === 0 && r) {
    const idsFromKeys = await auditIdsFromRedisKeys();
    idsFromKeys.forEach((id) => auditIndexSet.add(id));
    auditIndexFromScan = idsFromKeys.length > 0;
  }

  const auditKeysFromIndex = Array.from(auditIndexSet).map(KEY_AUDIT);
  await load(r, auditKeysFromIndex, normalizeAudit, mem.audits, idFromSuffix(AUDIT_PREFIX), mem.auditIndex);
  mem.auditIndex = auditIndexSet;
  if (auditIndexFromScan || legacyIndexIds.length > 0) await persistAuditIndex(r);

  const findingIndexSet = new Set(normalizeAuditIndex(findingIndexIds));
  mem.auditFindingIndex = findingIndexSet;
  let findingKeys = Array.from(findingIndexSet).map(KEY_AUDIT_FINDING);
  let findingIndexFromScan = false;
  if (findingKeys.length === 0 && r) {
    findingKeys = await rkeys(`${P}audit:finding:*`, r);
    findingIndexFromScan = findingKeys.length > 0;
  }
  await load(r, findingKeys, normalizeFinding, mem.auditFindings, idFromSuffix(FINDING_PREFIX), mem.auditFindingIndex);
  if (findingIndexFromScan) await persistAuditFindingIndex(r);

  const actionIndexSet = new Set(normalizeAuditIndex(actionIndexIds));
  mem.auditActionIndex = actionIndexSet;
  let actionKeys = Array.from(actionIndexSet).map(KEY_AUDIT_ACTION);
  let actionIndexFromScan = false;
  if (actionKeys.length === 0 && r) {
    actionKeys = await rkeys(`${P}audit:action:*`, r);
    actionIndexFromScan = actionKeys.length > 0;
  }
  await load(r, actionKeys, normalizeAction, mem.auditActions, idFromSuffix(ACTION_PREFIX), mem.auditActionIndex);
  if (actionIndexFromScan) await persistAuditActionIndex(r);

  const reportIndexSet = new Set(normalizeAuditIndex(reportIndexIds));
  mem.auditReportIndex = reportIndexSet;
  let reportKeys = Array.from(reportIndexSet).map(KEY_AUDIT_REPORT);
  let reportIndexFromScan = false;
  if (reportKeys.length === 0 && r) {
    reportKeys = await rkeys(`${P}audit:annualReport:*`, r);
    reportIndexFromScan = reportKeys.length > 0;
  }
  await load(r, reportKeys, normalizeAnnualReport, mem.auditAnnualReports, idFromSuffix(REPORT_PREFIX), mem.auditReportIndex);
  if (reportIndexFromScan) await persistAuditReportIndex(r);

  if (counters && typeof counters === 'object') {
    mem.auditCounters = counters;
  }
}

async function hydrateAuditorsById(ids = []) {
  const rAuditor = getAuditorRedisForRead();
  if (!rAuditor || !Array.isArray(ids) || ids.length === 0) return;

  for (const id of ids.filter(Boolean)) {
    if (mem.auditorIndex && mem.auditorIndex.size > 0 && !mem.auditorIndex.has(id)) continue;
    if (mem.auditors.has(id)) continue;
    const raw = await rget(KEY_AUDITOR(id), rAuditor);
    if (!raw || typeof raw !== 'object') continue;
    const normalized = normalizeAuditor({ ...raw, id: raw.id || id });
    mem.auditors.set(normalized.id, normalized);
  }
}

async function ensureAuditStoresReady() {
  ensureAuditStores();
  if (!auditStoresHydrated) await hydrateAuditStores();
}

function addAuditToIndex(id) {
  if (!id) return;
  ensureAuditStores();
  mem.auditIndex.add(String(id));
}

function removeAuditFromIndex(id) {
  if (!id) return;
  ensureAuditStores();
  mem.auditIndex.delete(String(id));
}

function addAuditorToIndex(id) {
  if (!id) return;
  ensureAuditStores();
  mem.auditorIndex.add(String(id));
}

function removeAuditorFromIndex(id) {
  if (!id) return;
  ensureAuditStores();
  mem.auditorIndex.delete(String(id));
}

function addAuditProgramToIndex(id) {
  if (!id) return;
  ensureAuditStores();
  mem.auditProgramIndex.add(String(id));
}

function removeAuditProgramFromIndex(id) {
  if (!id) return;
  ensureAuditStores();
  mem.auditProgramIndex.delete(String(id));
}

function addAuditFindingToIndex(id) {
  if (!id) return;
  ensureAuditStores();
  mem.auditFindingIndex.add(String(id));
}

function removeAuditFindingFromIndex(id) {
  if (!id) return;
  ensureAuditStores();
  mem.auditFindingIndex.delete(String(id));
}

function addAuditActionToIndex(id) {
  if (!id) return;
  ensureAuditStores();
  mem.auditActionIndex.add(String(id));
}

function removeAuditActionFromIndex(id) {
  if (!id) return;
  ensureAuditStores();
  mem.auditActionIndex.delete(String(id));
}

function addAuditReportToIndex(id) {
  if (!id) return;
  ensureAuditStores();
  mem.auditReportIndex.add(String(id));
}

function removeAuditReportFromIndex(id) {
  if (!id) return;
  ensureAuditStores();
  mem.auditReportIndex.delete(String(id));
}

async function persistAuditIndex(rclient = null) {
  const r = rclient || getAuditRedisForWrite();
  if (!r) return;
  const ids = currentAuditIndexIds();
  await rdel(KEY_AUDIT_INDEX, r);
  if (ids.length > 0) {
    await rsadd(KEY_AUDIT_INDEX, ids, r);
  }
}

async function persistAuditProgramIndex(rclient = null) {
  const r = rclient || getAuditRedisForWrite();
  if (!r) return;
  const ids = currentAuditProgramIndexIds();
  await rdel(KEY_AUDIT_PROGRAMS_INDEX, r);
  if (ids.length > 0) {
    await rsadd(KEY_AUDIT_PROGRAMS_INDEX, ids, r);
  }
}

async function persistAuditFindingIndex(rclient = null) {
  const r = rclient || getAuditRedisForWrite();
  if (!r) return;
  const ids = currentAuditFindingIndexIds();
  await rdel(KEY_AUDIT_FINDINGS_INDEX, r);
  if (ids.length > 0) {
    await rsadd(KEY_AUDIT_FINDINGS_INDEX, ids, r);
  }
}

async function persistAuditActionIndex(rclient = null) {
  const r = rclient || getAuditRedisForWrite();
  if (!r) return;
  const ids = currentAuditActionIndexIds();
  await rdel(KEY_AUDIT_ACTIONS_INDEX, r);
  if (ids.length > 0) {
    await rsadd(KEY_AUDIT_ACTIONS_INDEX, ids, r);
  }
}

async function persistAuditReportIndex(rclient = null) {
  const r = rclient || getAuditRedisForWrite();
  if (!r) return;
  const ids = currentAuditReportIndexIds();
  await rdel(KEY_AUDIT_REPORTS_INDEX, r);
  if (ids.length > 0) {
    await rsadd(KEY_AUDIT_REPORTS_INDEX, ids, r);
  }
}

async function persistAuditorIndex(rclient = null) {
  const r = rclient || getAuditorRedisForWrite();
  if (!r) return;
  const ids = currentAuditorIndexIds();
  await rdel(KEY_AUDITORS_INDEX, r);
  if (ids.length > 0) {
    await rsadd(KEY_AUDITORS_INDEX, ids, r);
  }
}

function normalizeAuditString(value) {
  return (value ?? '').toString().trim();
}

function normalizeAuditId(value) {
  const id = normalizeAuditString(value);
  return id || null;
}

function normalizeAuditStringArray(arr) {
  return Array.isArray(arr)
    ? Array.from(new Set(arr.map(v => normalizeAuditString(v)).filter(Boolean)))
    : [];
}

function validationError(message, details = []) {
  const err = new Error(message);
  err.code = 'VALIDATION_ERROR';
  err.details = details;
  return err;
}

function parseDate(value) {
  if (!value) return null;
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return null;
  return d.toISOString();
}

function addDays(base, days) {
  const d = base ? new Date(base) : new Date();
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString();
}

function nowIso() {
  return new Date().toISOString();
}

function auditorQualificationState(auditor) {
  const q = auditor?.qualifications || {};
  const hasTraining = !!q.internalAuditorTrainingDate;
  const experienceYears = Number(q.experienceYears || 0);
  const hasOverride = q.override === true || q.qualificationOverride === true;
  const dueDateIso = q.requalificationDueDate ? new Date(q.requalificationDueDate) : null;
  const overdue = dueDateIso ? dueDateIso.getTime() < Date.now() : false;
  const qualified = Boolean(hasTraining && (experienceYears >= 3 || hasOverride) && !overdue);
  return { qualified, overdue, hasTraining, hasOverride, experienceYears };
}

export function isAuditorQualified(auditor, { allowOverride = true } = {}) {
  const { qualified, hasOverride } = auditorQualificationState(auditor);
  if (qualified) return true;
  if (!allowOverride && hasOverride) return false;
  return false;
}

function auditorConflictsWithScope(auditor, audit) {
  const restrictedOrgUnits = normalizeAuditStringArray(auditor?.independenceRules?.restrictedOrgUnits);
  const restrictedProcessOwners = normalizeAuditStringArray(auditor?.independenceRules?.restrictedProcessOwners);
  const scopeOrgUnits = normalizeAuditStringArray(audit?.auditeesOrgUnits);
  const processOwners = normalizeAuditStringArray(audit?.processOwners);
  if (auditor?.orgUnit && audit?.orgUnit && normalizeAuditString(auditor.orgUnit) === normalizeAuditString(audit.orgUnit)) {
    return `Auditor ${auditor.name || auditor.id} darf Audit des eigenen Bereichs nicht durchführen`;
  }

  const conflictOrg = scopeOrgUnits.find(org => restrictedOrgUnits.includes(org));
  if (conflictOrg) return `Konflikt mit Organisationsbereich ${conflictOrg}`;
  const conflictProcess = processOwners.find(po => restrictedProcessOwners.includes(po));
  if (conflictProcess) return `Konflikt mit Prozessverantwortung ${conflictProcess}`;
  return null;
}

function formatAuditNumber(yearString, counter) {
  return `IA-${yearString}-${String(counter).padStart(2, '0')}`;
}

function isAuditNumberValid(value) {
  if (!value || typeof value !== 'string') return false;
  return /^IA-\d{2}-\d{2}$/.test(value.trim());
}

async function nextAuditNumber(year) {
  const y = String(year || new Date().getFullYear()).slice(-2);
  let counter = null;
  const r = getAuditRedisForWrite();
  if (r) {
    try {
      const redisCounter = await rincr(KEY_AUDIT_COUNTER_YEAR(y), r);
      if (typeof redisCounter === 'number') counter = redisCounter;
    } catch (err) {
      console.error('audit counter redis incr failed', err);
    }
  }

  if (counter == null) {
    if (!mem.auditCounters[y]) mem.auditCounters[y] = 0;
    counter = mem.auditCounters[y] + 1;
  }

  mem.auditCounters[y] = counter;

  if (r) rset(KEY_AUDIT_COUNTERS, mem.auditCounters);

  return formatAuditNumber(y, counter);
}

function applyAuditNumber(audit) {
  if (audit.auditNumber) return audit.auditNumber;
  if (audit.auditNo) return audit.auditNo;
  const year = audit?.plannedStart ? new Date(audit.plannedStart).getFullYear() : new Date().getFullYear();
  return formatAuditNumber(String(year).slice(-2), (mem.auditCounters[String(year).slice(-2)] || 0) + 1);
}

function normalizeAuditor(record = {}) {
  const now = nowIso();
  const q = record.qualifications || {};
  const standardsKnowledge = Array.isArray(q.standardsKnowledge) ? q.standardsKnowledge.filter(Boolean) : [];
  if (record.standardsIso13485) standardsKnowledge.push('ISO13485');
  if (record.standardsIso19011) standardsKnowledge.push('ISO19011');
  if (record.standardsMdr) standardsKnowledge.push('MDR');
  const coAuditCount = Number(q.coAuditCount ?? record.coAuditCount ?? 0) || 0;
  const leadAuditCount = Number(q.leadAuditCount ?? record.leadAuditCount ?? 0) || 0;
  const requalificationDueDate = q.requalificationDueDate || record.requalificationDueDate;
  const experienceYears = Number(q.experienceYears ?? record.experienceYears ?? 0) || 0;
  const trainingDate = q.trainingDate || q.internalAuditorTrainingDate || record.trainingDate;
  const evidence = Array.isArray(q.evidence)
    ? q.evidence.filter(Boolean)
    : Array.isArray(record.evidenceAttachments)
        ? record.evidenceAttachments.filter(Boolean)
        : [];
  const normalized = {
    id: record.id || crypto.randomUUID(),
    userId: record.userId || null,
    name: normalizeAuditString(record.name),
    email: normalizeAuditString(record.email),
    orgUnit: normalizeAuditString(record.orgUnit || record.orgUnitOrDepartment || record.department),
    role: normalizeAuditString(record.role || 'Lead'),
    status: normalizeAuditString(record.status || 'active'),
    qualifications: {
      ...q,
      trainingType: q.trainingType || record.trainingType || 'internal',
      trainingDate: parseDate(trainingDate),
      internalAuditorTrainingDate: parseDate(q.internalAuditorTrainingDate || record.internalAuditorTrainingDate || trainingDate),
      experienceYears,
      coAuditCount,
      leadAuditCount,
      requalificationDueDate: parseDate(requalificationDueDate),
      standardsKnowledge: Array.from(new Set(standardsKnowledge)),
      evidence,
    },
    independenceRules: {
      restrictedProcessOwners: normalizeAuditStringArray(record?.independenceRules?.restrictedProcessOwners),
      restrictedOrgUnits: normalizeAuditStringArray(record?.independenceRules?.restrictedOrgUnits),
      notes: normalizeAuditString(record?.independenceRules?.notes),
    },
    createdAt: record.createdAt || now,
    updatedAt: now,
    createdBy: record.createdBy || record.updatedBy,
    updatedBy: record.updatedBy,
  };
  return normalized;
}

function normalizeAuditProgram(record = {}) {
  const now = nowIso();
  return {
    id: record.id || crypto.randomUUID(),
    year: Number(record.year || new Date().getFullYear()),
    title: normalizeAuditString(record.title || `Auditprogramm ${record.year || new Date().getFullYear()}`),
    status: record.status || 'draft',
    approvedBy: normalizeAuditString(record.approvedBy),
    approvedAt: record.approvedAt ? parseDate(record.approvedAt) : null,
    clusters: Array.isArray(record.clusters) && record.clusters.length ? record.clusters : ['Q1', 'Q2', 'Q3', 'Q4'],
    createdAt: record.createdAt || now,
    updatedAt: now,
    createdBy: record.createdBy || record.updatedBy,
    updatedBy: record.updatedBy,
  };
}

function normalizeAudit(record = {}) {
  const validationIssues = [];

  const leadCandidates = [];
  if ('leadAuditorId' in record) leadCandidates.push(record.leadAuditorId);
  if ('leadAuditor' in record) {
    const lead = record.leadAuditor;
    if (lead && typeof lead === 'object') {
      if (lead.id) leadCandidates.push(lead.id);
      else
        validationIssues.push({ field: 'leadAuditor.id', issue: 'required', message: 'leadAuditor.id erforderlich' });
    } else if (lead) {
      leadCandidates.push(lead);
    }
  }
  const normalizedLead = leadCandidates.map(normalizeAuditId).filter(Boolean);
  const uniqueLead = Array.from(new Set(normalizedLead));
  if (uniqueLead.length > 1) {
    validationIssues.push({
      field: 'leadAuditorId',
      issue: 'conflict',
      message: 'Lead Auditor widersprüchlich (leadAuditor vs leadAuditorId)',
      values: uniqueLead,
    });
  }
  const leadAuditorId = uniqueLead[0] || null;

  const coAuditorIdsRaw = [];
  if (Array.isArray(record.coAuditorIds)) coAuditorIdsRaw.push(...record.coAuditorIds);
  if (Array.isArray(record.coAuditors)) {
    for (const co of record.coAuditors) {
      if (co && typeof co === 'object') {
        if (co.id) coAuditorIdsRaw.push(co.id);
        else validationIssues.push({ field: 'coAuditors[].id', issue: 'required', message: 'Co-Auditor ohne ID' });
      } else if (co) {
        coAuditorIdsRaw.push(co);
      }
    }
  }
  if (record.coAuditor) coAuditorIdsRaw.push(record.coAuditor);
  const coAuditorIds = normalizeAuditStringArray(coAuditorIdsRaw);

  if (validationIssues.length) {
    throw validationError(
      validationIssues.map(d => d.message || `${d.field || 'validation'} invalid`).join('; '),
      validationIssues,
    );
  }

  const now = nowIso();
  const programId = record.programId || null;
  const planEntries = Array.isArray(record.planEntries || record.plan)
      ? (record.planEntries || record.plan).map(normalizeAuditPlanEntry)
      : [];
  const auditNumber = record.auditNumber || record.auditNo || applyAuditNumber(record);
  const normalized = {
    id: record.id || crypto.randomUUID(),
    programId,
    auditNumber,
    auditNo: record.auditNo || auditNumber,
    cluster: normalizeAuditString(record.cluster || 'Q1'),
    auditType: normalizeAuditString(record.auditType || 'System'),
    title: normalizeAuditString(record.title || record.auditName),
    site: normalizeAuditString(record.site || record.location),
    orgUnit: normalizeAuditString(record.orgUnit),
    plannedStart: parseDate(record.plannedStart),
    plannedEnd: parseDate(record.plannedEnd),
    actualStart: parseDate(record.actualStart),
    actualEnd: parseDate(record.actualEnd),
    duration: record.duration || null,
    scopeText: normalizeAuditString(record.scopeText),
    objectives: normalizeAuditStringArray(record.objectives),
    criteria: normalizeAuditStringArray(record.criteria),
    references: normalizeAuditStringArray(record.references),
    auditeesOrgUnits: normalizeAuditStringArray(record.auditeesOrgUnits),
    processOwners: normalizeAuditStringArray(record.processOwners),
    participants: normalizeAuditStringArray(record.participants),
    leadAuditorId,
    coAuditorIds,
    planEntries,
    status: record.status || 'planned',
    riskPriority: record.riskPriority || null,
    linkedDocs: Array.isArray(record.linkedDocs) ? record.linkedDocs : [],
    attachments: Array.isArray(record.attachments) ? record.attachments : [],
    createdAt: record.createdAt || now,
    updatedAt: now,
    createdBy: record.createdBy || record.updatedBy,
    updatedBy: record.updatedBy,
  };
  return normalized;
}

function normalizeAuditPlanEntry(entry = {}) {
  return {
    from: normalizeAuditString(entry.from),
    to: normalizeAuditString(entry.to),
    agenda: normalizeAuditString(entry.agenda),
    process: normalizeAuditString(entry.process),
    participants: normalizeAuditString(entry.participants),
    auditor: normalizeAuditString(entry.auditor),
    auditorId: normalizeAuditId(entry.auditorId),
    reference: normalizeAuditString(entry.reference || entry.norm || entry.standard || entry.normReference),
    notes: normalizeAuditString(entry.notes),
    done: entry.done === true,
  };
}

function normalizeFinding(record = {}) {
  const now = nowIso();
  return {
    id: record.id || crypto.randomUUID(),
    auditId: record.auditId,
    type: record.type || AUDIT_FINDING_SEVERITY.HINT,
    requirementRef: normalizeAuditString(record.requirementRef),
    description: normalizeAuditString(record.description),
    evidenceText: normalizeAuditString(record.evidenceText),
    linkedComplaintIds: normalizeAuditStringArray(record.linkedComplaintIds),
    linkedCapaIds: normalizeAuditStringArray(record.linkedCapaIds),
    ownerOrgUnit: normalizeAuditString(record.ownerOrgUnit || record.processOwner),
    createdInMeeting: normalizeAuditString(record.createdInMeeting),
    status: record.status || 'open',
    createdAt: record.createdAt || now,
    updatedAt: now,
    createdBy: record.createdBy || record.updatedBy,
    updatedBy: record.updatedBy,
  };
}

function normalizeAction(record = {}) {
  const now = nowIso();
  return {
    id: record.id || crypto.randomUUID(),
    auditId: record.auditId,
    findingId: record.findingId || null,
    actionType: record.actionType || 'Korrektur',
    description: normalizeAuditString(record.description),
    responsibleUserId: normalizeAuditString(record.responsibleUserId),
    responsibleOrgUnit: normalizeAuditString(record.responsibleOrgUnit),
    dueDate: record.dueDate ? parseDate(record.dueDate) : null,
    completedAt: record.completedAt ? parseDate(record.completedAt) : null,
    effectivenessCheckRequired: record.effectivenessCheckRequired ?? false,
    effectivenessCheckMethod: normalizeAuditString(record.effectivenessCheckMethod),
    effectivenessCheckedAt: record.effectivenessCheckedAt ? parseDate(record.effectivenessCheckedAt) : null,
    effectivenessResult: record.effectivenessResult || null,
    escalationLevel: record.escalationLevel || 'none',
    escalationReason: normalizeAuditString(record.escalationReason),
    status: record.status || 'open',
    createdAt: record.createdAt || now,
    updatedAt: now,
    createdBy: record.createdBy || record.updatedBy,
    updatedBy: record.updatedBy,
  };
}

function normalizeAnnualReport(record = {}) {
  const now = nowIso();
  return {
    id: record.id || crypto.randomUUID(),
    year: Number(record.year || new Date().getFullYear()),
    generatedAt: record.generatedAt ? parseDate(record.generatedAt) : now,
    generatedBy: normalizeAuditString(record.generatedBy),
    contentSnapshot: record.contentSnapshot || {},
    kpisSnapshot: record.kpisSnapshot || {},
    exportFiles: Array.isArray(record.exportFiles) ? record.exportFiles : [],
    signOff: record.signOff || null,
    createdAt: record.createdAt || now,
    updatedAt: now,
    createdBy: record.createdBy || record.updatedBy,
    updatedBy: record.updatedBy,
  };
}

function validateAuditorAssignments(audit) {
  const details = [];
  if (!audit.leadAuditorId) {
    details.push({ field: 'leadAuditorId', issue: 'required', message: 'Lead Auditor erforderlich' });
  }
  const lead = audit.leadAuditorId ? mem.auditors.get(audit.leadAuditorId) : null;
  if (audit.leadAuditorId && !lead) {
    details.push({
      field: 'leadAuditorId',
      issue: 'notFound',
      message: 'Lead Auditor nicht gefunden',
      value: audit.leadAuditorId,
    });
  }
  if (lead) {
    if (!isAuditorQualified(lead))
      details.push({ field: 'leadAuditorId', issue: 'qualification', message: 'Lead Auditor nicht qualifiziert' });
    const conflict = auditorConflictsWithScope(lead, audit);
    if (conflict) details.push({ field: 'leadAuditorId', issue: 'conflict', message: `Lead Auditor Konflikt: ${conflict}` });
  }
  for (const coId of audit.coAuditorIds || []) {
    if (!coId) {
      details.push({ field: 'coAuditorIds', issue: 'empty', message: 'Leerer Co-Auditor-Eintrag nicht erlaubt' });
      continue;
    }
    const co = mem.auditors.get(coId);
    if (!co) {
      details.push({ field: 'coAuditorIds', issue: 'notFound', message: `Co-Auditor ${coId} nicht gefunden`, value: coId });
      continue;
    }
    if (!isAuditorQualified(co))
      details.push({ field: 'coAuditorIds', issue: 'qualification', message: `Co-Auditor ${co.name || coId} nicht qualifiziert` });
    const conflict = auditorConflictsWithScope(co, audit);
    if (conflict) details.push({ field: 'coAuditorIds', issue: 'conflict', message: `Co-Auditor Konflikt: ${conflict}` });
  }
  return details;
}

function defaultDueDateForFinding(findingType, audit) {
  const anchor = audit?.plannedEnd || audit?.plannedStart || nowIso();
  if (findingType === AUDIT_FINDING_SEVERITY.CRITICAL) return addDays(anchor, 7);
  if (findingType === AUDIT_FINDING_SEVERITY.MAJOR) return addDays(anchor, 90);
  if (findingType === AUDIT_FINDING_SEVERITY.MINOR) return addDays(anchor, 120);
  return null;
}

function escalateLevelForFinding(findingType) {
  if (findingType === AUDIT_FINDING_SEVERITY.CRITICAL) return 'prrc';
  if (findingType === AUDIT_FINDING_SEVERITY.MAJOR) return 'qm';
  return 'none';
}

function markActionOverdue(action) {
  if (!action?.dueDate) return action;
  const due = new Date(action.dueDate).getTime();
  const nowTs = Date.now();
  if (due < nowTs && !['done', 'closed'].includes(action.status)) {
    return { ...action, status: action.status === 'ineffective' ? 'ineffective' : 'overdue' };
  }
  return action;
}

function shouldTriggerNachaudit(findings, actions) {
  const severeFinding = (findings || []).some(f => [AUDIT_FINDING_SEVERITY.MAJOR, AUDIT_FINDING_SEVERITY.CRITICAL].includes(f?.type));
  if (severeFinding) return true;
  return (actions || []).some(a => ['overdue', 'ineffective'].includes(a?.status));
}

function auditDocumentationComplete(audit, findings, actions) {
  if (!audit.leadAuditorId) return false;
  if (!audit.plannedStart || !audit.plannedEnd) return false;
  if (!audit.scopeText) return false;
  if (!findings || findings.length === 0) return false;
  const openActions = (actions || []).filter(a => !['done', 'closed'].includes(a.status));
  return openActions.length === 0;
}

export async function auditorAll() {
  await ensureAuditStoresReady();
  const ids = currentAuditorIndexIds();
  return ids.map((id) => mem.auditors.get(id)).filter(Boolean);
}

export async function auditorSave(record = {}, { persist = false } = {}) {
  await ensureAuditStoresReady();
  const normalized = normalizeAuditor(record);
  mem.auditors.set(normalized.id, normalized);
  addAuditorToIndex(normalized.id);
  if (persist) throw new Error('legacy audit persistence disabled');
  return normalized;
}

export async function auditorUpdate(id, patch = {}, { persist = false } = {}) {
  await ensureAuditStoresReady();
  const current = mem.auditors.get(id);
  if (!current) return null;
  const merged = normalizeAuditor({ ...current, ...patch, id });
  mem.auditors.set(id, merged);
  addAuditorToIndex(id);
  if (persist) throw new Error('legacy audit persistence disabled');
  return merged;
}

export async function auditorDelete(id, { persist = false } = {}) {
  await ensureAuditStoresReady();
  for (const audit of mem.audits.values()) {
    const lead = audit.leadAuditorId === id ? null : audit.leadAuditorId;
    const coAuditorIds = (audit.coAuditorIds || []).filter(co => co !== id);
    if (lead !== audit.leadAuditorId || coAuditorIds.length !== (audit.coAuditorIds || []).length) {
      await saveAuditInternal({ ...audit, leadAuditorId: lead, coAuditorIds }, { skipValidation: true });
    }
  }
  const deleted = mem.auditors.delete(id);
  removeAuditorFromIndex(id);
  if (persist) throw new Error('legacy audit persistence disabled');
  return deleted;
}

export async function auditProgramAll() {
  await ensureAuditStoresReady();
  const ids = currentAuditProgramIndexIds();
  return ids.map((id) => mem.auditPrograms.get(id)).filter(Boolean);
}

export async function auditProgramSave(record = {}) {
  await ensureAuditStoresReady();
  const normalized = normalizeAuditProgram(record);
  mem.auditPrograms.set(normalized.id, normalized);
  addAuditProgramToIndex(normalized.id);
  const r = getAuditRedisForWrite();
  if (r) {
    await rset(KEY_AUDIT_PROGRAM(normalized.id), normalized);
    await persistAuditProgramIndex(r);
  }
  return normalized;
}

export async function auditProgramUpdate(id, patch = {}) {
  await ensureAuditStoresReady();
  const current = mem.auditPrograms.get(id);
  if (!current) return null;
  const merged = normalizeAuditProgram({ ...current, ...patch, id });
  mem.auditPrograms.set(id, merged);
  addAuditProgramToIndex(id);
  const r = getAuditRedisForWrite();
  if (r) {
    await rset(KEY_AUDIT_PROGRAM(id), merged);
    await persistAuditProgramIndex(r);
  }
  return merged;
}

export async function auditProgramDelete(id) {
  await ensureAuditStoresReady();
  mem.auditPrograms.delete(id);
  const r = getAuditRedisForWrite();
  if (r) await rdel(KEY_AUDIT_PROGRAM(id));
  removeAuditProgramFromIndex(id);
  if (r) await persistAuditProgramIndex(r);
  const auditIdsToDelete = Array.from(mem.audits.values())
    .filter((audit) => audit.programId === id)
    .map((audit) => audit.id);
  for (const auditId of auditIdsToDelete) {
    await auditDelete(auditId);
  }
  await persistAuditIndex(r);
}

export async function auditAll(filter = {}) {
  await ensureAuditStoresReady();
  const indexIds = currentAuditIndexIds();
  let list = indexIds.map((id) => mem.audits.get(id)).filter(Boolean);
  if (filter.programId) list = list.filter(a => a.programId === filter.programId);
  if (filter.cluster) list = list.filter(a => a.cluster === filter.cluster);
  if (filter.status) list = list.filter(a => a.status === filter.status);
  return list;
}

export async function auditGet(id) {
  await ensureAuditStoresReady();
  if (mem.auditIndex && mem.auditIndex.size > 0 && !mem.auditIndex.has(String(id))) return null;
  return mem.audits.get(id) || null;
}

export async function auditPlanGet(id) {
  await ensureAuditStoresReady();
  const planKey = KEY_AUDIT_PLAN(id);
  const legacyPlanKey = LEGACY_KEY_AUDIT_PLAN(id);
  const r = getAuditRedis();

  if (r) {
    const fromRedis = await rget(planKey, r);
    if (Array.isArray(fromRedis)) {
      return { planEntries: fromRedis.map(normalizeAuditPlanEntry), found: true, planKey };
    }
    const fromLegacyRedis = await rget(legacyPlanKey, r);
    if (Array.isArray(fromLegacyRedis)) {
      return { planEntries: fromLegacyRedis.map(normalizeAuditPlanEntry), found: true, planKey: legacyPlanKey };
    }
  }
  return { planEntries: [], found: false, planKey };
}

async function saveAuditInternal(record = {}, { skipValidation = false } = {}) {
  await ensureAuditStoresReady();
  const normalized = normalizeAudit(record);
  const auditorIdsToHydrate = [normalized.leadAuditorId, ...(normalized.coAuditorIds || [])].filter(Boolean);
  if (auditorIdsToHydrate.length) await hydrateAuditorsById(auditorIdsToHydrate);
  const validationErrors = skipValidation ? [] : validateAuditorAssignments(normalized);
  if (!skipValidation && validationErrors.length > 0) {
    throw validationError(
      validationErrors.map(v => v.message || v.issue || 'validation error').join('; '),
      validationErrors,
    );
  }
  mem.audits.set(normalized.id, normalized);
  const r = getAuditRedisForWrite();
  if (r) await rset(KEY_AUDIT(normalized.id), normalized);
  return normalized;
}

export async function auditSave(record = {}) {
  const plannedYear = record?.plannedStart ? new Date(record.plannedStart).getFullYear() : new Date().getFullYear();
  const providedNumbers = [record.auditNumber, record.auditNo].filter(isAuditNumberValid);
  const existingAuditNumber = providedNumbers[0] || null;

  const auditNumber = existingAuditNumber || (await nextAuditNumber(plannedYear));
  const auditNo = isAuditNumberValid(record.auditNo) ? record.auditNo.trim() : auditNumber;

  const saved = await saveAuditInternal({ ...record, auditNumber, auditNo });
  addAuditToIndex(saved.id);
  await persistAuditIndex();
  return saved;
}

export async function auditUpdate(id, patch = {}) {
  const current = await auditGet(id);
  if (!current) return null;
  const { auditNumber: _auditNumber, auditNo: _auditNo, ...rest } = patch || {};
  return await saveAuditInternal({ ...current, ...rest, id, auditNumber: current.auditNumber, auditNo: current.auditNo });
}

export async function auditPlanSave(id, planEntries = [], { updatedBy } = {}) {
  const planKey = KEY_AUDIT_PLAN(id);
  const current = await auditGet(id);
  if (!current) return { planEntries: null, planKey };

  const normalizedPlan = Array.isArray(planEntries) ? planEntries.map(normalizeAuditPlanEntry) : [];
  const r = getAuditRedisForWrite();
  if (r) {
    await rset(planKey, normalizedPlan, r);
    await rdel(LEGACY_KEY_AUDIT_PLAN(id), r);
  }

  const updated = await saveAuditInternal(
    { ...current, planEntries: normalizedPlan, updatedBy: updatedBy || current.updatedBy },
    { skipValidation: true },
  );

  return { planEntries: updated?.planEntries || normalizedPlan, planKey };
}

export async function auditDelete(id) {
  await ensureAuditStoresReady();
  mem.audits.delete(id);
  const r = getAuditRedisForWrite();
  if (r) {
    await rdel(KEY_AUDIT(id));
    await rdel(KEY_AUDIT_PLAN(id));
    await rdel(LEGACY_KEY_AUDIT_PLAN(id));
  }
  removeAuditFromIndex(id);
  await persistAuditIndex(r);
  const removedFindingIds = [];
  for (const [fid, finding] of mem.auditFindings.entries()) {
    if (finding.auditId === id) {
      mem.auditFindings.delete(fid);
      removeAuditFindingFromIndex(fid);
      if (r) await rdel(KEY_AUDIT_FINDING(fid));
      removedFindingIds.push(fid);
    }
  }
  if (removedFindingIds.length > 0) await persistAuditFindingIndex(r);
  const removedActionIds = [];
  for (const [aid, action] of mem.auditActions.entries()) {
    if (action.auditId === id) {
      mem.auditActions.delete(aid);
      removeAuditActionFromIndex(aid);
      if (r) await rdel(KEY_AUDIT_ACTION(aid));
      removedActionIds.push(aid);
    }
  }
  if (removedActionIds.length > 0) await persistAuditActionIndex(r);
}

export async function auditIndexReadOnly() {
  await ensureAuditStoresReady();
  return currentAuditIndexIds();
}

async function auditIdsFromRedisKeys() {
  const r = getAuditRedisForRead();
  if (!r) return [];
  const auditPrefix = `${P}audit:`;
  const keys = await rkeys(`${auditPrefix}*`, r);
  return keys.filter(isAuditObjectKey).map((key) => key.slice(auditPrefix.length));
}

export async function auditFindUnindexed() {
  const r = getAuditRedisForRead();
  const indexFromRedis = r ? normalizeAuditIndex(await rsmembers(KEY_AUDIT_INDEX, r)) : [];
  const canonicalIndex = new Set(indexFromRedis.length > 0 ? indexFromRedis : currentAuditIndexIds());
  const idsFromKeys = await auditIdsFromRedisKeys();
  return idsFromKeys.filter((id) => !canonicalIndex.has(id));
}

export async function auditDeleteUnindexed({ dryRun = true } = {}) {
  const r = getAuditRedisForWrite();
  const candidates = await auditFindUnindexed();
  const removed = [];
  if (!dryRun && r) {
    for (const auditId of candidates) {
      await rdel(KEY_AUDIT(auditId), r);
      await rdel(KEY_AUDIT_PLAN(auditId), r);
      await rdel(LEGACY_KEY_AUDIT_PLAN(auditId), r);
      removed.push(auditId);
    }
  }
  return { candidates, removed, dryRun };
}

export async function auditFindingAll(filter = {}) {
  await ensureAuditStoresReady();
  let list = currentAuditFindingIndexIds().map((id) => mem.auditFindings.get(id)).filter(Boolean);
  if (filter.auditId) list = list.filter(f => f.auditId === filter.auditId);
  return list;
}

export async function auditFindingSave(record = {}) {
  await ensureAuditStoresReady();
  if (!record.auditId) throw new Error('auditId missing');
  const audit = await auditGet(record.auditId);
  if (!audit) throw new Error('audit not found');
  const normalized = normalizeFinding(record);
  mem.auditFindings.set(normalized.id, normalized);
  const r = getAuditRedisForWrite();
  addAuditFindingToIndex(normalized.id);
  if (r) {
    await rset(KEY_AUDIT_FINDING(normalized.id), normalized);
    await persistAuditFindingIndex(r);
  }
  await updateAuditStatusAfterChange(audit.id);
  return normalized;
}

export async function auditFindingUpdate(id, patch = {}) {
  await ensureAuditStoresReady();
  const current = mem.auditFindings.get(id);
  if (!current) return null;
  const merged = normalizeFinding({ ...current, ...patch, id });
  mem.auditFindings.set(id, merged);
  const r = getAuditRedisForWrite();
  addAuditFindingToIndex(id);
  if (r) {
    await rset(KEY_AUDIT_FINDING(id), merged);
    await persistAuditFindingIndex(r);
  }
  await updateAuditStatusAfterChange(merged.auditId);
  return merged;
}

export async function auditFindingDelete(id) {
  await ensureAuditStoresReady();
  const current = mem.auditFindings.get(id);
  mem.auditFindings.delete(id);
  const r = getAuditRedisForWrite();
  removeAuditFindingFromIndex(id);
  if (r) {
    await rdel(KEY_AUDIT_FINDING(id));
    await persistAuditFindingIndex(r);
  }
  if (current) await updateAuditStatusAfterChange(current.auditId);
}

export async function auditActionAll(filter = {}) {
  await ensureAuditStoresReady();
  let list = currentAuditActionIndexIds().map((id) => mem.auditActions.get(id)).filter(Boolean);
  if (filter.auditId) list = list.filter(a => a.auditId === filter.auditId);
  if (filter.findingId) list = list.filter(a => a.findingId === filter.findingId);
  return list.map(markActionOverdue);
}

async function applyActionDefaults(record) {
  const audit = record.auditId ? await auditGet(record.auditId) : null;
  const finding = record.findingId ? mem.auditFindings.get(record.findingId) : null;
  const normalized = normalizeAction(record);
  const severity = finding?.type;
  if (!normalized.dueDate && severity) {
    normalized.dueDate = defaultDueDateForFinding(severity, audit);
  }
  if (!normalized.escalationLevel && severity) {
    normalized.escalationLevel = escalateLevelForFinding(severity);
  }
  if (severity === AUDIT_FINDING_SEVERITY.CRITICAL) {
    normalized.effectivenessCheckRequired = true;
  }
  return markActionOverdue(normalized);
}

export async function auditActionSave(record = {}) {
  await ensureAuditStoresReady();
  if (!record.auditId) throw new Error('auditId missing');
  const normalized = await applyActionDefaults(record);
  mem.auditActions.set(normalized.id, normalized);
  const r = getAuditRedisForWrite();
  addAuditActionToIndex(normalized.id);
  if (r) {
    await rset(KEY_AUDIT_ACTION(normalized.id), normalized);
    await persistAuditActionIndex(r);
  }
  await updateAuditStatusAfterChange(normalized.auditId);
  return normalized;
}

export async function auditActionUpdate(id, patch = {}) {
  await ensureAuditStoresReady();
  const current = mem.auditActions.get(id);
  if (!current) return null;
  const merged = await applyActionDefaults({ ...current, ...patch, id });
  mem.auditActions.set(id, merged);
  const r = getAuditRedisForWrite();
  addAuditActionToIndex(id);
  if (r) {
    await rset(KEY_AUDIT_ACTION(id), merged);
    await persistAuditActionIndex(r);
  }
  await updateAuditStatusAfterChange(merged.auditId);
  return merged;
}

export async function auditActionDelete(id) {
  await ensureAuditStoresReady();
  const current = mem.auditActions.get(id);
  mem.auditActions.delete(id);
  const r = getAuditRedisForWrite();
  removeAuditActionFromIndex(id);
  if (r) {
    await rdel(KEY_AUDIT_ACTION(id));
    await persistAuditActionIndex(r);
  }
  if (current) await updateAuditStatusAfterChange(current.auditId);
}

export async function auditAnnualReportAll(filter = {}) {
  await ensureAuditStoresReady();
  let list = currentAuditReportIndexIds().map((id) => mem.auditAnnualReports.get(id)).filter(Boolean);
  if (filter.year) list = list.filter(r => Number(r.year) === Number(filter.year));
  return list;
}

export async function auditAnnualReportSave(record = {}) {
  await ensureAuditStoresReady();
  const normalized = normalizeAnnualReport(record);
  mem.auditAnnualReports.set(normalized.id, normalized);
  const r = getAuditRedisForWrite();
  addAuditReportToIndex(normalized.id);
  if (r) {
    await rset(KEY_AUDIT_REPORT(normalized.id), normalized);
    await persistAuditReportIndex(r);
  }
  return normalized;
}

async function updateAuditStatusAfterChange(auditId) {
  const audit = await auditGet(auditId);
  if (!audit) return null;
  const findings = await auditFindingAll({ auditId });
  const actions = await auditActionAll({ auditId });
  const needsNachaudit = shouldTriggerNachaudit(findings, actions);
  let nextStatus = audit.status;
  if (needsNachaudit) nextStatus = 'nachauditRequired';
  if (audit.status === 'closed' && !auditDocumentationComplete(audit, findings, actions)) {
    nextStatus = 'inProgress';
  }
  if (nextStatus !== audit.status) {
    await saveAuditInternal({ ...audit, status: nextStatus }, { skipValidation: true });
  }
  return nextStatus;
}

export { AUDIT_TILE_ID, AUDIT_FINDING_SEVERITY };

/* =====================================================================
   SUPPLIER EVALUATION – Stammdaten, Performance, Bewertungen, Eskalation
   ===================================================================== */

const KEY_SUPPLIER_INDEX = `${P}supplier:index`;
const KEY_SUPPLIER = (id) => `${P}supplier:${id}`;
const KEY_SUPPLIER_PERF_INDEX = `${P}supplierPerf:index`;
const KEY_SUPPLIER_PERF = (id) => `${P}supplierPerf:${id}`;
const KEY_SUPPLIER_EVAL_INDEX = `${P}supplierEval:index`;
const KEY_SUPPLIER_EVAL = (id) => `${P}supplierEval:${id}`;
const KEY_SUPPLIER_ESC_INDEX = `${P}supplierEsc:index`;
const KEY_SUPPLIER_ESC = (id) => `${P}supplierEsc:${id}`;
const KEY_SUPPLIER_EVAL_CONFIG = `${P}supplierEvalConfig:default`;
const KEY_SUPPLIER_LOOKUPS = `${P}supplierLookups:default`;

function ensureSupplierStores() {
  if (!mem.suppliers) mem.suppliers = new Map();
  if (!mem.supplierIndex) mem.supplierIndex = new Set();
  if (!mem.supplierLookups) mem.supplierLookups = null;
  if (!mem.supplierPerformance) mem.supplierPerformance = new Map();
  if (!mem.supplierPerformanceIndex) mem.supplierPerformanceIndex = new Set();
  if (!mem.supplierEvaluations) mem.supplierEvaluations = new Map();
  if (!mem.supplierEvaluationIndex) mem.supplierEvaluationIndex = new Set();
  if (!mem.supplierEscalations) mem.supplierEscalations = new Map();
  if (!mem.supplierEscalationIndex) mem.supplierEscalationIndex = new Set();
}

function normalizeSupplierStatus(status) {
  const value = normalizeString(status).toLowerCase();
  if (['zugelassen', 'approved', 'active'].includes(value)) return 'zugelassen';
  if (['gesperrt', 'blocked', 'locked'].includes(value)) return 'gesperrt';
  if (['in bewertung', 'in_bewertung', 'review', 'evaluation'].includes(value)) return 'in bewertung';
  return 'zugelassen';
}

function normalizeSupplierRecord(record = {}) {
  const now = Date.now();
  const base = { ...record };
  const id = normalizeString(base.id || base.supplierId || base.supplier_id || crypto.randomUUID());
  base.id = id;
  base.supplierId = id;
  base.supplierNumber = normalizeString(base.supplierNumber || base.supplierNo || base.number || '');
  base.name = normalizeString(base.name || base.company || base.firma || '');
  base.address = normalizeString(base.address || '');
  base.contactName = normalizeString(base.contactName || base.contact || '');
  base.contactEmail = normalizeString(base.contactEmail || '');
  base.contactPhone = normalizeString(base.contactPhone || '');
  base.website = normalizeString(base.website || '');
  base.country = normalizeString(base.country || '');
  base.category = normalizeString(base.category || base.goodsGroup || '');
  base.critical = base.critical === true || base.critical === 'true' || base.critical === 1;
  base.status = normalizeSupplierStatus(base.status);
  base.notes = normalizeString(base.notes || '');
  base.blockedReason = normalizeString(base.blockedReason || '');
  base.blockedAt = normalizeDateValue(base.blockedAt) || null;
  base.blockedBy = normalizeString(base.blockedBy || '');
  base.createdAt = normalizeDateValue(base.createdAt) || now;
  base.updatedAt = normalizeDateValue(base.updatedAt) || now;
  base.createdBy = normalizeString(base.createdBy || '');
  base.updatedBy = normalizeString(base.updatedBy || '');
  base.history = Array.isArray(base.history) ? base.history : [];
  return base;
}

function normalizePerformanceRecord(record = {}) {
  const now = Date.now();
  const base = { ...record };
  const id = normalizeString(base.id || base.entryId || crypto.randomUUID());
  base.id = id;
  base.entryId = id;
  base.supplierId = normalizeString(base.supplierId || '');
  base.date = normalizeDateValue(base.date) || now;
  base.type = normalizeString(base.type || '');
  base.rating = normalizeString(base.rating || '');
  base.description = normalizeString(base.description || '');
  base.reference = normalizeString(base.reference || '');
  base.attachments = normalizeArray(base.attachments);
  base.includeInAnnual = base.includeInAnnual !== false;
  base.status = normalizeString(base.status || 'open');
  base.cancelReason = normalizeString(base.cancelReason || '');
  base.createdAt = normalizeDateValue(base.createdAt) || now;
  base.updatedAt = normalizeDateValue(base.updatedAt) || now;
  base.createdBy = normalizeString(base.createdBy || '');
  base.updatedBy = normalizeString(base.updatedBy || '');
  base.history = Array.isArray(base.history) ? base.history : [];
  return base;
}

function normalizeSupplierEvaluationRecord(record = {}) {
  const now = Date.now();
  const base = { ...record };
  const id = normalizeString(base.id || base.evalId || crypto.randomUUID());
  base.id = id;
  base.evalId = id;
  base.evalYear = Number(base.evalYear || base.year || now && new Date(now).getFullYear());
  base.periodFrom = normalizeDateValue(base.periodFrom) || null;
  base.periodTo = normalizeDateValue(base.periodTo) || null;
  base.supplierId = normalizeString(base.supplierId || '');
  base.aggregates = base.aggregates && typeof base.aggregates === 'object' ? base.aggregates : {};
  base.commentEk = normalizeString(base.commentEk || '');
  base.commentQm = normalizeString(base.commentQm || '');
  base.decision = normalizeString(base.decision || '');
  base.decisionReason = normalizeString(base.decisionReason || '');
  base.status = normalizeString(base.status || 'draft');
  base.configVersion = Number(base.configVersion || 1);
  base.configSnapshot = base.configSnapshot && typeof base.configSnapshot === 'object' ? base.configSnapshot : {};
  base.createdAt = normalizeDateValue(base.createdAt) || now;
  base.updatedAt = normalizeDateValue(base.updatedAt) || now;
  base.createdBy = normalizeString(base.createdBy || '');
  base.updatedBy = normalizeString(base.updatedBy || '');
  base.reviewedBy = normalizeString(base.reviewedBy || '');
  base.approvedBy = normalizeString(base.approvedBy || '');
  base.history = Array.isArray(base.history) ? base.history : [];
  return base;
}

function normalizeSupplierEscalationRecord(record = {}) {
  const now = Date.now();
  const base = { ...record };
  const id = normalizeString(base.id || base.escalationId || crypto.randomUUID());
  base.id = id;
  base.escalationId = id;
  base.supplierId = normalizeString(base.supplierId || '');
  base.trigger = normalizeString(base.trigger || '');
  base.reason = normalizeString(base.reason || '');
  base.severity = normalizeString(base.severity || 'mittel');
  base.status = normalizeString(base.status || 'offen');
  base.owner = normalizeString(base.owner || '');
  base.dueDate = normalizeDateValue(base.dueDate) || null;
  base.links = base.links && typeof base.links === 'object' ? base.links : {};
  base.actions = normalizeString(base.actions || base.measures || '');
  base.effectiveness = normalizeString(base.effectiveness || '');
  base.createdAt = normalizeDateValue(base.createdAt) || now;
  base.updatedAt = normalizeDateValue(base.updatedAt) || now;
  base.createdBy = normalizeString(base.createdBy || '');
  base.updatedBy = normalizeString(base.updatedBy || '');
  base.history = Array.isArray(base.history) ? base.history : [];
  return base;
}

function defaultSupplierEvalConfig() {
  return {
    id: 'default',
    version: 1,
    categories: [
      {
        name: 'Qualität',
        weight: 40,
        scale: ['1', '2', '3', '4', '5'],
        scoreMap: { '1': 1, '2': 2, '3': 3, '4': 4, '5': 5 },
      },
      {
        name: 'Termintreue',
        weight: 30,
        scale: ['1', '2', '3', '4', '5'],
        scoreMap: { '1': 1, '2': 2, '3': 3, '4': 4, '5': 5 },
      },
      {
        name: 'Dokumentation',
        weight: 20,
        scale: ['1', '2', '3', '4', '5'],
        scoreMap: { '1': 1, '2': 2, '3': 3, '4': 4, '5': 5 },
      },
      {
        name: 'Service',
        weight: 10,
        scale: ['1', '2', '3', '4', '5'],
        scoreMap: { '1': 1, '2': 2, '3': 3, '4': 4, '5': 5 },
      },
    ],
    thresholds: {
      green: 4,
      yellow: 3,
      red: 2,
      escalationScore: 2,
    },
    trend: {
      windowDays: 90,
      minEntries: 3,
    },
    annualWindow: {
      defaultRange: 'previousYear',
      startMonths: [1, 2, 3],
    },
    approval: {
      allowedRoles: ['qm'],
    },
    editRules: {
      entryEditDays: 7,
    },
    notifications: {
      recipients: ['qm'],
      reminderDays: 7,
      emails: [],
    },
    updatedAt: Date.now(),
    updatedBy: '',
    history: [],
  };
}

function defaultSupplierLookups() {
  return {
    id: 'default',
    categories: [],
    countries: [],
    statuses: ['zugelassen', 'in bewertung', 'gesperrt'],
    updatedAt: Date.now(),
    updatedBy: '',
    history: [],
  };
}

function normalizeSupplierLookups(lookups = {}) {
  const base = lookups && typeof lookups === 'object' ? { ...lookups } : {};
  const defaults = defaultSupplierLookups();
  const merged = {
    ...defaults,
    ...base,
  };
  merged.id = 'default';
  merged.categories = normalizeArray(merged.categories).map((e) => normalizeString(e)).filter(Boolean);
  merged.countries = normalizeArray(merged.countries).map((e) => normalizeString(e)).filter(Boolean);
  merged.statuses = defaults.statuses;
  merged.updatedAt = normalizeDateValue(merged.updatedAt) || Date.now();
  merged.updatedBy = normalizeString(merged.updatedBy || '');
  merged.history = Array.isArray(merged.history) ? merged.history : [];
  return merged;
}

function normalizeSupplierEvalConfig(config = {}) {
  const base = config && typeof config === 'object' ? { ...config } : {};
  const defaultConfig = defaultSupplierEvalConfig();
  const merged = {
    ...defaultConfig,
    ...base,
  };
  merged.id = 'default';
  merged.version = Number(merged.version || 1);
  merged.categories = Array.isArray(merged.categories) ? merged.categories : defaultConfig.categories;
  merged.thresholds = merged.thresholds && typeof merged.thresholds === 'object' ? merged.thresholds : defaultConfig.thresholds;
  merged.trend = merged.trend && typeof merged.trend === 'object' ? merged.trend : defaultConfig.trend;
  merged.annualWindow = merged.annualWindow && typeof merged.annualWindow === 'object' ? merged.annualWindow : defaultConfig.annualWindow;
  merged.approval = merged.approval && typeof merged.approval === 'object' ? merged.approval : defaultConfig.approval;
  merged.editRules = merged.editRules && typeof merged.editRules === 'object' ? merged.editRules : defaultConfig.editRules;
  merged.notifications =
    merged.notifications && typeof merged.notifications === 'object' ? merged.notifications : defaultConfig.notifications;
  merged.updatedAt = normalizeDateValue(merged.updatedAt) || Date.now();
  merged.updatedBy = normalizeString(merged.updatedBy || '');
  merged.history = Array.isArray(merged.history) ? merged.history : [];
  return merged;
}

async function supplierIndexIds() {
  ensureSupplierStores();
  return Array.from(mem.supplierIndex || new Set());
}

async function supplierPerfIndexIds() {
  ensureSupplierStores();
  return Array.from(mem.supplierPerformanceIndex || new Set());
}

async function supplierEvalIndexIds() {
  ensureSupplierStores();
  return Array.from(mem.supplierEvaluationIndex || new Set());
}

async function supplierEscIndexIds() {
  ensureSupplierStores();
  return Array.from(mem.supplierEscalationIndex || new Set());
}

function addSupplierIndex(id) {
  if (!id) return;
  ensureSupplierStores();
  mem.supplierIndex.add(String(id));
}

function removeSupplierIndex(id) {
  if (!id) return;
  ensureSupplierStores();
  mem.supplierIndex.delete(String(id));
}

function addSupplierPerfIndex(id) {
  if (!id) return;
  ensureSupplierStores();
  mem.supplierPerformanceIndex.add(String(id));
}

function removeSupplierPerfIndex(id) {
  if (!id) return;
  ensureSupplierStores();
  mem.supplierPerformanceIndex.delete(String(id));
}

function addSupplierEvalIndex(id) {
  if (!id) return;
  ensureSupplierStores();
  mem.supplierEvaluationIndex.add(String(id));
}

function removeSupplierEvalIndex(id) {
  if (!id) return;
  ensureSupplierStores();
  mem.supplierEvaluationIndex.delete(String(id));
}

function addSupplierEscIndex(id) {
  if (!id) return;
  ensureSupplierStores();
  mem.supplierEscalationIndex.add(String(id));
}

function removeSupplierEscIndex(id) {
  if (!id) return;
  ensureSupplierStores();
  mem.supplierEscalationIndex.delete(String(id));
}

async function persistSupplierIndex(rclient = null) {
  const r = rclient || getRedis();
  if (!r) return;
  const ids = await supplierIndexIds();
  await rdel(KEY_SUPPLIER_INDEX, r);
  if (ids.length) await rsadd(KEY_SUPPLIER_INDEX, ids, r);
}

async function persistSupplierPerfIndex(rclient = null) {
  const r = rclient || getRedis();
  if (!r) return;
  const ids = await supplierPerfIndexIds();
  await rdel(KEY_SUPPLIER_PERF_INDEX, r);
  if (ids.length) await rsadd(KEY_SUPPLIER_PERF_INDEX, ids, r);
}

async function persistSupplierEvalIndex(rclient = null) {
  const r = rclient || getRedis();
  if (!r) return;
  const ids = await supplierEvalIndexIds();
  await rdel(KEY_SUPPLIER_EVAL_INDEX, r);
  if (ids.length) await rsadd(KEY_SUPPLIER_EVAL_INDEX, ids, r);
}

async function persistSupplierEscIndex(rclient = null) {
  const r = rclient || getRedis();
  if (!r) return;
  const ids = await supplierEscIndexIds();
  await rdel(KEY_SUPPLIER_ESC_INDEX, r);
  if (ids.length) await rsadd(KEY_SUPPLIER_ESC_INDEX, ids, r);
}

export async function supplierAll() {
  ensureSupplierStores();
  const r = getRedis();
  if (r) {
    const ids = await rsmembers(KEY_SUPPLIER_INDEX, r);
    const list = [];
    for (const id of ids || []) {
      const raw = await rget(KEY_SUPPLIER(id), r);
      if (!raw || typeof raw !== 'object') continue;
      list.push(normalizeSupplierRecord({ ...raw, id }));
    }
    list.sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0));
    return list;
  }
  const list = Array.from(mem.suppliers.values()).map((s) => normalizeSupplierRecord(s));
  list.sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0));
  return list;
}

export async function supplierGet(id) {
  if (!id) return null;
  ensureSupplierStores();
  const r = getRedis();
  const raw = r ? await rget(KEY_SUPPLIER(id), r) : mem.suppliers.get(id);
  return raw ? normalizeSupplierRecord({ ...raw, id }) : null;
}

export async function supplierSave(record = {}) {
  const normalized = normalizeSupplierRecord(record);
  ensureSupplierStores();
  mem.suppliers.set(normalized.id, normalized);
  addSupplierIndex(normalized.id);
  const r = getRedis();
  if (r) {
    await rset(KEY_SUPPLIER(normalized.id), normalized);
    await persistSupplierIndex(r);
  }
  return normalized;
}

export async function supplierUpdate(id, patch = {}) {
  const current = await supplierGet(id);
  if (!current) return null;
  const updated = normalizeSupplierRecord({ ...current, ...patch, id, updatedAt: Date.now() });
  return supplierSave(updated);
}

export async function supplierDelete(id) {
  if (!id) return false;
  ensureSupplierStores();
  mem.suppliers.delete(id);
  removeSupplierIndex(id);
  const r = getRedis();
  if (r) {
    await rdel(KEY_SUPPLIER(id), r);
    await persistSupplierIndex(r);
  }
  return true;
}

export async function supplierPerformanceAll(filter = {}) {
  ensureSupplierStores();
  const r = getRedis();
  const filterSupplierId = normalizeString(filter.supplierId || '');
  if (r) {
    const ids = await rsmembers(KEY_SUPPLIER_PERF_INDEX, r);
    const list = [];
    for (const id of ids || []) {
      const raw = await rget(KEY_SUPPLIER_PERF(id), r);
      if (!raw || typeof raw !== 'object') continue;
      const normalized = normalizePerformanceRecord({ ...raw, id });
      if (filterSupplierId && normalized.supplierId !== filterSupplierId) continue;
      list.push(normalized);
    }
    list.sort((a, b) => (b.date || 0) - (a.date || 0));
    return list;
  }
  const list = Array.from(mem.supplierPerformance.values()).map((p) => normalizePerformanceRecord(p));
  const filtered = filterSupplierId ? list.filter((p) => p.supplierId === filterSupplierId) : list;
  filtered.sort((a, b) => (b.date || 0) - (a.date || 0));
  return filtered;
}

export async function supplierPerformanceGet(id) {
  if (!id) return null;
  ensureSupplierStores();
  const r = getRedis();
  const raw = r ? await rget(KEY_SUPPLIER_PERF(id), r) : mem.supplierPerformance.get(id);
  return raw ? normalizePerformanceRecord({ ...raw, id }) : null;
}

export async function supplierPerformanceSave(record = {}) {
  const normalized = normalizePerformanceRecord(record);
  ensureSupplierStores();
  mem.supplierPerformance.set(normalized.id, normalized);
  addSupplierPerfIndex(normalized.id);
  const r = getRedis();
  if (r) {
    await rset(KEY_SUPPLIER_PERF(normalized.id), normalized);
    await persistSupplierPerfIndex(r);
  }
  return normalized;
}

export async function supplierPerformanceUpdate(id, patch = {}) {
  const current = await supplierPerformanceGet(id);
  if (!current) return null;
  const updated = normalizePerformanceRecord({ ...current, ...patch, id, updatedAt: Date.now() });
  return supplierPerformanceSave(updated);
}

export async function supplierPerformanceDelete(id) {
  if (!id) return false;
  ensureSupplierStores();
  mem.supplierPerformance.delete(id);
  removeSupplierPerfIndex(id);
  const r = getRedis();
  if (r) {
    await rdel(KEY_SUPPLIER_PERF(id), r);
    await persistSupplierPerfIndex(r);
  }
  return true;
}

export async function supplierEvaluationAll(filter = {}) {
  ensureSupplierStores();
  const r = getRedis();
  const filterSupplierId = normalizeString(filter.supplierId || '');
  if (r) {
    const ids = await rsmembers(KEY_SUPPLIER_EVAL_INDEX, r);
    const list = [];
    for (const id of ids || []) {
      const raw = await rget(KEY_SUPPLIER_EVAL(id), r);
      if (!raw || typeof raw !== 'object') continue;
      const normalized = normalizeSupplierEvaluationRecord({ ...raw, id });
      if (filterSupplierId && normalized.supplierId !== filterSupplierId) continue;
      list.push(normalized);
    }
    list.sort((a, b) => (b.evalYear || 0) - (a.evalYear || 0));
    return list;
  }
  const list = Array.from(mem.supplierEvaluations.values()).map((e) => normalizeSupplierEvaluationRecord(e));
  const filtered = filterSupplierId ? list.filter((e) => e.supplierId === filterSupplierId) : list;
  filtered.sort((a, b) => (b.evalYear || 0) - (a.evalYear || 0));
  return filtered;
}

export async function supplierEvaluationGet(id) {
  if (!id) return null;
  ensureSupplierStores();
  const r = getRedis();
  const raw = r ? await rget(KEY_SUPPLIER_EVAL(id), r) : mem.supplierEvaluations.get(id);
  return raw ? normalizeSupplierEvaluationRecord({ ...raw, id }) : null;
}

export async function supplierEvaluationSave(record = {}) {
  const normalized = normalizeSupplierEvaluationRecord(record);
  ensureSupplierStores();
  mem.supplierEvaluations.set(normalized.id, normalized);
  addSupplierEvalIndex(normalized.id);
  const r = getRedis();
  if (r) {
    await rset(KEY_SUPPLIER_EVAL(normalized.id), normalized);
    await persistSupplierEvalIndex(r);
  }
  return normalized;
}

export async function supplierEvaluationUpdate(id, patch = {}) {
  const current = await supplierEvaluationGet(id);
  if (!current) return null;
  const updated = normalizeSupplierEvaluationRecord({ ...current, ...patch, id, updatedAt: Date.now() });
  return supplierEvaluationSave(updated);
}

export async function supplierEvaluationDelete(id) {
  if (!id) return false;
  ensureSupplierStores();
  mem.supplierEvaluations.delete(id);
  removeSupplierEvalIndex(id);
  const r = getRedis();
  if (r) {
    await rdel(KEY_SUPPLIER_EVAL(id), r);
    await persistSupplierEvalIndex(r);
  }
  return true;
}

export async function supplierEscalationAll(filter = {}) {
  ensureSupplierStores();
  const r = getRedis();
  const filterSupplierId = normalizeString(filter.supplierId || '');
  if (r) {
    const ids = await rsmembers(KEY_SUPPLIER_ESC_INDEX, r);
    const list = [];
    for (const id of ids || []) {
      const raw = await rget(KEY_SUPPLIER_ESC(id), r);
      if (!raw || typeof raw !== 'object') continue;
      const normalized = normalizeSupplierEscalationRecord({ ...raw, id });
      if (filterSupplierId && normalized.supplierId !== filterSupplierId) continue;
      list.push(normalized);
    }
    list.sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0));
    return list;
  }
  const list = Array.from(mem.supplierEscalations.values()).map((e) => normalizeSupplierEscalationRecord(e));
  const filtered = filterSupplierId ? list.filter((e) => e.supplierId === filterSupplierId) : list;
  filtered.sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0));
  return filtered;
}

export async function supplierEscalationGet(id) {
  if (!id) return null;
  ensureSupplierStores();
  const r = getRedis();
  const raw = r ? await rget(KEY_SUPPLIER_ESC(id), r) : mem.supplierEscalations.get(id);
  return raw ? normalizeSupplierEscalationRecord({ ...raw, id }) : null;
}

export async function supplierEscalationSave(record = {}) {
  const normalized = normalizeSupplierEscalationRecord(record);
  ensureSupplierStores();
  mem.supplierEscalations.set(normalized.id, normalized);
  addSupplierEscIndex(normalized.id);
  const r = getRedis();
  if (r) {
    await rset(KEY_SUPPLIER_ESC(normalized.id), normalized);
    await persistSupplierEscIndex(r);
  }
  return normalized;
}

export async function supplierEscalationUpdate(id, patch = {}) {
  const current = await supplierEscalationGet(id);
  if (!current) return null;
  const updated = normalizeSupplierEscalationRecord({ ...current, ...patch, id, updatedAt: Date.now() });
  return supplierEscalationSave(updated);
}

export async function supplierEscalationDelete(id) {
  if (!id) return false;
  ensureSupplierStores();
  mem.supplierEscalations.delete(id);
  removeSupplierEscIndex(id);
  const r = getRedis();
  if (r) {
    await rdel(KEY_SUPPLIER_ESC(id), r);
    await persistSupplierEscIndex(r);
  }
  return true;
}

export async function supplierEvalConfigGet() {
  const r = getRedis();
  if (r) {
    const raw = await rget(KEY_SUPPLIER_EVAL_CONFIG, r);
    if (raw && typeof raw === 'object') return normalizeSupplierEvalConfig(raw);
  }
  if (mem.supplierEvalConfig) return normalizeSupplierEvalConfig(mem.supplierEvalConfig);
  const fallback = normalizeSupplierEvalConfig({});
  mem.supplierEvalConfig = fallback;
  return fallback;
}

export async function supplierEvalConfigSave(input = {}, { updatedBy = '' } = {}) {
  const current = await supplierEvalConfigGet();
  const nextVersion = current.version + 1;
  const historyEntry = {
    version: current.version,
    updatedAt: current.updatedAt,
    updatedBy: current.updatedBy,
    snapshot: current,
  };
  const merged = normalizeSupplierEvalConfig({
    ...current,
    ...input,
    version: nextVersion,
    updatedAt: Date.now(),
    updatedBy,
    history: [...(current.history || []), historyEntry],
  });
  mem.supplierEvalConfig = merged;
  const r = getRedis();
  if (r) {
    await rset(KEY_SUPPLIER_EVAL_CONFIG, merged, r);
  }
  return merged;
}

export async function supplierLookupsGet() {
  const r = getRedis();
  if (r) {
    const raw = await rget(KEY_SUPPLIER_LOOKUPS, r);
    if (raw && typeof raw === 'object') return normalizeSupplierLookups(raw);
  }
  if (mem.supplierLookups) return normalizeSupplierLookups(mem.supplierLookups);
  const fallback = normalizeSupplierLookups({});
  mem.supplierLookups = fallback;
  return fallback;
}

export async function supplierLookupsSave(input = {}, { updatedBy = '' } = {}) {
  const current = await supplierLookupsGet();
  const merged = normalizeSupplierLookups({
    ...current,
    ...input,
    updatedAt: Date.now(),
    updatedBy,
    history: [
      ...(current.history || []),
      { updatedAt: current.updatedAt, updatedBy: current.updatedBy, snapshot: current },
    ],
  });
  mem.supplierLookups = merged;
  const r = getRedis();
  if (r) {
    await rset(KEY_SUPPLIER_LOOKUPS, merged, r);
  }
  return merged;
}
