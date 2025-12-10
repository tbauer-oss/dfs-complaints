// api/admin/prrc.js
export const config = { runtime: 'nodejs' };

import { setCors, ok, bad, noContent, methodNotAllowed } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import { normalizeRole, PORTAL_ROLES } from '../_lib/portalAuth.js';
import { normalizeDepartments, hasDepartmentOverlap } from '../_lib/departments.js';

const PRRC_VALUES = new Set(['N/A', 'SUB', 'A', 'B', 'C', 'D']);

function normalizePrrcClassification(value) {
  const raw = (value ?? '').toString().trim();
  if (!raw) return null;
  const upper = raw.toUpperCase();
  if (PRRC_VALUES.has(upper)) return upper === 'SUB' ? 'Sub' : upper;
  return null;
}

function filterByDepartments(list = [], actor) {
  const role = normalizeRole(actor?.role || '');
  if (role === PORTAL_ROLES.superuser || role === PORTAL_ROLES.readonly) return list;
  const deps = normalizeDepartments(actor?.assignedDepartments || []);
  if (deps.length === 0) return [];
  return list.filter((c) => hasDepartmentOverlap(deps, c?.internalDepartments));
}

function statsFromComplaints(list = []) {
  const counts = { 'N/A': 0, Sub: 0, A: 0, B: 0, C: 0, D: 0 };
  let unrated = 0;
  let open = 0;
  let incidents = 0;
  let potentiallyReportable = 0;
  let reportableCases = 0;

  for (const c of list) {
    const classification = normalizePrrcClassification(c?.prrcClassification) || 'N/A';
    counts[classification] = (counts[classification] || 0) + 1;
    if (!normalizePrrcClassification(c?.prrcClassification)) unrated += 1;
    if (Number(c?.status ?? 0) !== 5) open += 1;
    if (['A', 'B', 'C', 'D'].includes(classification)) incidents += 1;
    if (['B', 'C', 'D'].includes(classification) || c?.isPotentiallyReportable === true) {
      potentiallyReportable += 1;
    }
    if (c?.prrcReportableCase === true) reportableCases += 1;
  }

  const total = list.length || 1;
  const incidentShare = Number(((incidents / total) * 100).toFixed(1));

  return {
    counts,
    unrated,
    open,
    incidents,
    total: list.length,
    incidentShare,
    potentiallyReportable,
    reportableCases,
  };
}

export default async function handler(req, res) {
  setCors(req, res);

  if (req.method === 'OPTIONS') return noContent(res);

  const actor = await requirePortalAccess(req, res, { tile: 'prrc', allowPrrc: true });
  if (!actor) return;

  const role = normalizeRole(actor?.role || actor?.portalRole || '');
  const isPrrc = actor?.isPRRC === true || role === PORTAL_ROLES.prrc || role === PORTAL_ROLES.superuser;
  if (!isPrrc) return bad(res, 'forbidden for role', 403);

  if (req.method !== 'GET') return methodNotAllowed(res, ['GET']);

  const { complaintsAll } = await import('../_lib/store.js');

  const raw = filterByDepartments(await complaintsAll(), actor);

  const q = req.query || {};
  const from = q.from ? Number(new Date(q.from)) : null;
  const to = q.to ? Number(new Date(q.to)) : null;

  const filtered = raw.filter((c) => {
    if (from && Number(c?.createdAt) < from) return false;
    if (to && Number(c?.createdAt) > to) return false;
    return true;
  });

  const normalized = filtered.map((c) => ({
    ...c,
    history: Array.isArray(c?.history) ? c.history : [],
  }));

  return ok(res, {
    stats: statsFromComplaints(normalized),
    complaints: normalized,
  });
}
