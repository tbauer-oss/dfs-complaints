// api/_lib/wikiValidation.js
// Lightweight validation helpers to avoid external runtime dependencies

const VALID_TYPES = ['faq', 'safety', 'error', 'prevention'];
const VALID_IMPORTANCE = ['normal', 'high', 'critical'];

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

export function validateCategoryPayload(payload = {}) {
  const name = parseString(payload.name, { required: true });
  const description = parseString(payload.description);
  const icon = parseString(payload.icon);
  const sortOrder = parseNumber(payload.sortOrder);
  const isActive = parseBool(payload.isActive, true);

  return {
    name,
    description,
    icon,
    sortOrder: sortOrder ?? undefined,
    isActive,
  };
}

export function validateArticlePayload(payload = {}) {
  const categoryId = parseString(payload.categoryId, { required: true });
  const productGroups = parseStringArray(payload.productGroups);
  const typeRaw = parseString(payload.type, { defaultValue: 'faq' }).toLowerCase();
  const type = VALID_TYPES.includes(typeRaw) ? typeRaw : 'faq';
  const title = parseString(payload.title, { required: true });
  const teaser = parseString(payload.teaser);
  const importanceRaw = parseString(payload.importance, { defaultValue: 'normal' }).toLowerCase();
  const importance = VALID_IMPORTANCE.includes(importanceRaw) ? importanceRaw : 'normal';
  const contentMarkdown = toStr(payload.contentMarkdown ?? '').trim();
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
    importance,
    contentMarkdown,
    tags,
    isActive,
    createdAt: createdAt ?? undefined,
    updatedAt: updatedAt ?? undefined,
  };
}
