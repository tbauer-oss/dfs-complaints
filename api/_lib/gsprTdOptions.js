import fs from 'fs/promises';
import path from 'path';

import { fmeaAll, fmeaGet } from './store.js';

const MDR_TD_PREFIX = 'MDR-TD';
const CSV_PATH = path.join(process.cwd(), 'dfs_mobile', 'assets', 'data', 'dfs_products.csv');

export function normalizeTdLabel(value) {
  let text = (value ?? '').toString().trim();
  if (!text) return '';
  text = text.replace(/\s+/g, ' ');
  text = text.replace(/\s*[-–—]\s*/g, ' – ');
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

function detectDelimiter(line) {
  const commaCount = (line.match(/,/g) || []).length;
  const semiCount = (line.match(/;/g) || []).length;
  return semiCount > commaCount ? ';' : ',';
}

function parseCsvRows(content, delimiter) {
  const rows = [];
  let row = [];
  let field = '';
  let inQuotes = false;

  for (let i = 0; i < content.length; i++) {
    const char = content[i];
    if (char === '"') {
      const next = content[i + 1];
      if (inQuotes && next === '"') {
        field += '"';
        i++;
        continue;
      }
      inQuotes = !inQuotes;
      continue;
    }

    if (!inQuotes && char === delimiter) {
      row.push(field);
      field = '';
      continue;
    }

    if (!inQuotes && (char === '\n' || char === '\r')) {
      if (char === '\r' && content[i + 1] === '\n') i++;
      row.push(field);
      rows.push(row);
      row = [];
      field = '';
      continue;
    }

    field += char;
  }

  row.push(field);
  if (row.length > 1 || row[0]?.trim()) rows.push(row);
  return rows;
}

async function loadMdrTdValues() {
  const buf = await fs.readFile(CSV_PATH);
  let content;
  try {
    content = buf.toString('utf8');
  } catch (_) {
    content = buf.toString('latin1');
  }

  const previewLines = content.split(/\r?\n/).slice(0, 3);
  const headerLine = previewLines.find((line) => line.trim().length > 0) || '';
  const delimiter = detectDelimiter(headerLine);
  const rows = parseCsvRows(content, delimiter);
  const values = new Set();

  for (const row of rows) {
    if (!row || row.length === 0) continue;
    const normalized = normalizeTdValue(row[0]);
    if (!normalized.startsWith(MDR_TD_PREFIX)) continue;
    values.add(normalized);
  }

  if (values.size === 0) {
    console.error('[gspr/td-options] no MDR-TD entries parsed', {
      path: CSV_PATH,
      preview: previewLines,
    });
  }

  return Array.from(values);
}

export async function gsprTdOptions() {
  const tdValues = await loadMdrTdValues();
  const fmeas = await fmeaAll();
  const fmeaByMdrTd = new Map();
  for (const fmea of fmeas) {
    const mdrTd = (fmea?.mdrTd || '').toString().trim();
    if (mdrTd) fmeaByMdrTd.set(mdrTd, fmea);
  }

  const options = tdValues
    .map((label) => {
      const fmea = fmeaByMdrTd.get(label) || null;
      return {
        key: label,
        label,
        mdrTd: label,
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
