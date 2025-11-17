// api/admin/stats.js – Kennzahlen für Admin-Dashboard
export const config = { runtime: 'nodejs' };

import {
  setCors,
  ok,
  bad,
  noContent,
  methodNotAllowed,
} from '../_lib/http.js';

const ADMIN_SECRET = process.env.ADMIN_SECRET || '';
const isAdmin = (req) => ADMIN_SECRET && req.headers?.['x-admin-secret'] === ADMIN_SECRET;

function defaultRange() {
  const to = new Date();
  to.setUTCHours(23, 59, 59, 999);
  const from = new Date(to);
  from.setUTCMonth(from.getUTCMonth() - 11);
  from.setUTCDate(1);
  from.setUTCHours(0, 0, 0, 0);
  return { from, to };
}

function parseDateOnly(value, fallback, { endOfDay = false } = {}) {
  if (!value) return new Date(fallback);
  const trimmed = value.trim();
  if (!trimmed) return new Date(fallback);
  let parsed = Number.isFinite(Number(trimmed)) && trimmed.length >= 8
    ? new Date(Number(trimmed))
    : new Date(trimmed);
  if (Number.isNaN(parsed.getTime())) {
    parsed = new Date(fallback);
  }
  if (endOfDay) {
    parsed.setUTCHours(23, 59, 59, 999);
  } else {
    parsed.setUTCHours(0, 0, 0, 0);
  }
  return parsed;
}

function formatDateOnly(date) {
  const iso = date.toISOString();
  return iso.slice(0, 10);
}

function createdAtMs(complaint) {
  const pick = (value) => {
    if (typeof value === 'number' && Number.isFinite(value)) return value;
    if (typeof value === 'string' && value.trim()) {
      const num = Number(value);
      if (Number.isFinite(num)) return num;
      const ts = Date.parse(value);
      if (!Number.isNaN(ts)) return ts;
    }
    return null;
  };
  return (
    pick(complaint?.createdAt) ??
    pick(complaint?.payload?.createdAt) ??
    pick(complaint?.updatedAt) ??
    0
  );
}

function monthKey(ts) {
  if (!Number.isFinite(ts) || ts <= 0) return null;
  const d = new Date(ts);
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
}

function iterateMonths(range) {
  const out = [];
  const cursor = new Date(Date.UTC(range.from.getUTCFullYear(), range.from.getUTCMonth(), 1));
  const end = new Date(Date.UTC(range.to.getUTCFullYear(), range.to.getUTCMonth(), 1));
  while (cursor <= end) {
    out.push(`${cursor.getUTCFullYear()}-${String(cursor.getUTCMonth() + 1).padStart(2, '0')}`);
    cursor.setUTCMonth(cursor.getUTCMonth() + 1);
  }
  return out;
}

const norm = (v) => (v ?? '').toString().trim();
const normLower = (v) => norm(v).toLowerCase();

const COUNTRY_VALUE_KEYS = [
  'countryCode',
  'country',
  'countryName',
  'country_name',
  'customerCountry',
  'name',
  'label',
  'value',
  'title',
  'text',
  'land',
];

function collectCountryCandidates(value) {
  if (value === null || value === undefined) return [];
  if (typeof value === 'string' || typeof value === 'number') {
    const v = norm(value);
    return v ? [v] : [];
  }
  if (Array.isArray(value)) {
    return value.flatMap((entry) => collectCountryCandidates(entry));
  }
  if (typeof value === 'object') {
    return COUNTRY_VALUE_KEYS.flatMap((key) => collectCountryCandidates(value[key]));
  }
  return [];
}

function detectIsoCode(candidate) {
  if (!candidate || typeof candidate !== 'string') return null;
  const tokens = candidate.split(/[^A-Za-z]/).filter(Boolean);
  for (const token of tokens) {
    if (token.length === 2) {
      return token.toUpperCase();
    }
  }
  return null;
}

function pickCountry(complaint) {
  const payload = complaint?.payload || {};
  const sources = [
    complaint?.countryCode,
    complaint?.country,
    complaint?.land,
    complaint?.customer,
    payload.countryCode,
    payload.country,
    payload.customerCountry,
    payload.countryName,
    payload.land,
    payload?.customer,
    payload?.customer?.countryCode,
    payload?.customer?.country,
    payload?.customer?.land,
    complaint?.account,
    complaint?.account?.countryCode,
    complaint?.account?.country,
    complaint?.account?.land,
    complaint?.user,
    complaint?.user?.countryCode,
    complaint?.user?.country,
    complaint?.user?.land,
  ];
  for (const raw of sources) {
    const candidates = collectCountryCandidates(raw);
    for (const candidate of candidates) {
      if (candidate.length === 2) return candidate.toUpperCase();
      const detected = detectIsoCode(candidate);
      if (detected) return detected;
      return candidate;
    }
  }
  return 'Unbekannt';
}

