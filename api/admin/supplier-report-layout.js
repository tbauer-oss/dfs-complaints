// /api/admin/supplier-report-layout.js – Layout-Konfiguration für Lieferantenbriefe
export const config = { runtime: 'nodejs' };

import { applyAdminCors } from '../_lib/adminCors.js';
import { ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
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
  'id',
  'version',
  'updatedAt',
  'updatedBy',
  'history',
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

  const wantsWrite = ['POST'].includes(req.method);
  const actor = await requirePortalAccess(req, res, { tile: SUPPLIER_TILE, write: wantsWrite });
  if (!actor) return;

  try {
    const type = (req.query?.type || '').toString().toLowerCase();
    const layoutType = type || 'letter';
    if (!['letter', 'report'].includes(layoutType)) {
      return bad(res, 'Ungültiger Layout-Typ.', 400);
    }

    if (req.method === 'GET') {
      const layout = await supplierReportLetterLayoutGet();
      const reportLayout = isPlainObject(layout.reportLayout) ? layout.reportLayout : null;
      const payload = layoutType === 'report' ? reportLayout || layout : layout;
      return ok(res, { ok: true, layout: payload });
    }

    if (req.method === 'POST') {
      const raw = typeof req.body === 'string' ? req.body : JSON.stringify(req.body ?? {});
      if (Buffer.byteLength(raw || '', 'utf8') > MAX_LAYOUT_BYTES) {
        return bad(res, 'layout payload too large', 413);
      }
      const body = readJson(req) || {};
      const payload = body?.layout && typeof body.layout === 'object' ? body.layout : body;
      const normalized = normalizeLayoutInput(payload);
      if (!normalized.ok) {
        return bad(res, normalized.error, 400);
      }
      // Layouts must stay small: only numeric coordinates (no HTML/base64/logo payloads).
      if (layoutType === 'report') {
        const updated = await supplierReportLetterLayoutSave(
          { reportLayout: normalized.layout },
          { updatedBy: actor.email }
        );
        return ok(res, { ok: true, layout: updated.reportLayout || normalized.layout });
      }
      const updated = await supplierReportLetterLayoutSave(normalized.layout, { updatedBy: actor.email });
      return ok(res, { ok: true, layout: updated });
    }

    return methodNotAllowed(res, req.method, ['GET', 'POST']);
  } catch (err) {
    console.error('[admin/supplier-report-layout] failed', err);
    return bad(res, 'Layout-Konfiguration konnte nicht gespeichert werden.', 500);
  }
}
