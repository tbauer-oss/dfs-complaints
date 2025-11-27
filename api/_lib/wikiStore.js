// api/_lib/wikiStore.js
import { Redis } from '@upstash/redis';
import { wikiSeedArticles, wikiSeedCategories } from './wikiSeeds.js';
import { normalizeLangValue } from './store.js';

const redisUrl =
  process.env.REDIS_URL ||
  process.env.UPSTASH_REDIS_REST_URL ||
  process.env.KV_REST_API_URL ||
  '';
const redisToken =
  process.env.REDIS_TOKEN ||
  process.env.UPSTASH_REDIS_REST_TOKEN ||
  process.env.KV_REST_API_TOKEN ||
  '';

const REDIS_TIMEOUT_MS = Math.max(0, Number(process.env.REDIS_TIMEOUT_MS || 2500));
const redis = redisUrl && redisToken ? new Redis({ url: redisUrl, token: redisToken }) : null;

const PFX = 'dfs:wiki:';
const KEY_CATEGORIES = `${PFX}categories`;
const KEY_ARTICLES = `${PFX}articles`;

const mem = {
  categories: [],
  articles: [],
};

async function redisWithTimeout(promise, label = 'redis op') {
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

async function rget(key) {
  try {
    if (!redis) return null;
    return await redisWithTimeout(redis.get(key), `KV GET ${key}`);
  } catch (e) {
    console.error('[wikiStore] KV GET failed', e);
    return null;
  }
}

async function rset(key, value) {
  try {
    if (!redis) return null;
    return await redisWithTimeout(redis.set(key, value), `KV SET ${key}`);
  } catch (e) {
    console.error('[wikiStore] KV SET failed', e);
    return null;
  }
}

function normalizeId(prefix) {
  const now = Date.now();
  return `${prefix}${now}_${Math.random().toString(36).slice(2, 8)}`;
}

function normalizeDate(value, fallback) {
  const d = value instanceof Date ? value : new Date(value || fallback || Date.now());
  if (Number.isNaN(d.getTime())) return new Date();
  return d;
}

function normalizeCategory(payload, existing = null) {
  const now = Date.now();
  const id = (payload?.id ?? existing?.id ?? '').toString().trim() || normalizeId('wiki_cat_');
  const name = (payload?.name ?? existing?.name ?? '').toString().trim();
  const description = (payload?.description ?? existing?.description ?? '').toString();
  const nameIntl = normalizeIntlMap(payload?.nameIntl ?? existing?.nameIntl);
  const descriptionIntl = normalizeIntlMap(payload?.descriptionIntl ?? existing?.descriptionIntl);
  const icon = (payload?.icon ?? existing?.icon ?? '').toString().trim();
  const sortOrderRaw = Number(payload?.sortOrder ?? existing?.sortOrder ?? 0);
  const sortOrder = Number.isFinite(sortOrderRaw) ? sortOrderRaw : 0;
  const isActive = (payload?.isActive ?? existing?.isActive ?? true) === true;
  return {
    id,
    name,
    description,
    nameIntl,
    descriptionIntl,
    icon,
    sortOrder,
    isActive,
  };
}

function normalizeArticle(payload, existing = null) {
  const now = Date.now();
  const id = (payload?.id ?? existing?.id ?? '').toString().trim() || normalizeId('wiki_art_');
  const categoryId = (payload?.categoryId ?? existing?.categoryId ?? '').toString().trim();
  const productGroups = Array.isArray(payload?.productGroups)
    ? payload.productGroups.map((p) => p.toString().trim()).filter(Boolean)
    : Array.isArray(existing?.productGroups)
      ? existing.productGroups
      : [];
  const type = (payload?.type ?? existing?.type ?? 'faq').toString().trim();
  const title = (payload?.title ?? existing?.title ?? '').toString();
  const teaser = (payload?.teaser ?? existing?.teaser ?? '').toString();
  const titleIntl = normalizeIntlMap(payload?.titleIntl ?? existing?.titleIntl);
  const teaserIntl = normalizeIntlMap(payload?.teaserIntl ?? existing?.teaserIntl);
  const importance = (payload?.importance ?? existing?.importance ?? 'normal').toString().trim();
  const contentMarkdown = (payload?.contentMarkdown ?? existing?.contentMarkdown ?? '').toString();
  const contentIntl = normalizeIntlMap(payload?.contentIntl ?? existing?.contentIntl);
  const tags = Array.isArray(payload?.tags)
    ? payload.tags.map((t) => t.toString().trim()).filter(Boolean)
    : Array.isArray(existing?.tags)
      ? existing.tags
      : [];
  const isActive = (payload?.isActive ?? existing?.isActive ?? true) === true;
  const createdAt = normalizeDate(payload?.createdAt ?? existing?.createdAt ?? now);
  const updatedAt = normalizeDate(payload?.updatedAt ?? now);

  return {
    id,
    categoryId,
    productGroups,
    type,
    title,
    teaser,
    titleIntl,
    teaserIntl,
    importance,
    contentMarkdown,
    contentIntl,
    tags,
    isActive,
    createdAt: createdAt.toISOString(),
    updatedAt: updatedAt.toISOString(),
  };
}

function normalizeIntlMap(value) {
  const out = {};
  if (value && typeof value === 'object') {
    for (const [key, val] of Object.entries(value)) {
      const lang = normalizeLangValue(key);
      const text = (val ?? '').toString();
      if (lang && text.trim()) {
        out[lang] = text;
      }
    }
  }
  return out;
}

function pickIntl(base, intlMap, lang) {
  const normalized = normalizeLangValue(lang);
  if (!normalized) return base;
  const localized = intlMap?.[normalized];
  return localized ?? base;
}

function categoryWithLang(cat, lang) {
  if (!lang) return cat;
  return {
    ...cat,
    name: pickIntl(cat.name, cat.nameIntl, lang),
    description: pickIntl(cat.description, cat.descriptionIntl, lang),
  };
}

function articleWithLang(article, lang, categories = []) {
  if (!lang) return article;
  const catMap = new Map(categories.map((c) => [c.id, c]));
  const category = catMap.get(article.categoryId);
  return {
    ...article,
    title: pickIntl(article.title, article.titleIntl, lang),
    teaser: pickIntl(article.teaser, article.teaserIntl, lang),
    contentMarkdown: pickIntl(article.contentMarkdown, article.contentIntl, lang),
    categoryName: category ? pickIntl(category.name, category.nameIntl, lang) : article.categoryName,
  };
}

async function loadCategories() {
  if (redis) {
    const raw = await rget(KEY_CATEGORIES);
    const normalized = Array.isArray(raw) ? raw.map((c) => normalizeCategory(c)) : [];
    if (normalized.length) {
      mem.categories = normalized;
      global.__DFS_WIKI_CATEGORIES__ = normalized;
      return normalized;
    }
  }

  const cached = mem.categories;
  if (Array.isArray(cached) && cached.length) return cached;
  if (Array.isArray(global.__DFS_WIKI_CATEGORIES__)) {
    mem.categories = global.__DFS_WIKI_CATEGORIES__;
    return mem.categories;
  }

  mem.categories = wikiSeedCategories.map((c) => normalizeCategory(c));
  return mem.categories;
}

async function loadArticles(categories = null) {
  if (redis) {
    const raw = await rget(KEY_ARTICLES);
    const normalized = Array.isArray(raw) ? raw.map((c) => normalizeArticle(c)) : [];
    if (normalized.length) {
      mem.articles = normalized;
      global.__DFS_WIKI_ARTICLES__ = normalized;
      return normalized;
    }
  }

  const cached = mem.articles;
  if (Array.isArray(cached) && cached.length) return cached;
  if (Array.isArray(global.__DFS_WIKI_ARTICLES__)) {
    mem.articles = global.__DFS_WIKI_ARTICLES__;
    return mem.articles;
  }

  mem.articles = wikiSeedArticles.map((c) => normalizeArticle(c));
  return mem.articles;
}

async function persistCategories(list) {
  const normalized = list.map((c) => normalizeCategory(c));
  normalized.sort((a, b) => a.sortOrder - b.sortOrder || a.name.localeCompare(b.name));
  mem.categories = normalized;
  await rset(KEY_CATEGORIES, normalized);
  global.__DFS_WIKI_CATEGORIES__ = normalized;
  return normalized;
}

async function persistArticles(list) {
  const normalized = list.map((c) => normalizeArticle(c));
  normalized.sort((a, b) => new Date(b.updatedAt) - new Date(a.updatedAt));
  mem.articles = normalized;
  await rset(KEY_ARTICLES, normalized);
  global.__DFS_WIKI_ARTICLES__ = normalized;
  return normalized;
}

export async function wikiCategories({ includeInactive = true, lang = null } = {}) {
  const langNorm = normalizeLangValue(lang);
  const cats = await loadCategories();
  const filtered = includeInactive ? cats : cats.filter((c) => c.isActive);
  return langNorm ? filtered.map((c) => categoryWithLang(c, langNorm)) : filtered;
}

export async function wikiArticles({ includeInactive = false, filters = {}, lang = null } = {}) {
  const langNorm = normalizeLangValue(filters.lang || lang);
  const cats = await wikiCategories({ includeInactive, lang: langNorm });
  const allowedCats = new Set(cats.map((c) => c.id));
  const all = await loadArticles(cats);
  const onlyActive = includeInactive ? all : all.filter((a) => a.isActive);

  const category = (filters.category ?? '').toString().trim();
  const productGroup = (filters.productGroup ?? '').toString().trim().toLowerCase();
  const type = (filters.type ?? '').toString().trim().toLowerCase();
  const search = (filters.search ?? '').toString().trim().toLowerCase();

  const filtered = onlyActive.filter((a) => {
    if (!allowedCats.has(a.categoryId)) return false;
    if (category && a.categoryId !== category) return false;
    if (type && a.type.toLowerCase() !== type) return false;
    if (productGroup) {
      const has = (Array.isArray(a.productGroups) ? a.productGroups : [])
        .some((p) => p.toString().trim().toLowerCase() === productGroup);
      if (!has) return false;
    }
    if (search) {
      const haystack = `${a.title} ${a.teaser} ${a.contentMarkdown}`.toLowerCase();
      if (!haystack.includes(search)) return false;
    }
    return true;
  });

  if (!langNorm) return filtered;
  return filtered.map((a) => articleWithLang(a, langNorm, cats));
}

export async function wikiPublicList(params = {}) {
  const lang = normalizeLangValue(params.lang || params.locale);
  const cats = await wikiCategories({ includeInactive: false, lang });
  const items = await wikiArticles({ includeInactive: false, filters: params, lang });
  return { categories: cats, articles: items };
}

export async function wikiGetPublic(id, { lang = null } = {}) {
  const target = (id ?? '').toString().trim();
  if (!target) return null;
  const langNorm = normalizeLangValue(lang);
  const cats = await wikiCategories({ includeInactive: false, lang: langNorm });
  const allowed = new Set(cats.map((c) => c.id));
  const items = await wikiArticles({ includeInactive: false, lang: langNorm });
  const found = items.find((a) => a.id === target);
  if (!found) return null;
  if (!allowed.has(found.categoryId)) return null;
  if (!langNorm) return found;
  return articleWithLang(found, langNorm, cats);
}

export async function wikiAdminList(params = {}) {
  const includeInactive = params.includeInactive !== false;
  const cats = await wikiCategories({ includeInactive });
  const items = await wikiArticles({ includeInactive, filters: params });
  return { categories: cats, articles: items };
}

export async function wikiSaveCategory(payload) {
  const cats = await loadCategories();
  const existing = cats.find((c) => c.id === (payload?.id || payload?.categoryId));
  const normalized = normalizeCategory(payload, existing);
  const idx = cats.findIndex((c) => c.id === normalized.id);
  if (idx >= 0) cats[idx] = normalized; else cats.push(normalized);
  await persistCategories(cats);
  return normalized;
}

export async function wikiSetCategoryStatus(id, isActive) {
  const target = (id ?? '').toString().trim();
  if (!target) throw new Error('id required');
  const cats = await loadCategories();
  const idx = cats.findIndex((c) => c.id === target);
  if (idx < 0) throw new Error('category not found');
  const updated = { ...cats[idx], isActive: isActive === true };
  cats[idx] = updated;
  await persistCategories(cats);
  return updated;
}

export async function wikiDeleteCategory(id) {
  const target = (id ?? '').toString().trim();
  if (!target) return false;
  const cats = await loadCategories();
  const items = await loadArticles();
  const nextCats = cats.filter((c) => c.id !== target);
  const nextItems = items.filter((a) => a.categoryId !== target);
  await persistCategories(nextCats);
  await persistArticles(nextItems);
  return nextCats.length !== cats.length;
}

export async function wikiSaveArticle(payload) {
  const items = await loadArticles();
  const normalized = normalizeArticle(payload);
  const idx = items.findIndex((a) => a.id === normalized.id);
  if (idx >= 0) items[idx] = normalized; else items.push(normalized);
  await persistArticles(items);
  return normalized;
}

export async function wikiDeleteArticle(id) {
  const target = (id ?? '').toString().trim();
  if (!target) return false;
  const items = await loadArticles();
  const nextItems = items.filter((a) => a.id !== target);
  await persistArticles(nextItems);
  return nextItems.length !== items.length;
}

export async function wikiGetArticle(id) {
  const target = (id ?? '').toString().trim();
  if (!target) return null;
  const items = await loadArticles();
  return items.find((a) => a.id === target) || null;
}
