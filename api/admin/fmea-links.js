// /api/admin/fmea-links.js – Übersicht aller FMEA-Verknüpfungen
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import { fmeaAll } from '../_lib/store.js';

const FMEA_TILE = 'fmea';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { tile: FMEA_TILE, write: false });
  if (!actor) return;

  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);

  try {
    const list = await fmeaAll();
    const links = [];
    for (const fmea of list) {
      for (const risk of fmea.risks || []) {
        links.push({
          fmeaId: fmea.id,
          mdrTd: fmea.mdrTd,
          riskId: risk.id,
          riskNumber: risk.riskNumber,
          hazard: risk.hazard,
          riskLevel: risk.riskLevel,
          riskLevelAfter: risk.riskLevelAfter,
          residualRiskOk: risk.residualRiskOk,
          newHazard: risk.newHazard,
          linkedComplaints: risk.linkedComplaints || [],
          linkedCapas: risk.linkedCapas || [],
        });
      }
    }
    return ok(res, { ok: true, links });
  } catch (err) {
    console.error('[admin/fmea-links] error', err);
    return bad(res, 'server error', 500);
  }
}
