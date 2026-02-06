// api/_lib/wikiValidation.js
// Lightweight validation helpers to avoid external runtime dependencies

import { normalizeLangValue } from './store.js';

const VALID_TYPES = ['faq', 'safety', 'error', 'prevention'];
const VALID_IMPORTANCE = ['normal', 'high', 'critical'];
const WIKI_LANGS = ['de', 'en', 'es', 'fr', 'it'];

function toStr(value) {
  return (value ?? '').toString();
}

function parseBool(value, defaultValue = false) {
  if (value === undefined || value === null) return defaultValue;
  if (typeof value === 'boolean') return value;
  const normalized = toStr(value).toLowerCase().trim();
  if (!normalized) return defaultValue;
  return ['1', 'true', 'yes', 'on'].includes(normalized);
}

function parseNumber(value) {
  const num = Number(value);
  return Number.isFinite(num) ? num : null;
}

function parseDate(value) {
  if (!value) return null;
  const d = value instanceof Date ? value : new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

function parseString(value, { required = false, defaultValue = '' } = {}) {
  const text = toStr(value).trim();
  if (required && !text) throw new Error('missing required field');
  return text || defaultValue;
}

function parseStringArray(value) {
  if (!Array.isArray(value)) return [];
  return value
    .map((v) => toStr(v).trim())
    .filter(Boolean);
}

function parseTranslationsBlock(value, keys) {
  const out = {};
  if (value && typeof value === 'object') {
    for (const [lang, entry] of Object.entries(value)) {
      const normalized = normalizeLangValue(lang);
      if (!normalized || !WIKI_LANGS.includes(normalized)) continue;
      const item = {};
      for (const key of keys) {
        const text = toStr(entry?.[key] ?? '').trim();
        if (text) item[key] = text;
      }
      if (Object.keys(item).length) out[normalized] = item;
    }
  }
  return out;
}

function translationsToIntlMap(translations, key) {
  const out = {};
  for (const [lang, entry] of Object.entries(translations || {})) {
    const text = toStr(entry?.[key] ?? '').trim();
    if (text) out[lang] = text;
  }
  return out;
}

export function validateCategoryPayload(payload = {}) {
  const translations = parseTranslationsBlock(payload.translations, ['name', 'description']);
  const name = parseString(payload.name ?? translations.de?.name, { required: true });
  const description = parseString(payload.description ?? translations.de?.description);
  const icon = parseString(payload.icon);
  const sortOrder = parseNumber(payload.sortOrder);
  const isActive = parseBool(payload.isActive, true);

  return {
    name,
    description,
    nameIntl: translationsToIntlMap(translations, 'name'),
    descriptionIntl: translationsToIntlMap(translations, 'description'),
    icon,
    sortOrder: sortOrder ?? undefined,
    isActive,
    translations,
  };
}

export function validateCategoryStatusPayload(payload = {}) {
  if (!('isActive' in payload)) throw new Error('isActive required');
  const isActive = parseBool(payload.isActive);
  return { isActive };
}

export function validateArticlePayload(payload = {}) {
  const categoryId = parseString(payload.categoryId, { required: true });
  const productGroups = parseStringArray(payload.productGroups);
  const typeRaw = parseString(payload.type, { defaultValue: 'faq' }).toLowerCase();
  const type = VALID_TYPES.includes(typeRaw) ? typeRaw : 'faq';
  const translations = parseTranslationsBlock(payload.translations, ['title', 'teaser', 'contentMarkdown']);
  const title = parseString(payload.title ?? translations.de?.title, { required: true });
  const teaser = parseString(payload.teaser ?? translations.de?.teaser);
  const importanceRaw = parseString(payload.importance, { defaultValue: 'normal' }).toLowerCase();
  const importance = VALID_IMPORTANCE.includes(importanceRaw) ? importanceRaw : 'normal';
  const contentMarkdown = toStr(payload.contentMarkdown ?? translations.de?.contentMarkdown ?? '').trim();
  const tags = parseStringArray(payload.tags);
  const isActive = parseBool(payload.isActive, true);
  const createdAt = parseDate(payload.createdAt);
  const updatedAt = parseDate(payload.updatedAt);

  return {
    categoryId,
    productGroups,
    type,
    title,
    teaser,
    titleIntl: translationsToIntlMap(translations, 'title'),
    teaserIntl: translationsToIntlMap(translations, 'teaser'),
    importance,
    contentMarkdown,
    contentIntl: translationsToIntlMap(translations, 'contentMarkdown'),
    tags,
    isActive,
    createdAt: createdAt ?? undefined,
    updatedAt: updatedAt ?? undefined,
    translations,
  };
}
