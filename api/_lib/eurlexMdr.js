import { createHash } from 'node:crypto';

const MDR_CELEX = '32017R0745';
const PARSER_VERSION = 'eurlex-xml-v1';
const EUR_LEX_XML_URL = `https://eur-lex.europa.eu/legal-content/EN/TXT/XML/?uri=CELEX:${MDR_CELEX}`;
const FETCH_TIMEOUT_MS = 10_000;

const MIN_STABLE_TEXT_LENGTH = 20_000;

const REQUIRED_ANCHORS = [
  /annex\s+i\b/i,
  /general safety and performance requirements/i,
];

const ANTI_BOT_OR_NAV_PATTERNS = [
  /access denied/i,
  /forbidden/i,
  /verify you are (not )?a robot/i,
  /enable javascript/i,
  /cookie/i,
  /captcha/i,
  /sign in/i,
  /register/i,
  /my recent searches/i,
  /navigation/i,
  /official eu languages/i,
  /eur-lex access to european union law/i,
];

function decodeEntities(text = '') {
  return text
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/&#x([0-9a-f]+);/gi, (_, hex) => String.fromCodePoint(parseInt(hex, 16)))
    .replace(/&#(\d+);/g, (_, dec) => String.fromCodePoint(parseInt(dec, 10)));
}

function stripMarkup(payload = '') {
  return payload
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, ' $1 ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export function normalizeStableText(payload = '') {
  return decodeEntities(stripMarkup(payload))
    .replace(/\u00a0/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export function stabilityCheck(rawText = '') {
  const text = (rawText || '').trim();
  if (!text) return { ok: false, reason: 'EMPTY_TEXT' };

  const lower = text.toLowerCase();
  if (ANTI_BOT_OR_NAV_PATTERNS.some((pattern) => pattern.test(lower))) {
    return { ok: false, reason: 'ANTI_BOT_OR_NAV_MARKUP_DETECTED' };
  }

  if (text.length < MIN_STABLE_TEXT_LENGTH) {
    return { ok: false, reason: `TEXT_TOO_SHORT_${text.length}` };
  }

  const missingAnchors = REQUIRED_ANCHORS.filter((pattern) => !pattern.test(text));
  if (missingAnchors.length > 0) {
    return { ok: false, reason: 'EXPECTED_ANCHORS_MISSING' };
  }

  return { ok: true, reason: '' };
}

export async function fetchEurLexMdrText() {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort('timeout'), FETCH_TIMEOUT_MS);

  try {
    const response = await fetch(EUR_LEX_XML_URL, {
      method: 'GET',
      redirect: 'follow',
      signal: controller.signal,
      headers: {
        accept: 'application/xml,text/xml,text/plain;q=0.7,*/*;q=0.5',
        'accept-language': 'en',
        'cache-control': 'no-cache',
      },
    });

    const raw = await response.text();
    const sourceMeta = {
      sourceUrl: response.url || EUR_LEX_XML_URL,
      parserVersion: PARSER_VERSION,
      celex: MDR_CELEX,
      fetchedAt: new Date().toISOString(),
      contentType: (response.headers.get('content-type') || '').toLowerCase(),
      status: response.status,
      rawSnippet: (raw || '').slice(0, 500),
    };

    if (!response.ok) {
      return {
        ok: false,
        reason: `HTTP_${response.status}`,
        sourceMeta,
        rawBody: raw,
      };
    }

    const text = normalizeStableText(raw);
    const check = stabilityCheck(text);
    if (!check.ok) {
      return {
        ok: false,
        reason: check.reason,
        sourceMeta,
        rawBody: raw,
      };
    }

    const contentHash = createHash('sha256').update(text).digest('hex');
    return {
      ok: true,
      text,
      contentHash,
      sourceMeta,
      rawBody: raw,
    };
  } catch (err) {
    return {
      ok: false,
      reason: err?.name === 'AbortError' ? 'FETCH_TIMEOUT' : 'FETCH_FAILED',
      sourceMeta: {
        sourceUrl: EUR_LEX_XML_URL,
        parserVersion: PARSER_VERSION,
        celex: MDR_CELEX,
        fetchedAt: new Date().toISOString(),
      },
      errorMessage: err?.message || 'fetch failed',
      rawBody: '',
    };
  } finally {
    clearTimeout(timeout);
  }
}
