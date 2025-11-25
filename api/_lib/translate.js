// api/_lib/translate.js
import { SUPPORTED_LANGS, normalizeLangValue } from './store.js';

const DEEPL_API_KEY =
  process.env.DEEPL_API_KEY ||
  process.env.DEEPL_AUTH_KEY ||
  process.env.DEEPL_KEY ||
  '';

const DEEPL_API_URL =
  process.env.DEEPL_API_URL ||
  process.env.DEEPL_ENDPOINT ||
  'https://api-free.deepl.com/v2/translate';

const TRANSLATE_TIMEOUT_MS = Math.max(1500, Number(process.env.TRANSLATE_TIMEOUT_MS || 8000));

export function translationProviderReady() {
  return Boolean(DEEPL_API_KEY && DEEPL_API_URL);
}

function normLang(code) {
  return normalizeLangValue(code) || 'de';
}

function normTargetList(list, source) {
  const src = normLang(source);
  const out = [];
  const seen = new Set();
  for (const entry of Array.isArray(list) ? list : []) {
    const lc = normLang(entry);
    if (!lc || lc === src || seen.has(lc)) continue;
    if (SUPPORTED_LANGS.has(lc)) {
      seen.add(lc);
      out.push(lc);
    }
  }
  return out;
}

function deeplLang(code) {
  switch (normLang(code)) {
    case 'de':
      return 'DE';
    case 'en':
      return 'EN';
    case 'fr':
      return 'FR';
    case 'it':
      return 'IT';
    case 'es':
      return 'ES';
    default:
      return '';
  }
}

async function translateWithDeepL(textEntries = [], sourceLang = 'de', targetLang = 'en') {
  if (!translationProviderReady()) {
    const err = new Error('DeepL API key not configured');
    err.statusCode = 503;
    throw err;
  }

  const src = deeplLang(sourceLang);
  const tgt = deeplLang(targetLang);
  if (!tgt) throw new Error('unsupported target language');

  const form = new URLSearchParams();
  form.set('target_lang', tgt);
  if (src) form.set('source_lang', src);

  const orderedKeys = [];
  for (const [key, value] of textEntries) {
    const trimmed = (value ?? '').toString().trim();
    if (!trimmed) continue;
    orderedKeys.push(key);
    form.append('text', trimmed);
  }

  if (orderedKeys.length === 0) return {};

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), TRANSLATE_TIMEOUT_MS);

  try {
    const res = await fetch(DEEPL_API_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        Authorization: `DeepL-Auth-Key ${DEEPL_API_KEY}`,
      },
      body: form.toString(),
      signal: controller.signal,
    });

    if (!res.ok) {
      const txt = (await res.text()) || res.statusText;
      throw new Error(`DeepL HTTP ${res.status}: ${txt}`);
    }

    const body = await res.json();
    const translations = Array.isArray(body?.translations) ? body.translations : [];
    if (translations.length !== orderedKeys.length) {
      throw new Error('unexpected translation result');
    }

    const mapped = {};
    translations.forEach((entry, idx) => {
      const key = orderedKeys[idx];
      const text = (entry?.text ?? '').toString().trim();
      if (key && text) mapped[key] = text;
    });

    return mapped;
  } finally {
    clearTimeout(timeout);
  }
}

export async function translateTexts({ textByKey = {}, sourceLang = 'de', targetLangs = [] }) {
  const source = normLang(sourceLang);
  const targets = targetLangs.length > 0 ? normTargetList(targetLangs, source) : normTargetList([...SUPPORTED_LANGS], source);

  const entries = Object.entries(textByKey)
    .filter(([key, value]) => key && (value ?? '').toString().trim().length > 0)
    .map(([key, value]) => [key, (value ?? '').toString()]);

  if (entries.length === 0) {
    throw new Error('no text provided for translation');
  }
  if (targets.length === 0) {
    throw new Error('no target languages provided');
  }

  const translations = {};
  for (const target of targets) {
    translations[target] = await translateWithDeepL(entries, source, target);
  }

  return { provider: 'deepl', translations, sourceLang: source };
}

