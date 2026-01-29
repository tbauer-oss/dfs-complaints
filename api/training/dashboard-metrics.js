// /api/training/dashboard-metrics – Aggregated Training metrics for admin dashboard
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed } from '../_lib/http.js';
import { requirePortalAccess } from '../admin/_guard.js';
import {
  trainingNeedsAll,
  trainingProgramsAll,
  trainingRecordsAll,
  trainingQuestionnairesAll,
} from '../_lib/store.js';

const TRAINING_TILE = 'trainings';

const DAY_MS = 24 * 60 * 60 * 1000;

function parseDateValue(value) {
  if (!value) return null;
  if (value instanceof Date) return value;
  if (typeof value === 'number') {
    const d = new Date(value);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  const raw = value.toString().trim();
  if (!raw) return null;
  const direct = new Date(raw);
  if (!Number.isNaN(direct.getTime())) return direct;
  const match = raw.match(/^(\d{1,2})\.(\d{1,2})\.(\d{2,4})$/);
  if (match) {
    const day = Number(match[1]);
    const month = Number(match[2]);
    const year = Number(match[3].length === 2 ? `20${match[3]}` : match[3]);
    if (Number.isNaN(day) || Number.isNaN(month) || Number.isNaN(year)) return null;
    const d = new Date(year, month - 1, day);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  return null;
}

function startOfDayMs(date = new Date()) {
  const d = new Date(date);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

function startOfWeekMs(date = new Date()) {
  const d = new Date(date);
  const day = d.getDay();
  const offset = (day + 6) % 7; // Monday start
  d.setDate(d.getDate() - offset);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

function isNeedApproved(status = '') {
  const normalized = status.toString().trim().toLowerCase();
  return normalized === 'glapproved' || normalized === 'scheduled' || normalized === 'approved';
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  if (req.method !== 'GET') return methodNotAllowed(res);

  const actor = await requirePortalAccess(req, res, { tile: TRAINING_TILE });
  if (!actor) return;

  try {
    const [needs, programs, trainings, questionnaires] = await Promise.all([
      trainingNeedsAll(),
      trainingProgramsAll(),
      trainingRecordsAll(),
      trainingQuestionnairesAll(),
    ]);

    const now = new Date();
    const currentYear = now.getFullYear();
    const todayStart = startOfDayMs(now);
    const weekStart = startOfWeekMs(now);
    const weekEnd = weekStart + 7 * DAY_MS;

    const openNeedsList = needs.filter((need) => !isNeedApproved(need.status));
    const openNeeds = openNeedsList.length;
    const newNeeds = needs.filter((need) => {
      const status = (need.status || '').toString().trim().toLowerCase();
      return status === 'submitted';
    }).length;
    const overdueNeeds = openNeedsList.filter((need) => {
      const year = Number(need.year || currentYear);
      if (!year) return false;
      const deadline = new Date(year, 11, 15);
      return todayStart > startOfDayMs(deadline);
    }).length;

    const trainingsThisYear = trainings.filter((t) => Number(t.year) === currentYear && !t.deletedAt);
    const plannedTrainingsThisYear = trainingsThisYear.filter((t) => {
      const status = (t.status || '').toString().trim().toLowerCase();
      return status !== 'cancelled';
    }).length;

    let trainingsToday = 0;
    let trainingsThisWeek = 0;
    let openTrainings = 0;
    let completedTrainings = 0;

    for (const training of trainingsThisYear) {
      const status = (training.status || '').toString().trim().toLowerCase();
      if (status === 'completed') {
        completedTrainings += 1;
      } else if (status !== 'cancelled') {
        openTrainings += 1;
      }

      const startDate = parseDateValue(training.startDate || training.date);
      if (!startDate) continue;
      const startMs = startDate.getTime();
      if (startMs >= todayStart && startMs < todayStart + DAY_MS) {
        trainingsToday += 1;
      }
      if (startMs >= weekStart && startMs < weekEnd) {
        trainingsThisWeek += 1;
      }
    }

    const openEffectivenessChecks = trainingsThisYear.filter((t) => {
      const status = (t.wkStatus || '').toString().trim().toLowerCase();
      if (!t.wkMethod || !t.wkDueAt) return false;
      return status && status !== 'done';
    }).length;

    const overdueEffectivenessChecks = trainingsThisYear.filter((t) => {
      const status = (t.wkStatus || '').toString().trim().toLowerCase();
      if (!t.wkMethod || !t.wkDueAt) return false;
      if (!status || status === 'done') return false;
      return Number(t.wkDueAt) < Date.now();
    }).length;

    const ineffectiveTrainings = questionnaires.filter((q) => q.needsRetraining).length;

    const activeProgram = programs
      .filter((p) => p && p.year)
      .sort((a, b) => Number(b.year) - Number(a.year))[0];
    const activeProgramYear = activeProgram?.year ?? currentYear;
    const programStatus = (activeProgram?.status || '').toString().trim();
    const programApproved = programStatus.toLowerCase() === 'approved';

    return ok(res, {
      ok: true,
      openNeeds,
      overdueNeeds,
      newNeeds,
      plannedTrainingsThisYear,
      trainingsThisYear: trainingsThisYear.length,
      trainingsToday,
      trainingsThisWeek,
      openTrainings,
      completedTrainings,
      openEffectivenessChecks,
      overdueEffectivenessChecks,
      ineffectiveTrainings,
      activeProgramYear,
      programStatus,
      programApproved,
    });
  } catch (err) {
    console.error('[training/dashboard-metrics] error', err);
    return bad(res, 'server error', 500);
  }
}
