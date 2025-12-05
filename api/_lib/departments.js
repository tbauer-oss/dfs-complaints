// api/_lib/departments.js
// Zentrale Pflege der internen Abteilungen und Normalisierung für Berechtigungen

export const DEFAULT_INTERNAL_DEPARTMENTS = [
  'Sinterei',
  'Galvanik',
  'Galvanik Vor-/Nachbereitung',
  'Schleiferei',
  'Bürstenproduktion',
  'Dreherei',
  'MP Spezialfertigung',
  'Chemie / Logistik',
  'Versand / Lager',
  'Vertrieb',
];

export function normalizeDepartments(input) {
  const list = Array.isArray(input) ? input : [input];
  const seen = new Set();
  const normalized = [];
  for (const entry of list) {
    const value = (entry ?? '').toString().trim();
    if (!value) continue;
    const key = value.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    normalized.push(value);
  }
  return normalized;
}

export function hasDepartmentOverlap(a = [], b = []) {
  const left = normalizeDepartments(a).map((v) => v.toLowerCase());
  const right = new Set(normalizeDepartments(b).map((v) => v.toLowerCase()));
  const leftHasAll = left.includes('alle') || left.includes('all');
  const rightHasAll = right.has('alle') || right.has('all');
  if (leftHasAll || rightHasAll) return true;
  if (left.length === 0 || right.size === 0) return false;
  return left.some((v) => right.has(v));
}

export const INTERNAL_EVALUATION_CAUSES = [
  'Produktionsfehler',
  'Prozessfehler',
  'Aufmerksamkeitsversagen',
  'möglicher Anwenderfehler',
  'Materialproblem',
  'unvollständige / unklare Arbeitsanweisung',
  'unzureichende Schulung',
  'Lieferantenproblem',
  'sonstige Ursache (bitte im Text spezifizieren)',
];

export function normalizeInternalEvaluationCause(value) {
  const raw = (value ?? '').toString().trim();
  if (!raw) return null;
  const match = INTERNAL_EVALUATION_CAUSES.find((entry) => entry.toLowerCase() === raw.toLowerCase());
  return match || null;
}

export function normalizeEvaluationText(value) {
  const raw = (value ?? '').toString();
  const trimmed = raw.trim();
  return trimmed ? trimmed : null;
}

export const ALLOWED_EVALUATION_TRANSLATION_LANGS = new Set(['de', 'en', 'es', 'fr', 'it']);

export function normalizeEvaluationTranslations(input) {
  const out = {};
  for (const [lang, value] of Object.entries(input || {})) {
    const lc = (lang || '').toString().trim().toLowerCase();
    if (!ALLOWED_EVALUATION_TRANSLATION_LANGS.has(lc)) continue;
    const text = normalizeEvaluationText(value);
    if (text) out[lc] = text;
  }
  return out;
}

export function normalizeReportLinksMap(map) {
  const out = {};
  for (const [lang, url] of Object.entries(map || {})) {
    const lc = (lang || '').toString().trim().toLowerCase();
    const val = (url ?? '').toString().trim();
    if (!lc || !val) continue;
    if (!/^https?:\/\//i.test(val) && !val.startsWith('data:')) continue;
    out[lc] = val;
  }
  return out;
}
