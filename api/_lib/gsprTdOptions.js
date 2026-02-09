import { fmeaAll, fmeaGet } from './store.js';
import { getProducts } from './products.js';

export function normalizeTdLabel(value) {
  let text = (value ?? '').toString().trim();
  if (!text) return '';
  text = text.replace(/\s+/g, ' ');
  text = text.replace(/\s*[-–—]\s*/g, ' – ');
  text = text.replace(/\s+/g, ' ').trim();
  return text;
}

export function parseMdrTd(label) {
  const normalized = normalizeTdLabel(label);
  if (!normalized.startsWith('MDR-TD')) return '';
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

export async function gsprTdOptions() {
  const products = await getProducts();
  const byLabel = new Map();

  for (const product of products) {
    const raw = (product?.tdNumberAndName || '').toString().trim();
    if (!raw.startsWith('MDR-TD')) continue;
    const normalized = normalizeTdLabel(raw);
    if (!normalized.startsWith('MDR-TD')) continue;
    if (!byLabel.has(normalized)) {
      byLabel.set(normalized, {
        label: normalized,
        mdrTd: parseMdrTd(normalized),
      });
    }
  }

  const fmeas = await fmeaAll();
  const fmeaByLabel = new Map();
  const fmeaByMdrTd = new Map();
  for (const fmea of fmeas) {
    const mdrTd = (fmea?.mdrTd || '').toString().trim();
    if (mdrTd) fmeaByMdrTd.set(mdrTd, fmea);
    const normalizedLabel = normalizeTdLabel(fmeaLabel(fmea));
    if (normalizedLabel) fmeaByLabel.set(normalizedLabel, fmea);
  }

  const options = Array.from(byLabel.values())
    .map((entry) => {
      const fmea = fmeaByLabel.get(entry.label) || fmeaByMdrTd.get(entry.mdrTd);
      return {
        key: fmea ? fmea.id : entry.label,
        label: entry.label,
        mdrTd: entry.mdrTd,
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
