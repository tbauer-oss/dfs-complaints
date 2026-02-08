// /api/td.js – MDR-TD list (reuse FMEA data)
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from './_lib/http.js';
import { requirePortalAccess } from './admin/_guard.js';
import { fmeaAll } from './_lib/store.js';

const GSPR_TILE = 'gspr';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: GSPR_TILE, write: false });
  if (!actor) return;

  try {
    if (req.method !== 'GET') return bad(res, 'method not allowed', 405);
    const list = await fmeaAll();
    const mapped = list.map((fmea) => ({
      id: fmea.id,
      mdrTd: fmea.mdrTd,
      title: fmea.title,
      productGroup: fmea.productGroup,
      medicalProduct: fmea.medicalProduct,
      updatedAt: fmea.updatedAt,
      active: fmea.active !== false,
      archivedAt: fmea.archivedAt || null,
    }));
    return ok(res, { ok: true, list: mapped });
  } catch (err) {
    console.error('[td] error', err);
    return bad(res, err?.message || 'server error', 500);
  }
}
