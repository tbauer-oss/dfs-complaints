// /api/cron/training-recurrence.js – Cron job for recurring trainings
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../_lib/http.js';
import {
  trainingNeedsAll,
  trainingNeedSave,
  trainingNeedUpdate,
  trainingRecordsAll,
  trainingRecordSave,
  trainingRecordUpdate,
} from '../_lib/store.js';

const INTERVAL_MONTHS = new Map([
  ['vierteljährlich', 3],
  ['halbjährlich', 6],
  ['jährlich', 12],
  ['alle 2 Jahre', 24],
  ['alle 3 Jahre', 36],
  ['alle 4 Jahre', 48],
  ['alle 5 Jahre', 60],
]);

function pad(value) {
  return value.toString().padStart(2, '0');
}

function parseDate(value) {
  if (!value || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const [y, m, d] = value.split('-').map((v) => Number(v));
  return new Date(y, m - 1, d);
}

function formatDate(date) {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function periodToDate(type, value) {
  if (!value) return null;
  if (type === 'date') return parseDate(value);
  if (type === 'month') {
    const match = /^(\d{4})-(\d{2})$/.exec(value);
    if (!match) return null;
    return new Date(Number(match[1]), Number(match[2]) - 1, 1);
  }
  if (type === 'quarter') {
    const match = /^(\d{4})-Q([1-4])$/.exec(value);
    if (!match) return null;
    const month = (Number(match[2]) - 1) * 3 + 1;
    return new Date(Number(match[1]), month - 1, 1);
  }
  if (type === 'halfYear') {
    const match = /^(\d{4})-H([1-2])$/.exec(value);
    if (!match) return null;
    const month = Number(match[2]) === 1 ? 1 : 7;
    return new Date(Number(match[1]), month - 1, 1);
  }
  return null;
}

function addMonthsToPeriod(type, value, months) {
  if (!value) return null;
  if (type === 'date') {
    const date = parseDate(value);
    if (!date) return null;
    date.setMonth(date.getMonth() + months);
    return formatDate(date);
  }
  if (type === 'month') {
    const match = /^(\d{4})-(\d{2})$/.exec(value);
    if (!match) return null;
    const total = Number(match[1]) * 12 + (Number(match[2]) - 1) + months;
    const nextYear = Math.floor(total / 12);
    const nextMonth = (total % 12) + 1;
    return `${nextYear}-${pad(nextMonth)}`;
  }
  if (type === 'quarter') {
    const match = /^(\d{4})-Q([1-4])$/.exec(value);
    if (!match) return null;
    const baseMonth = (Number(match[2]) - 1) * 3 + 1;
    const total = Number(match[1]) * 12 + (baseMonth - 1) + months;
    const nextYear = Math.floor(total / 12);
    const nextMonth = (total % 12) + 1;
    const quarter = Math.floor((nextMonth - 1) / 3) + 1;
    return `${nextYear}-Q${quarter}`;
  }
  if (type === 'halfYear') {
    const match = /^(\d{4})-H([1-2])$/.exec(value);
    if (!match) return null;
    const baseMonth = Number(match[2]) === 1 ? 1 : 7;
    const total = Number(match[1]) * 12 + (baseMonth - 1) + months;
    const nextYear = Math.floor(total / 12);
    const nextMonth = (total % 12) + 1;
    const half = nextMonth <= 6 ? 'H1' : 'H2';
    return `${nextYear}-${half}`;
  }
  return null;
}

function addMonthsToDateString(value, months) {
  const date = parseDate(value);
  if (!date) return null;
  date.setMonth(date.getMonth() + months);
  return formatDate(date);
}

function extractYear(value) {
  return Number(String(value || '').slice(0, 4)) || new Date().getFullYear();
}

function plannedPeriodLabel(type, value) {
  if (!value) return '';
  if (type === 'date') return `Datum: ${value}`;
  if (type === 'month') return `Monat: ${value}`;
  if (type === 'quarter') {
    const [year, quarter] = value.split('-');
    return `Quartal: ${quarter} ${year}`;
  }
  if (type === 'halfYear') {
    const [year, half] = value.split('-');
    return `Halbjahr: ${half} ${year}`;
  }
  return value;
}

async function processNeeds(now) {
  const needs = await trainingNeedsAll();
  const existing = new Set(
    needs
      .filter((entry) => entry.parentRecurringId && entry.plannedPeriodValue)
      .map((entry) => `${entry.parentRecurringId}:${entry.plannedPeriodValue}`)
  );
  let generated = 0;
  let updated = 0;

  for (const need of needs) {
    if (need.parentRecurringId) continue;
    if (need.intervalType !== 'recurring' || !need.recurrenceActive) continue;
    const months = INTERVAL_MONTHS.get(need.intervalValue || '');
    if (!months) {
      console.info('[training/recurrence] skip need interval', { id: need.id, interval: need.intervalValue });
      continue;
    }
    if (!need.plannedPeriodValue || !need.plannedPeriodType) continue;
    let nextPeriod = need.nextDuePeriod || addMonthsToPeriod(need.plannedPeriodType, need.plannedPeriodValue, months);
    if (!nextPeriod) continue;

    let lastGeneratedAt = need.lastGeneratedAt || null;
    while (true) {
      const dueDate = periodToDate(need.plannedPeriodType, nextPeriod);
      if (!dueDate || dueDate > now) break;
      const key = `${need.id}:${nextPeriod}`;
      if (!existing.has(key)) {
        const updatedItems = (need.items || []).map((item) => ({
          ...item,
          timeframe: plannedPeriodLabel(need.plannedPeriodType, nextPeriod),
        }));
        const instance = {
          ...need,
          id: '',
          year: extractYear(nextPeriod),
          plannedPeriodValue: nextPeriod,
          items: updatedItems,
          parentRecurringId: need.id,
          isAutoGenerated: true,
          recurrenceActive: false,
          nextDuePeriod: null,
          lastGeneratedAt: null,
          createdBy: 'system/cron',
          updatedBy: 'system/cron',
        };
        await trainingNeedSave(instance);
        existing.add(key);
        generated += 1;
        lastGeneratedAt = Date.now();
      }
      nextPeriod = addMonthsToPeriod(need.plannedPeriodType, nextPeriod, months);
      if (!nextPeriod) break;
    }

    if (
      nextPeriod &&
      (nextPeriod !== need.nextDuePeriod ||
        need.recurrenceIntervalMonths !== months ||
        (lastGeneratedAt && lastGeneratedAt !== need.lastGeneratedAt))
    ) {
      await trainingNeedUpdate(need.id, {
        nextDuePeriod: nextPeriod,
        recurrenceIntervalMonths: months,
        lastGeneratedAt,
        updatedBy: 'system/cron',
      });
      updated += 1;
    }
  }

  return { generated, updated };
}

async function processTrainings(now) {
  const trainings = await trainingRecordsAll();
  const existing = new Set(
    trainings
      .filter((entry) => entry.parentRecurringId && entry.startDate)
      .map((entry) => `${entry.parentRecurringId}:${entry.startDate}`)
  );
  let generated = 0;
  let updated = 0;

  for (const training of trainings) {
    if (training.parentRecurringId) continue;
    if (training.intervalType !== 'recurring' || !training.recurrenceActive) continue;
    const months = INTERVAL_MONTHS.get(training.intervalValue || '');
    if (!months) {
      console.info('[training/recurrence] skip training interval', { id: training.id, interval: training.intervalValue });
      continue;
    }
    const baseDate = training.nextDueDate || training.startDate;
    if (!baseDate) continue;
    let nextDate = training.nextDueDate || addMonthsToDateString(training.startDate, months);
    if (!nextDate) continue;

    let lastGeneratedAt = training.lastGeneratedAt || null;
    while (true) {
      const due = parseDate(nextDate);
      if (!due || due > now) break;
      const key = `${training.id}:${nextDate}`;
      if (!existing.has(key)) {
        const instance = {
          ...training,
          id: '',
          trainingNumber: '',
          year: extractYear(nextDate),
          startDate: nextDate,
          endDate: training.endDate ? addMonthsToDateString(training.endDate, months) || training.endDate : training.endDate,
          parentRecurringId: training.id,
          isAutoGenerated: true,
          recurrenceActive: false,
          nextDueDate: null,
          lastGeneratedAt: null,
          createdBy: 'system/cron',
          updatedBy: 'system/cron',
        };
        await trainingRecordSave(instance);
        existing.add(key);
        generated += 1;
        lastGeneratedAt = Date.now();
      }
      nextDate = addMonthsToDateString(nextDate, months);
      if (!nextDate) break;
    }

    if (
      nextDate &&
      (nextDate !== training.nextDueDate ||
        training.recurrenceIntervalMonths !== months ||
        (lastGeneratedAt && lastGeneratedAt !== training.lastGeneratedAt))
    ) {
      await trainingRecordUpdate(training.id, {
        nextDueDate: nextDate,
        recurrenceIntervalMonths: months,
        lastGeneratedAt,
        updatedBy: 'system/cron',
      });
      updated += 1;
    }
  }

  return { generated, updated };
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const secret = process.env.CRON_SECRET || '';
  if (secret) {
    const header = String(req.headers?.['x-cron-secret'] || '');
    if (header !== secret) return bad(res, 'forbidden', 403);
  }

  try {
    const now = new Date();
    const needs = await processNeeds(now);
    const trainings = await processTrainings(now);
    const summary = { needs, trainings };
    console.info('[training/recurrence] run', summary);
    return ok(res, { ok: true, summary });
  } catch (err) {
    console.error('[training/recurrence] error', err);
    return bad(res, 'server error', 500);
  }
}
