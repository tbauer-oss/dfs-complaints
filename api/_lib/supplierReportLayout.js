// api/_lib/supplierReportLayout.js
export const MAX_LAYOUT_BYTES = 20000;

const FORBIDDEN_KEYWORDS = ['html', 'template', 'base64', 'image'];
const ROOT_KEYS = new Set(['page', 'header', 'recipientBlock', 'dateBlock', 'titleBlock', 'bodyStartMm']);
const SECTION_KEYS = {
  page: new Set(['marginTopMm', 'marginRightMm', 'marginBottomMm', 'marginLeftMm']),
  header: new Set(['logoWidthMm', 'headerTopMm']),
  recipientBlock: new Set(['topMm', 'leftMm']),
  dateBlock: new Set(['topMm', 'rightMm']),
  titleBlock: new Set(['topMm']),
};

function isPlainObject(value) {
  return !!value && typeof value === 'object' && !Array.isArray(value);
}

function hasForbiddenKey(value) {
  if (!isPlainObject(value)) return null;
  for (const key of Object.keys(value)) {
    const lower = key.toLowerCase();
    if (FORBIDDEN_KEYWORDS.some((word) => lower.includes(word))) {
      return key;
    }
    const nested = hasForbiddenKey(value[key]);
    if (nested) return nested;
  }
  return null;
}

function validateNumber(value) {
  return typeof value === 'number' && Number.isFinite(value);
}

function validateSection(section, allowedKeys) {
  if (!isPlainObject(section)) {
    return 'Ungültige Layout-Daten.';
  }
  for (const key of Object.keys(section)) {
    if (!allowedKeys.has(key)) {
      return 'Layout enthält unbekannte Felder.';
    }
    if (!validateNumber(section[key])) {
      return 'Layout-Werte müssen Zahlen sein.';
    }
  }
  return null;
}

export function validateSupplierReportLayout(payload) {
  if (!isPlainObject(payload)) {
    return 'Ungültige Layout-Daten.';
  }
  const forbidden = hasForbiddenKey(payload);
  if (forbidden) {
    return 'Layout enthält nicht erlaubte Felder.';
  }
  for (const key of Object.keys(payload)) {
    if (!ROOT_KEYS.has(key)) {
      return 'Layout enthält unbekannte Felder.';
    }
  }

  for (const [section, keys] of Object.entries(SECTION_KEYS)) {
    if (payload[section] === undefined) continue;
    const error = validateSection(payload[section], keys);
    if (error) return error;
  }

  if (payload.bodyStartMm !== undefined && !validateNumber(payload.bodyStartMm)) {
    return 'Layout-Werte müssen Zahlen sein.';
  }

  return null;
}

export function layoutPayloadSize(payload) {
  try {
    return Buffer.byteLength(JSON.stringify(payload ?? {}), 'utf8');
  } catch {
    return MAX_LAYOUT_BYTES + 1;
  }
}
