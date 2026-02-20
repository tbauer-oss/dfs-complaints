import { load } from 'cheerio';

const MDR_CELEX = '32017R0745';
const BASE_URL = 'https://eur-lex.europa.eu';
const LANDING_URL = `${BASE_URL}/legal-content/EN/TXT/?uri=CELEX:${MDR_CELEX}`;

async function withRetry(url, attempts = 2) {
  let last;
  for (let i = 0; i < attempts; i += 1) {
    const ctrl = new AbortController();
    const timeout = setTimeout(() => ctrl.abort(), 12000);
    try {
      const response = await fetch(url, { signal: ctrl.signal, headers: { 'user-agent': 'ConnectPlus-RegulatorySync/1.0' } });
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

export async function getLatestMdrVersionMeta() {
  const html = await withRetry(LANDING_URL, 2);
  const $ = load(html);
  const candidates = [
    $('[data-celex]').first().attr('data-celex') || '',
    $('meta[name="WT.z_celex"]').attr('content') || '',
  ].filter(Boolean);
  const celex = candidates.find((v) => /\d{4}R\d+/i.test(v)) || MDR_CELEX;
  const label = `CELEX-${celex}`;
  const sourceUrl = `${BASE_URL}/legal-content/EN/TXT/HTML/?uri=CELEX:${celex}`;
  return { celex, versionLabel: label, sourceUrl, consolidationDate: null };
}

export async function fetchMdrConsolidatedHtml(meta) {
  const sourceUrl = meta?.sourceUrl || `${BASE_URL}/legal-content/EN/TXT/HTML/?uri=CELEX:${MDR_CELEX}`;
  const html = await withRetry(sourceUrl, 2);
  return { sourceUrl, html };
}
