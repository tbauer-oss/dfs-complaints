// /api/admin/supplier-report-layout.js – Layout-Konfiguration für Lieferantenbriefe
export const config = { runtime: 'nodejs' };

import { applyAdminCors } from '../_lib/adminCors.js';
import { readJson } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import { supplierReportLetterLayoutGet, supplierReportLetterLayoutSave } from '../_lib/store.js';

const SUPPLIER_TILE = 'supplierEvaluation';
const MAX_LAYOUT_BYTES = 20000;
const TOP_LEVEL_KEYS = new Set([
  'page',
  'header',
  'recipientBlock',
  'dateBlock',
  'titleBlock',
  'bodyStartMm',
  'blocks',
]);
const PAGE_KEYS = ['marginTopMm', 'marginRightMm', 'marginBottomMm', 'marginLeftMm'];
const HEADER_KEYS = ['logoWidthMm', 'headerTopMm'];
const RECIPIENT_KEYS = ['topMm', 'leftMm'];
const DATE_KEYS = ['topMm', 'rightMm'];
const TITLE_KEYS = ['topMm'];
const BLOCK_KEYS = [
  'recipientTopMm',
  'recipientLeftMm',
  'dateTopMm',
  'dateRightMm',
  'subjectTopMm',
  'bodyTopMm',
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

  pickNumericFields(input.page, PAGE_KEYS, page, errors);
  pickNumericFields(input.header, HEADER_KEYS, header, errors);
  pickNumericFields(input.recipientBlock, RECIPIENT_KEYS, recipientBlock, errors);
  pickNumericFields(input.dateBlock, DATE_KEYS, dateBlock, errors);
  pickNumericFields(input.titleBlock, TITLE_KEYS, titleBlock, errors);

  if (input.blocks != null) {
    if (!isPlainObject(input.blocks)) {
      errors.push('Ungültiges Layout-Format.');
    } else {
      for (const key of Object.keys(input.blocks)) {
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

  if (input.bodyStartMm != null) {
    if (!isFiniteNumber(input.bodyStartMm)) {
      errors.push('Ungültige Layout-Werte.');
    } else {
      layout.bodyStartMm = input.bodyStartMm;
    }
  }

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
      if (containsProhibitedContent(body)) {
        return sendError(
          res,
          413,
          'Do not send HTML/base64 to supplier-reports. Only send small JSON.'
        );
      }
      const payload = body?.layout && typeof body.layout === 'object' ? body.layout : body;
      const normalized = normalizeLayoutInput(payload);
      if (!normalized.ok) {
        return sendError(res, 400, normalized.error);
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
