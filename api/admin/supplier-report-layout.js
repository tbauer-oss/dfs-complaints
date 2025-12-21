// /api/admin/supplier-report-layout.js – Layout-Konfiguration für Lieferantenbriefe
export const config = {
  runtime: 'nodejs',
  api: {
    bodyParser: { sizeLimit: '2mb' },
  },
};

import { applyAdminCors } from '../_lib/adminCors.js';
import { readJson } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import { supplierReportLetterLayoutGet, supplierReportLetterLayoutSave } from '../_lib/store.js';

const SUPPLIER_TILE = 'supplierEvaluation';
const MAX_LAYOUT_BYTES = 200 * 1024;
const TOP_LEVEL_KEYS = new Set(['version', 'type', 'page', 'blocks']);
const PAGE_KEYS = ['marginTopMm', 'marginRightMm', 'marginBottomMm', 'marginLeftMm'];
const BLOCK_KEYS = [
  'logoWidthMm',
  'headerTopMm',
  'recipientTopMm',
  'recipientLeftMm',
  'dateTopMm',
  'dateRightMm',
  'subjectTopMm',
  'bodyTopMm',
];
const SIGNATURE_KEYS = [
  'enabled',
  'startY',
  'compact',
  'showName',
  'showTitle',
  'showEmail',
  'showLegalFooter',
];

const isPlainObject = (value) => Boolean(value) && typeof value === 'object' && !Array.isArray(value);
const isFiniteNumber = (value) => typeof value === 'number' && Number.isFinite(value);
const BASE64_PATTERN = /^[A-Za-z0-9+/=]+$/;

function sendJson(res, statusCode, payload) {
  if (!res.getHeader('Content-Type')) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
  }
  res.statusCode = statusCode;
  res.end(JSON.stringify(payload ?? {}));
}

function sendError(res, statusCode, message, extra) {
  const body = typeof extra === 'object' && extra !== null ? { error: message, ...extra } : { error: message };
  sendJson(res, statusCode, body);
}

function containsProhibitedContent(value, keyPath = '') {
  if (typeof value === 'string') {
    const loweredKey = keyPath.toLowerCase();
    if (loweredKey.includes('html')) return true;
    if (value.length > 500) return true;
    if (/<\/?[a-z][\s\S]*>/i.test(value)) return true;
    if (value.length > 500 && BASE64_PATTERN.test(value)) return true;
    return false;
  }
  if (Array.isArray(value)) {
    return value.some((item, index) => containsProhibitedContent(item, `${keyPath}[${index}]`));
  }
  if (isPlainObject(value)) {
    return Object.entries(value).some(([key, val]) => containsProhibitedContent(val, key));
  }
  return false;
}

function pickNumericFields(source, allowedKeys, target, errors) {
  if (source == null) return;
  if (!isPlainObject(source)) {
    errors.push('Ungültiges Layout-Format.');
    return;
  }
  for (const key of Object.keys(source)) {
    if (!allowedKeys.includes(key)) {
      errors.push('Ungültiges Layout-Format.');
      return;
    }
    if (!isFiniteNumber(source[key])) {
      errors.push('Ungültige Layout-Werte.');
      return;
    }
    target[key] = source[key];
  }
}

