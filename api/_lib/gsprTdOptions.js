import { fmeaAll, fmeaGet } from './store.js';
import { loadActiveTdCatalogItemsFromFile } from './tdCatalogFile.js';

const MDR_TD_PREFIX = 'MDR-TD';

export function normalizeTdLabel(value) {
  let text = (value ?? '').toString().trim();
  if (!text) return '';
  text = text.replace(/\s+/g, ' ');
  text = text.replace(/\s+[–—-]\s+/g, ' – ');
  text = text.replace(/\s+/g, ' ').trim();
  return text;
}

function normalizeTdValue(value) {
  let text = (value ?? '').toString().trim();
  if (!text) return '';
  text = text.replace(/\s+/g, ' ').trim();
  return text;
}

export function parseMdrTd(label) {
  const normalized = normalizeTdLabel(label);
  if (!normalized.startsWith(MDR_TD_PREFIX)) return '';
  const parts = normalized.split(' – ');
  return parts[0].trim();
}

export function extractTdIndex(label) {
  const code = parseMdrTd(label);
  const match = /^MDR-TD\s*([0-9]+)/.exec(code);
  if (!match) return null;
  const idx = Number(match[1]);
  return Number.isFinite(idx) ? idx : null;
}

export function compareTdLabels(a, b) {
  const aIndex = extractTdIndex(a);
  const bIndex = extractTdIndex(b);
  if (aIndex != null && bIndex != null && aIndex !== bIndex) return aIndex - bIndex;
  if (aIndex != null && bIndex == null) return -1;
  if (aIndex == null && bIndex != null) return 1;
  return a.localeCompare(b, undefined, { numeric: true, sensitivity: 'base' });
}

function fmeaLabel(fmea) {
  const title = (fmea?.title || fmea?.productGroup || '').toString().trim();
  const mdrTd = (fmea?.mdrTd || '').toString().trim();
  if (!mdrTd) return '';
  if (title) return `${mdrTd} – ${title}`;
  return mdrTd;
}

async function loadMdrTdValues() {
  const values = new Set();
  const rows = await loadActiveTdCatalogItemsFromFile();
  for (const row of rows) {
    const code = normalizeTdValue(row?.td_key);
    if (!code.startsWith(MDR_TD_PREFIX)) continue;
    const title = String(row?.title || '').replace(/^\s*MDR-TD\d+\s*[-–—:]?\s*/i, '').trim();
    const label = title ? `${code} – ${title}` : code;
    values.add(label);
  }
  if (values.size === 0) {
    console.error('[gspr/td-options] no MDR-TD entries found in file catalog');
  }

  return Array.from(values);
}

export async function gsprTdOptions() {
  const tdValues = await loadMdrTdValues();
  const fmeas = await fmeaAll();
  const fmeaByMdrTd = new Map();
  for (const fmea of fmeas) {
    const mdrTd = parseMdrTd((fmea?.mdrTd || '').toString().trim()) || (fmea?.mdrTd || '').toString().trim();
    if (mdrTd) fmeaByMdrTd.set(mdrTd, fmea);
  }

  const options = tdValues
    .map((label) => {
      const mdrTd = parseMdrTd(label) || label;
      const fmea = fmeaByMdrTd.get(mdrTd) || null;
      return {
        key: mdrTd,
        label,
        mdrTd,
        hasFmea: Boolean(fmea),
      };
    })
    .sort((a, b) => compareTdLabels(a.label, b.label));

  return options;
}

export async function resolveGsprTdInfo(tdId) {
  if (!tdId) return null;
  const fmea = await fmeaGet(tdId);
  if (fmea) {
    return {
      id: fmea.id,
      mdrTd: (fmea.mdrTd || '').toString(),
      label: normalizeTdLabel(fmeaLabel(fmea)) || (fmea.mdrTd || '').toString(),
      active: fmea.active !== false,
      archivedAt: fmea.archivedAt || null,
    };
  }

  const options = await gsprTdOptions();
  const normalizedId = normalizeTdLabel(tdId);
  const match = options.find((option) => option.key === tdId) ||
    (normalizedId ? options.find((option) => option.label === normalizedId) : null);
  if (!match) return null;
  return {
    id: match.key,
    mdrTd: match.mdrTd || parseMdrTd(match.label),
    label: match.label,
    active: true,
    archivedAt: null,
  };
}
