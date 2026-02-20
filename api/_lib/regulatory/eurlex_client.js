const BASE_URL = 'https://eur-lex.europa.eu';
const MDR_BASE_CELEX = '32017R0745';
const CONSOLIDATED_CELEX_RE = /02017R0745-\d{8}/g;

function buildAllUrl(locale = 'DE') {
  return `${BASE_URL}/legal-content/${locale}/ALL/?uri=CELEX:${MDR_BASE_CELEX}`;
}

function buildConsolidatedHtmlUrl(consolidatedCelex, locale = 'DE') {
  return `${BASE_URL}/legal-content/${locale}/TXT/HTML/?uri=CELEX:${consolidatedCelex}`;
}

async function withRetry(url, attempts = 2) {
  let last;
  for (let i = 0; i < attempts; i += 1) {
    const ctrl = new AbortController();
    const timeout = setTimeout(() => ctrl.abort(), 12000);
    try {
      const response = await fetch(url, {
        signal: ctrl.signal,
        headers: { 'user-agent': 'ConnectPlus-RegulatorySync/1.0' },
      });
      clearTimeout(timeout);
      if (!response.ok) throw new Error(`HTTP_${response.status}`);
      return await response.text();
    } catch (err) {
      clearTimeout(timeout);
      last = err;
    }
  }
  throw last || new Error('fetch failed');
}

function extractLatestConsolidatedCelex(html = '') {
  const matches = String(html || '').match(CONSOLIDATED_CELEX_RE) || [];
  const unique = [...new Set(matches)];
  if (!unique.length) return null;
  unique.sort((a, b) => a.localeCompare(b));
  return unique[unique.length - 1] || null;
}

function toConsolidationDate(celex = '') {
  const raw = String(celex || '').split('-')[1] || '';
  if (!/^\d{8}$/.test(raw)) return null;
  return `${raw.slice(0, 4)}-${raw.slice(4, 6)}-${raw.slice(6, 8)}`;
}

export async function getLatestMdrVersionMeta() {
  let consolidatedCelex = null;
  let consolidatedLocale = 'DE';

  try {
    const deAllHtml = await withRetry(buildAllUrl('DE'), 2);
    consolidatedCelex = extractLatestConsolidatedCelex(deAllHtml);
  } catch (err) {
    console.warn('[regulatory/eurlex] failed to resolve consolidated celex', {
      locale: 'DE',
      message: err?.message || String(err),
    });
  }

  if (!consolidatedCelex) {
    try {
      const deTxtHtml = await withRetry(buildConsolidatedHtmlUrl(MDR_BASE_CELEX, 'DE'), 2);
      consolidatedCelex = extractLatestConsolidatedCelex(deTxtHtml);
      consolidatedLocale = 'DE';
    } catch (err) {
      console.warn('[regulatory/eurlex] failed to resolve consolidated celex', {
        locale: 'DE',
        view: 'TXT',
        message: err?.message || String(err),
      });
    }
  }

  if (!consolidatedCelex) {
    try {
      const enTxtHtml = await withRetry(buildConsolidatedHtmlUrl(MDR_BASE_CELEX, 'EN'), 2);
      consolidatedCelex = extractLatestConsolidatedCelex(enTxtHtml);
      consolidatedLocale = 'EN';
    } catch (err) {
      console.warn('[regulatory/eurlex] failed to resolve consolidated celex', {
        locale: 'EN',
        view: 'TXT',
        message: err?.message || String(err),
      });
    }
  }

  if (!consolidatedCelex) {
    console.error('[eurlex_client] consolidated CELEX not found in DE/ALL, DE/TXT, EN/TXT');
    throw new Error('NO_CONSOLIDATED_CELEX_FOUND');
  }

  const sourceUrl = buildConsolidatedHtmlUrl(consolidatedCelex, consolidatedLocale);
  const html = await withRetry(sourceUrl, 2);

  return {
    base_celex: MDR_BASE_CELEX,
    consolidated_celex: consolidatedCelex,
    versionLabel: consolidatedCelex,
    consolidation_date: toConsolidationDate(consolidatedCelex),
    consolidationDate: toConsolidationDate(consolidatedCelex),
    source_url: sourceUrl,
    sourceUrl,
    html,
  };
}

export async function fetchMdrConsolidatedHtml(meta) {
  if (meta?.html && meta?.source_url) {
    return { sourceUrl: meta.source_url, source_url: meta.source_url, html: meta.html };
  }
  const latest = await getLatestMdrVersionMeta();
  return { sourceUrl: latest.source_url, source_url: latest.source_url, html: latest.html };
}

export { MDR_BASE_CELEX };