function normalizeLayoutInput(input) {
  const errors = [];
  if (!isPlainObject(input)) {
    return { ok: false, error: 'Ungültiges Layout-Format.' };
  }
  for (const key of Object.keys(input)) {
    if (!TOP_LEVEL_KEYS.has(key)) {
      return { ok: false, error: 'Ungültiges Layout-Format.' };
    }
  }

  const layout = {};
  const page = {};
  const header = {};
  const recipientBlock = {};
  const dateBlock = {};
  const titleBlock = {};
  const signature = {};

  pickNumericFields(input.page, PAGE_KEYS, page, errors);

  if (input.blocks != null) {
    if (!isPlainObject(input.blocks)) {
      errors.push('Ungültiges Layout-Format.');
    } else {
      for (const key of Object.keys(input.blocks)) {
        if (key === 'signature') {
          const raw = input.blocks.signature;
          if (!isPlainObject(raw)) {
            errors.push('Ungültiges Layout-Format.');
            break;
          }
          for (const sigKey of Object.keys(raw)) {
            if (!SIGNATURE_KEYS.includes(sigKey)) {
              errors.push('Ungültiges Layout-Format.');
              break;
            }
            const value = raw[sigKey];
            if (sigKey === 'startY') {
              if (!isFiniteNumber(value)) {
                errors.push('Ungültige Layout-Werte.');
                break;
              }
            } else if (typeof value !== 'boolean') {
              errors.push('Ungültige Layout-Werte.');
              break;
            }
            signature[sigKey] = value;
          }
          if (errors.length) break;
          continue;
        }
        if (!BLOCK_KEYS.includes(key)) {
          errors.push('Ungültiges Layout-Format.');
          break;
        }
        if (!isFiniteNumber(input.blocks[key])) {
          errors.push('Ungültige Layout-Werte.');
          break;
        }
      }
      if (!errors.length) {
        if (!isFiniteNumber(header.logoWidthMm) && isFiniteNumber(input.blocks.logoWidthMm)) {
          header.logoWidthMm = input.blocks.logoWidthMm;
        }
        if (!isFiniteNumber(header.headerTopMm) && isFiniteNumber(input.blocks.headerTopMm)) {
          header.headerTopMm = input.blocks.headerTopMm;
        }
        if (!isFiniteNumber(recipientBlock.topMm) && isFiniteNumber(input.blocks.recipientTopMm)) {
          recipientBlock.topMm = input.blocks.recipientTopMm;
        }
        if (!isFiniteNumber(recipientBlock.leftMm) && isFiniteNumber(input.blocks.recipientLeftMm)) {
          recipientBlock.leftMm = input.blocks.recipientLeftMm;
        }
        if (!isFiniteNumber(dateBlock.topMm) && isFiniteNumber(input.blocks.dateTopMm)) {
          dateBlock.topMm = input.blocks.dateTopMm;
        }
        if (!isFiniteNumber(dateBlock.rightMm) && isFiniteNumber(input.blocks.dateRightMm)) {
          dateBlock.rightMm = input.blocks.dateRightMm;
        }
        if (!isFiniteNumber(titleBlock.topMm) && isFiniteNumber(input.blocks.subjectTopMm)) {
          titleBlock.topMm = input.blocks.subjectTopMm;
        }
        if (!isFiniteNumber(layout.bodyStartMm) && isFiniteNumber(input.blocks.bodyTopMm)) {
          layout.bodyStartMm = input.blocks.bodyTopMm;
        }
      }
    }
  }

  if (Object.keys(page).length) layout.page = page;
  if (Object.keys(header).length) layout.header = header;
  if (Object.keys(recipientBlock).length) layout.recipientBlock = recipientBlock;
  if (Object.keys(dateBlock).length) layout.dateBlock = dateBlock;
  if (Object.keys(titleBlock).length) layout.titleBlock = titleBlock;
  if (Object.keys(signature).length) layout.signature = signature;

  if (errors.length) {
    return { ok: false, error: errors[0] };
  }
  return { ok: true, layout };
}

export default async function handler(req, res) {
  if (applyAdminCors(req, res)) return;

  try {
    if (req.method === 'POST') {
      const raw = typeof req.body === 'string' ? req.body : JSON.stringify(req.body || {});
      if (Buffer.byteLength(raw || '', 'utf8') > MAX_LAYOUT_BYTES) {
        return sendError(res, 413, 'payload too large', { limit: MAX_LAYOUT_BYTES });
      }
    }

    const wantsWrite = ['POST'].includes(req.method);
    const actor = await requirePortalAccess(req, res, { tile: SUPPLIER_TILE, write: wantsWrite });
    if (!actor) return;

    const type = (req.query?.type || '').toString().toLowerCase();
    const layoutType = type || 'letter';
    if (!['letter', 'report'].includes(layoutType)) {
      return sendError(res, 400, 'Ungültiger Layout-Typ.');
    }

    if (req.method === 'GET') {
      const layout = await supplierReportLetterLayoutGet();
      const keyedLayout = layout[`supplierReportLayout:${layoutType}`];
      const reportLayout = isPlainObject(layout.reportLayout) ? layout.reportLayout : null;
      const payload = keyedLayout && isPlainObject(keyedLayout)
        ? keyedLayout
        : layoutType === 'report'
          ? reportLayout || layout
          : layout;
      return sendJson(res, 200, { ok: true, layout: payload });
    }

    if (req.method === 'POST') {
      const body = readJson(req) || {};
      const payloadSize = Buffer.byteLength(JSON.stringify(body), 'utf8');
      if (payloadSize > 200 * 1024) {
        return sendError(res, 413, 'payload too large', { limit: 200 * 1024 });
      }
      if (containsProhibitedContent(body)) {
        return sendError(
          res,
          400,
          'layout contains oversized string (do not send html/base64)'
        );
      }
      const payload = body;
      const normalized = normalizeLayoutInput(payload);
      if (!normalized.ok) {
        return sendError(res, 400, normalized.error);
      }
      if (payload.type && payload.type !== layoutType) {
        return sendError(res, 400, 'Ungültiger Layout-Typ.');
      }
      // Layouts must stay small: only numeric coordinates (no HTML/base64/logo payloads).
      const layoutKey = `supplierReportLayout:${layoutType}`;
      if (layoutType === 'report') {
        const updated = await supplierReportLetterLayoutSave(
          { reportLayout: normalized.layout, [layoutKey]: normalized.layout },
          { updatedBy: actor.email }
        );
        return sendJson(res, 200, { ok: true, layout: updated[layoutKey] || normalized.layout });
      }
      const updated = await supplierReportLetterLayoutSave(
        { ...normalized.layout, [layoutKey]: normalized.layout },
        { updatedBy: actor.email }
      );
      return sendJson(res, 200, { ok: true, layout: updated[layoutKey] || normalized.layout });
    }

    return sendError(res, 405, 'method not allowed');
  } catch (err) {
    console.error('[admin/supplier-report-layout] failed', err);
    applyAdminCors(req, res);
    return sendError(res, 500, 'Layout-Konfiguration konnte nicht gespeichert werden.');
  }
}
