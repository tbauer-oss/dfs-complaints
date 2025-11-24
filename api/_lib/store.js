// =======================================================
// api/_lib/store.js  (ESM) – DFS Complaints Backend
// =======================================================
import { Redis } from '@upstash/redis';
import { loadRepByEmail, loadRepById, repCustomers } from './repsStore.js';

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

let _redis = null;
function getRedis() {
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

// ===== In-Memory Fallback (Preview / Dev) =====
const mem = {
  users: new Map(),
  pending: new Map(),
  complaints: new Map(),
  counters: { ticket: 1 },
  catalogConfig: {},
  repPushTokens: new Map(),
  adminPushTokens: [],
  gateCodes: new Map(),
  customerNews: [],
  faqCategories: [],
  faqItems: [],
};

const SUPPORTED_LANGS = new Set(['de', 'en', 'fr', 'it', 'es']);
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
};

function normalizeLangValue(value) {
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
  'general',
];
export const CUSTOMER_NEWS_CATEGORY_CODES = [...NEWS_CATEGORY_CODES];
const FAQ_AUDIENCE_CODES = ['customer', 'rep', 'both'];
const KEY_FAQ_CATEGORIES = `${P}faq:categories`;
const KEY_FAQ_ITEMS = `${P}faq:items`;
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
async function rget(k) {
  try {
    const r = getRedis();
    if (!r) return null;
    return await withRedisTimeout(r.get(k), `KV GET ${k}`);
  } catch (e) {
    console.error('KV GET', k, e);
    return null;
  }
}
async function rset(k, v) {
  try {
    const r = getRedis();
    if (!r) return null;
    return await withRedisTimeout(r.set(k, v), `KV SET ${k}`);
  } catch (e) {
    console.error('KV SET', k, e);
    return null;
  }
}
async function rdel(k) {
  try {
    const r = getRedis();
    if (!r) return null;
    return await withRedisTimeout(r.del(k), `KV DEL ${k}`);
  } catch (e) {
    console.error('KV DEL', k, e);
    return null;
  }
}

// ===== Key-Scan kompatibel zu Upstash =====
async function rkeys(pattern) {
  const r = getRedis();
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
  const r = getRedis();
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

  const r = getRedis();
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
  const r = getRedis();
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
  const r = getRedis();
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
  };
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
  const title = _text(raw.title ?? raw.name ?? '', 200);
  if (!id || !title) return null;
  const description = _text(raw.description ?? '', 2000);
  return {
    id,
    title,
    description: description || null,
    order: _orderValue(raw.order, 0),
    active: raw.active === undefined ? true : Boolean(raw.active),
  };
}

function _normalizeStoredFaqEntry(raw, categories) {
  if (!raw || typeof raw !== 'object') return null;
  const id = (raw.id ?? '').toString().trim();
  const categoryId = (raw.categoryId ?? '').toString().trim();
  const question = _text(raw.question ?? '', 500);
  const answer = _text(raw.answer ?? '', 8000);
  if (!id || !categoryId || !question || !answer) return null;

  if (Array.isArray(categories) && categories.length > 0) {
    const exists = categories.some((cat) => cat.id === categoryId);
    if (!exists) return null;
  }

  const createdAt = _parseTs(raw.createdAt, Date.now());
  const updatedAt = _parseTs(raw.updatedAt, createdAt);

  return {
    id,
    categoryId,
    question,
    answer,
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
  const title = _text(input.title ?? input.name ?? base.title ?? '', 200);
  if (!title) throw new Error('title required');
  const description = _text(input.description ?? base.description ?? '', 2000);

  return {
    id:
      (input.id ?? base.id ?? '').toString().trim() ||
      `faq_cat_${now}_${Math.random().toString(36).slice(2, 8)}`,
    title,
    description: description || null,
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

  const question = _text(input.question ?? base.question ?? '', 500);
  const answer = _text(input.answer ?? base.answer ?? '', 8000);
  if (!question || !answer) throw new Error('question and answer required');

  return {
    id:
      (input.id ?? base.id ?? '').toString().trim() ||
      `faq_${now}_${Math.random().toString(36).slice(2, 8)}`,
    categoryId,
    question,
    answer,
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
export async function userByEmail(email) {
  if (!email) return null;
  const key = `${P}user:${String(email).toLowerCase()}`;
  const r = getRedis();
  const raw = r ? await rget(key) : mem.users.get(String(email).toLowerCase()) ?? null;
  if (raw && typeof raw === 'object') {
    const normalized = normalizePushTokens(raw.pushTokens);
    if (normalized.length > 0) raw.pushTokens = normalized; else delete raw.pushTokens;
    raw.lang = normLang(raw.lang || '');
  }
  return raw;
}

export async function userSave(u) {
  const email = String(u?.email || '').toLowerCase();
  if (!email) return false;
  const key = `${P}user:${email}`;
  const r = getRedis();
  const toSave = { ...u, email };
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
  if (r) {
    const keys = await rkeys(`${P}user:*`);
    const vals = await Promise.all(keys.map(k => rget(k)));
    return vals
      .filter(Boolean)
      .map(u => {
        if (u && typeof u === 'object') {
          const normalized = normalizePushTokens(u.pushTokens);
          if (normalized.length > 0) u.pushTokens = normalized; else delete u.pushTokens;
          u.lang = normLang(u.lang || '');
        }
        return u;
      });
  }
  return Array.from(mem.users.values());
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

export async function complaintSave(c) {
  if (!c?.ticket) c.ticket = await nextTicket();
  const key = `${P}complaint:${c.ticket}`;
  const r = getRedis();
  if (r) await rset(key, c); else mem.complaints.set(c.ticket, c);
  return c;
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
  await complaintSave(updated);
  return updated;
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

  return {
    kind: 'rep',
    repId: rep.id,
    email: rep.email || mail,
    name: `${rep.firstName || ''} ${rep.lastName || ''}`.trim(),
    region: rep.region || '',
    customers: customers || [],
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