function pickRepMeta(complaint) {
  // Einige Datensätze führen keinen repId – dann lassen wir die Aggregation leer.
  const payload = complaint?.payload || {};
  const rep = complaint?.rep || {};
  const id = norm(
    complaint?.repId ||
    complaint?.rep_id ||
    rep?.id ||
    rep?.repId ||
    payload.repId ||
    payload.rep_id ||
    payload.rep ||
    payload.representative
  );
  if (!id) return null;
  const nameCandidates = [
    complaint?.repName,
    rep?.name,
    `${rep?.firstName || ''} ${rep?.lastName || ''}`,
    `${payload.repFirstName || ''} ${payload.repLastName || ''}`,
  ];
  let repName = null;
  for (const entry of nameCandidates) {
    const v = norm(entry);
    if (v) { repName = v; break; }
  }
  const emailCandidates = [
    complaint?.repEmail,
    rep?.email,
    payload.repEmail,
    payload.representativeEmail,
  ];
  let repEmail = null;
  for (const entry of emailCandidates) {
    const v = normLower(entry);
    if (v) { repEmail = v; break; }
  }
  return { repId: id, repName: repName || undefined, repEmail: repEmail || undefined };
}

function countBy(list, keyFn) {
  const map = new Map();
  for (const entry of list) {
    const key = keyFn(entry);
    if (key === null || key === undefined || key === '') continue;
    map.set(key, (map.get(key) || 0) + 1);
  }
  return map;
}

function buildStats(list, range, repInfo = new Map()) {
  const total = list.length;
  const statusCounts = countBy(list, (c) => {
    const s = Number(c?.status || 0);
    if (!Number.isFinite(s) || s < 1 || s > 5) return null;
    return s;
  });
  const decisionCounts = countBy(list, (c) => {
    const raw = (c?.decision || '').toString().trim();
    return raw || 'pending';
  });
  const pending = decisionCounts.get('pending') || 0;
  const open = Math.max(pending, 0);

  const monthsRaw = countBy(list, (c) => monthKey(createdAtMs(c)));
  const monthsSeries = iterateMonths(range).map((month) => ({
    month,
    count: monthsRaw.get(month) || 0,
  }));

  const byCountry = Array.from(countBy(list, (c) => pickCountry(c)).entries())
    .map(([country, count]) => ({ country, count }))
    .sort((a, b) => b.count - a.count || a.country.localeCompare(b.country));

  const repMap = new Map();
  for (const c of list) {
    const meta = pickRepMeta(c);
    if (!meta) continue;
    const key = meta.repId;
    const current = repMap.get(key) || { ...meta, count: 0 };
    current.count += 1;
    if (!current.repName && meta.repName) current.repName = meta.repName;
    if (!current.repEmail && meta.repEmail) current.repEmail = meta.repEmail;
    const enriched = repInfo.get(key);
    if (enriched) {
      if (enriched.name) current.repName = enriched.name;
      if (enriched.email) current.repEmail = enriched.email;
    }
    repMap.set(key, current);
  }
  const byRep = Array.from(repMap.values()).sort((a, b) => b.count - a.count || a.repId.localeCompare(b.repId));

  const byStatus = Array.from(statusCounts.entries())
    .map(([status, count]) => ({ status: Number(status), count }))
    .sort((a, b) => a.status - b.status);

  const byDecision = Array.from(decisionCounts.entries())
    .map(([decision, count]) => ({ decision, count }))
    .sort((a, b) => a.decision.localeCompare(b.decision));

  return {
    from: formatDateOnly(range.from),
    to: formatDateOnly(range.to),
    total,
    open,
    byStatus,
    byDecision,
    byMonth: monthsSeries,
    byCountry,
    byRep,
  };
}

function formatRepStoreEntry(rep) {
  if (!rep || typeof rep !== 'object') return null;
  const first = norm(rep.firstName);
  const last = norm(rep.lastName);
  const full = `${first} ${last}`.trim();
  const name = full || norm(rep.name) || undefined;
  const email = normLower(rep.email) || undefined;
  if (!name && !email) return null;
  return { name, email };
}

async function loadRepInfoMap(repIds) {
  if (!repIds?.length) return new Map();
  try {
    const store = await import('../_lib/repsStore.js');
    const { loadRepById } = store || {};
    if (typeof loadRepById !== 'function') return new Map();
    const map = new Map();
    await Promise.all(repIds.map(async (id) => {
      try {
        const rep = await loadRepById(id);
        const normalized = formatRepStoreEntry(rep);
        if (normalized) map.set(id, normalized);
      } catch (err) {
        console.warn(`[admin/stats] failed to load rep ${id}`, err?.message || err);
      }
    }));
    return map;
  } catch (err) {
    console.warn('[admin/stats] rep store unavailable', err?.message || err);
    return new Map();
  }
}

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);
  if (req.method !== 'GET') return methodNotAllowed(res);
  if (!isAdmin(req)) return bad(res, 'admin unauthorized', 401);

  try {
    const { complaintsAll } = await import('../_lib/store.js');

    const q = req.query || {};
    const defaults = defaultRange();
    const fromInput = norm(q.from || '');
    const toInput = norm(q.to || '');
    let from = parseDateOnly(fromInput, defaults.from);
    let to = parseDateOnly(toInput, defaults.to, { endOfDay: true });
    if (from > to) {
      const tmp = from;
      from = to;
      to = tmp;
    }
    const range = { from, to };

    const allComplaints = await complaintsAll();
    const filtered = (allComplaints || []).filter((c) => {
      const ts = createdAtMs(c);
      return ts >= range.from.getTime() && ts <= range.to.getTime();
    });

    const repIds = Array.from(new Set(filtered.map((c) => pickRepMeta(c)?.repId).filter(Boolean)));
    const repInfo = await loadRepInfoMap(repIds);

    const payload = buildStats(filtered, range, repInfo);
    return ok(res, payload);
  } catch (err) {
    console.error('[admin/stats] failed', err);
    return bad(res, 'internal error', 500);
  }
}
