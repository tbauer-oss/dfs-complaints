const BASE_URL = 'https://eur-lex.europa.eu';
const SPARQL_URL = 'https://publications.europa.eu/webapi/rdf/sparql';
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

async function withRetryResponse(url, attempts = 2) {
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
      return { html: await response.text(), finalUrl: response.url || url };
    } catch (err) {
      clearTimeout(timeout);
      last = err;
    }
  }
  throw last || new Error('fetch failed');
}

async function withRetryJson(url, attempts = 2) {
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
      return await response.json();
    } catch (err) {
      clearTimeout(timeout);
      last = err;
    }
  }
  throw last || new Error('fetch failed');
}

function extractLatestConsolidatedCelex(html = '') {
  const raw = String(html || '');
  const direct = raw.match(CONSOLIDATED_CELEX_RE) || [];
  const encodedDash = raw.match(/02017R0745(?:%2D|%2d)(\d{8})/g) || [];
  const normalizedEncoded = encodedDash.map((m) => m.replace(/%2D/i, '-'));
  const unique = [...new Set([...direct, ...normalizedEncoded])]
    .map((m) => {
      const found = String(m).match(/02017R0745-(\d{8})/);
      return found ? `02017R0745-${found[1]}` : null;
    })
    .filter(Boolean);
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
    const redirectAttempts = [
      { locale: 'DE', url: buildConsolidatedHtmlUrl('02017R0745', 'DE') },
      { locale: 'EN', url: buildConsolidatedHtmlUrl('02017R0745', 'EN') },
    ];

    for (const attempt of redirectAttempts) {
      try {
        const { html: latestHtml, finalUrl } = await withRetryResponse(attempt.url, 2);
        consolidatedCelex = extractLatestConsolidatedCelex(`${finalUrl}\n${latestHtml}`);
        if (consolidatedCelex) {
          consolidatedLocale = attempt.locale;
          break;
        }
      } catch (err) {
        console.warn('[regulatory/eurlex] failed to resolve consolidated celex', {
          locale: attempt.locale,
          view: 'TXT_REDIRECT',
          message: err?.message || String(err),
        });
      }
    }
  }

  if (!consolidatedCelex) {
    const sparqlQuery = `PREFIX cdm: <http://publications.europa.eu/ontology/cdm#>
SELECT ?celex WHERE {
  ?work cdm:resource_legal_id_celex ?celex .
  FILTER(STRSTARTS(STR(?celex), "02017R0745-"))
}
ORDER BY DESC(STR(?celex))
LIMIT 1`;

    try {
      const sparqlUrl = `${SPARQL_URL}?query=${encodeURIComponent(sparqlQuery)}&format=${encodeURIComponent('application/sparql-results+json')}`;
      const json = await withRetryJson(sparqlUrl, 2);
      const sparqlCelex = json?.results?.bindings?.[0]?.celex?.value;
      if (typeof sparqlCelex === 'string' && /^02017R0745-\d{8}$/.test(sparqlCelex)) {
        consolidatedCelex = sparqlCelex;
        consolidatedLocale = 'DE';
        console.info('[eurlex_client] resolved consolidated CELEX via SPARQL:', consolidatedCelex);
      }
    } catch (err) {
      console.warn('[regulatory/eurlex] SPARQL consolidated celex lookup failed', {
        message: err?.message || String(err),
      });
    }
  }

  if (!consolidatedCelex) {
    console.error('[eurlex_client] SPARQL fallback failed; cannot resolve consolidated CELEX');
    throw new Error('NO_CONSOLIDATED_CELEX_FOUND');
  }

  let sourceUrl = buildConsolidatedHtmlUrl(consolidatedCelex, consolidatedLocale);
  let html;

  try {
    html = await withRetry(sourceUrl, 2);
  } catch (err) {
    if (consolidatedLocale === 'DE') {
      sourceUrl = buildConsolidatedHtmlUrl(consolidatedCelex, 'EN');
      html = await withRetry(sourceUrl, 2);
      consolidatedLocale = 'EN';
    } else {
      throw err;
    }
  }

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
