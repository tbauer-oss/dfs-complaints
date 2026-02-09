// /api/gspr/analysis.js – GSPR analysis dashboard data
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../_lib/http.js';
import { requirePortalAccess } from '../admin/_guard.js';
import {
  gsprAssessmentsByTd,
  gsprEnsureAssessmentsForTd,
  gsprTdSignoffGet,
} from '../_lib/store.js';
import { GSPR_ITEMS } from '../_lib/gsprRequirements.js';
import { resolveGsprTdInfo } from '../_lib/gsprTdOptions.js';

const GSPR_TILE = 'gspr';
const OPEN_STATUSES = new Set(['not_assessed', 'partial', 'not_fulfilled']);
const COMPLETED_STATUSES = new Set(['fulfilled', 'not_applicable']);

function parseBool(value) {
  if (value == null) return false;
  const v = String(value).trim().toLowerCase();
  return v === 'true' || v === '1' || v === 'yes' || v === 'on';
}

function parseChapter(value) {
  const v = (value || '').toString().trim().toUpperCase();
  if (v === 'I' || v === '1') return 1;
  if (v === 'II' || v === '2') return 2;
  if (v === 'III' || v === '3') return 3;
  return null;
}

function parseStatusList(value) {
  if (!value) return [];
  const list = String(value)
    .split(',')
    .map((v) => v.trim().toLowerCase())
    .filter(Boolean);
  return Array.from(new Set(list));
}

function isOpen(status) {
  return OPEN_STATUSES.has(status);
}

function isCompleted(status) {
  return COMPLETED_STATUSES.has(status);
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: GSPR_TILE, write: false, allowPrrc: true });
  if (!actor) return;

  try {
    if (req.method !== 'GET') return bad(res, 'method not allowed', 405);
    const tdId = (req.query?.tdId || '').toString();
    if (!tdId) return bad(res, 'tdId missing', 400);

    const td = await resolveGsprTdInfo(tdId);
    if (!td) return bad(res, 'td not found', 404);

    const signoff = await gsprTdSignoffGet(tdId);
    await gsprEnsureAssessmentsForTd(tdId, { status: signoff.status, actor });

    const chapter = parseChapter(req.query?.chapter);
    const statusFilter = parseStatusList(req.query?.status);
    const onlyOpen = parseBool(req.query?.openOnly);
    const onlyOverdue = parseBool(req.query?.overdueOnly);
    const onlyDueSoon = parseBool(req.query?.dueSoonOnly);
    const onlyMissingEvidence = parseBool(req.query?.missingEvidenceOnly);
    const ownerFilter = (req.query?.owner || '').toString().trim().toLowerCase();
    const search = (req.query?.search || '').toString().trim().toLowerCase();
    const dueSoonDays = Math.max(1, Number(req.query?.dueSoonDays || 14) || 14);

    const page = Math.max(1, Number(req.query?.page || 1) || 1);
    const pageSize = Math.max(1, Math.min(200, Number(req.query?.pageSize || 50) || 50));

    const assessments = await gsprAssessmentsByTd(tdId);
    const assessmentByRequirement = new Map(assessments.map((a) => [a.requirementId, a]));

    const now = new Date();
    const dueSoonCutoff = new Date(now);
    dueSoonCutoff.setUTCDate(dueSoonCutoff.getUTCDate() + dueSoonDays);

    const requirements = GSPR_ITEMS.filter((item) => item.isAssessable)
      .filter((item) => (chapter ? item.chapter === chapter : true));

    const rows = [];
    for (const requirement of requirements) {
      const assessment = assessmentByRequirement.get(requirement.id) || {
        status: 'not_assessed',
        owner: '',
        evidence: [],
        dueDate: null,
        updatedAt: null,
      };
      const status = String(assessment.status || 'not_assessed').toLowerCase();
      if (statusFilter.length && !statusFilter.includes(status)) continue;
      if (onlyOpen && !isOpen(status)) continue;
      if (ownerFilter && !String(assessment.owner || '').toLowerCase().includes(ownerFilter)) continue;

      const dueDate = assessment.dueDate ? new Date(assessment.dueDate) : null;
      const overdue = dueDate ? dueDate < now && isOpen(status) : false;
      const dueSoon = dueDate ? dueDate >= now && dueDate <= dueSoonCutoff && isOpen(status) : false;
      if (onlyOverdue && !overdue) continue;
      if (onlyDueSoon && !dueSoon) continue;

      const missingEvidence = status !== 'not_assessed' && (assessment.evidence || []).length === 0;
      if (onlyMissingEvidence && !missingEvidence) continue;

      if (search) {
        const haystack = [
          requirement.id,
          requirement.ref,
          requirement.title,
          requirement.text,
          requirement.contextText,
          assessment.owner,
        ]
          .filter(Boolean)
          .join(' ')
          .toLowerCase();
        if (!haystack.includes(search)) continue;
      }

      rows.push({
        tdId,
        mdrTd: td.mdrTd || td.label || tdId,
        requirementId: requirement.id,
        ref: requirement.ref,
        title: requirement.title,
        chapter: requirement.chapter,
        status,
        owner: assessment.owner || '',
        dueDate: assessment.dueDate || null,
        updatedAt: assessment.updatedAt || null,
        missingEvidence,
        overdue,
        dueSoon,
      });
    }

    const summary = {
      total: rows.length,
      fulfilled: rows.filter((row) => row.status === 'fulfilled').length,
      notApplicable: rows.filter((row) => row.status === 'not_applicable').length,
      open: rows.filter((row) => isOpen(row.status)).length,
      overdue: rows.filter((row) => row.overdue).length,
      dueSoon: rows.filter((row) => row.dueSoon).length,
      completed: rows.filter((row) => isCompleted(row.status)).length,
    };

    const total = rows.length;
    const start = (page - 1) * pageSize;
    const items = rows.slice(start, start + pageSize);

    return ok(res, {
      ok: true,
      tdId,
      summary,
      total,
      page,
      pageSize,
      items,
    });
  } catch (err) {
    console.error('[gspr/analysis] error', err);
    return bad(res, err?.message || 'server error', 500);
  }
}
