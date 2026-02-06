// /api/capa/dashboard – Aggregated CAPA metrics for admin dashboard
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed } from '../_lib/http.js';
import { requirePortalAccess } from '../admin/_guard.js';
import { capaAll } from '../_lib/store.js';

const CAPA_TILE = 'capaReports';

function parseTimestamp(value) {
  if (value === null || value === undefined) return null;
  const num = Number(value);
  if (!Number.isNaN(num) && num > 0) return num;
  const parsed = Date.parse(value);
  if (!Number.isNaN(parsed)) return parsed;
  return null;
}

function startOfTodayMs(now = Date.now()) {
  const d = new Date(now);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

function earliestDueDate(capa) {
  const actions =
    capa?.sections?.d4?.correctiveActions || capa?.sections?.correctiveActions || [];
  let earliest = null;
  for (const action of actions) {
    const ts = parseTimestamp(action?.dueDate);
    if (!ts) continue;
    if (earliest === null || ts < earliest) earliest = ts;
  }
  return earliest;
}

function isRecurring(capa) {
  return Boolean(
    (capa?.parentCapaId ?? '').toString().trim() ||
      (capa?.parentCapaNumber ?? '').toString().trim() ||
      capa?.isRecurring === true ||
      capa?.recurrence === true ||
      (capa?.recurrenceOf ?? '').toString().trim(),
  );
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  if (req.method !== 'GET') return methodNotAllowed(res);

  const actor = await requirePortalAccess(req, res, { tile: CAPA_TILE });
  if (!actor) return;

  try {
    const list = await capaAll();
    const today = startOfTodayMs();
    const soon = today + 7 * 24 * 60 * 60 * 1000;

    let totalOpen = 0;
    let overdue = 0;
    let dueSoon = 0;
    let recurrenceCount = 0;
    let durationSum = 0;
    let durationCount = 0;
    const departmentCounts = new Map();
    const criticalCapas = [];

    for (const capa of list) {
      const status = (capa?.status || '').toString();
      const isOpen = status === 'open' || status === 'inProgress' || status === 'in_progress';
      const dept = (capa?.sections?.d1?.area || capa?.sections?.area || '').toString().trim() || 'Unbekannt';
      const dueDate = earliestDueDate(capa);

      if (isOpen) {
        totalOpen += 1;
        const current = departmentCounts.get(dept) || 0;
        departmentCounts.set(dept, current + 1);

        if (dueDate) {
          if (dueDate < today) {
            overdue += 1;
            criticalCapas.push({ ...capa, department: dept, dueDate });
          } else if (dueDate <= soon) {
            dueSoon += 1;
            criticalCapas.push({ ...capa, department: dept, dueDate });
          }
        }
      }

      if (isRecurring(capa)) {
        recurrenceCount += 1;
      }

      const closed = status === 'closed' || status === 'done';
      if (closed) {
        const start = parseTimestamp(capa?.createdAt);
        const end = parseTimestamp(capa?.closedAt) || parseTimestamp(capa?.updatedAt);
        if (start && end && end >= start) {
          durationSum += (end - start) / (24 * 60 * 60 * 1000);
          durationCount += 1;
        }
      }
    }

    const byDepartment = Array.from(departmentCounts.entries())
      .map(([department, openCount]) => ({ department, openCount }))
      .sort((a, b) => b.openCount - a.openCount || a.department.localeCompare(b.department));

    const avgDurationDays = durationCount > 0 ? Number((durationSum / durationCount).toFixed(1)) : 0;

    return ok(res, {
      ok: true,
      totalOpen,
      overdue,
      dueSoon,
      avgDurationDays,
      byDepartment,
      recurrenceCount,
      criticalCapas: criticalCapas.map((c) => ({
        id: c.id,
        capaNumber: c.capaNumber,
        title: c.title,
        status: c.status,
        department: c.department,
        dueDate: c.dueDate || null,
      })),
    });
  } catch (err) {
    console.error('[capa/dashboard] error', err);
    return bad(res, 'server error', 500);
  }
}
