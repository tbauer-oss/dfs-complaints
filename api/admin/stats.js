// api/admin/stats.js – Kennzahlen für Admin-Dashboard
export const config = { runtime: 'nodejs' };

import {
  setCors,
  ok,
  bad,
  noContent,
  methodNotAllowed,
} from '../_lib/http.js';
import { normalizeCountryName, resolveCountryCode } from '../_lib/countryNames.js';

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

function parseTimestamp(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim()) {
    const num = Number(value);
    if (Number.isFinite(num)) return num;
    const ts = Date.parse(value);
    if (!Number.isNaN(ts)) return ts;
  }
  return null;
}

function createdAtMs(complaint) {
  return (
    parseTimestamp(complaint?.createdAt) ??
    parseTimestamp(complaint?.payload?.createdAt) ??
    parseTimestamp(complaint?.updatedAt) ??
    0
  );
}

function updatedAtMs(complaint) {
  return (
    parseTimestamp(complaint?.updatedAt) ??
    parseTimestamp(complaint?.statusUpdatedAt) ??
    createdAtMs(complaint)
  );
}

function closedAtMs(complaint) {
  return (
    parseTimestamp(complaint?.closedAt) ??
    parseTimestamp(complaint?.closed_at) ??
    parseTimestamp(complaint?.payload?.closedAt) ??
    parseTimestamp(complaint?.payload?.closed_at) ??
    null
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

const STATUS_LABEL = {
  1: 'Eingegangen',
  2: 'In Bearbeitung',
  3: 'Rückfrage erforderlich',
  4: 'In Nacharbeit',
  5: 'Abgeschlossen',
};

const DECISION_LABEL = {
  accepted: 'Angenommen',
  rejected: 'Abgelehnt',
  pending: 'Entscheidung offen',
};

const CUSTOMER_COMPANY_KEYS = [
  'company',
  'customerCompany',
  'customer_company',
  'customer',
  'customerName',
  'customer_name',
  'accountCompany',
  'account_company',
  'organization',
  'organisation',
  'org',
  'clinic',
  'practice',
  'praxis',
  'firm',
  'firma',
  'betrieb',
];

const CUSTOMER_CONTACT_KEYS = [
  'contact',
  'contactName',
  'contact_name',
  'contactPerson',
  'contact_person',
  'customerContact',
  'customer_contact',
  'user',
  'userName',
  'user_name',
];

const CUSTOMER_EMAIL_KEYS = [
  'email',
  'customerEmail',
  'customer_email',
  'userEmail',
  'user_email',
  'contactEmail',
  'contact_email',
  'accountEmail',
  'account_email',
];

const CUSTOMER_NUMBER_KEYS = [
  'customerNumber',
  'customer_number',
  'customer_no',
  'customerNo',
  'customerId',
  'customer_id',
  'kundennummer',
  'kundenNr',
];

const ARTICLE_KEYS = [
  'article',
  'article_no',
  'articleNo',
  'articleNumber',
  'article_name',
  'product',
  'productName',
  'artikel',
  'artikelnummer',
];

const SEGMENT_KEYS = [
  'segment',
  'segment_code',
  'customer_segment',
  'businessUnit',
  'unit',
  'bereich',
];

const MS_PER_DAY = 24 * 60 * 60 * 1000;
const LONG_RUNNER_DAYS = Math.max(
  1,
  Number(process.env.ADMIN_LONG_RUNNER_DAYS || 30),
);

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
const COUNTRY_VALUE_KEY_SET = new Set(COUNTRY_VALUE_KEYS);
const MAX_COUNTRY_DEPTH = 5;

function collectCountryCandidates(value, depth = 0, visited = new Set()) {
  if (value === null || value === undefined) return [];
  if (typeof value === 'string' || typeof value === 'number') {
    const v = norm(value);
    return v ? [v] : [];
  }
  if (Array.isArray(value)) {
    return value.flatMap((entry) => collectCountryCandidates(entry, depth + 1, visited));
  }
  if (typeof value === 'object') {
    if (visited.has(value) || depth >= MAX_COUNTRY_DEPTH) return [];
    visited.add(value);
    const prioritized = COUNTRY_VALUE_KEYS
      .filter((key) => Object.prototype.hasOwnProperty.call(value, key))
      .map((key) => value[key]);
    const others = [];
    if (depth + 1 < MAX_COUNTRY_DEPTH) {
      for (const [key, entry] of Object.entries(value)) {
        if (COUNTRY_VALUE_KEY_SET.has(key)) continue;
        others.push(entry);
      }
    }
    const nested = [...prioritized, ...others]
      .flatMap((entry) => collectCountryCandidates(entry, depth + 1, visited));
    visited.delete(value);
    return nested;
  }
  return [];
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
  const seen = new Set();
  let fallback = null;
  for (const raw of sources) {
    const candidates = collectCountryCandidates(raw);
    for (const candidate of candidates) {
      const normalized = norm(candidate);
      if (!normalized) continue;
      const key = normalized.toLowerCase();
      if (seen.has(key)) continue;
      seen.add(key);
      const resolved = resolveCountryCode(normalized);
      if (resolved) return resolved;
      const clean = normalizeCountryName(normalized);
      if (!fallback && clean && !/\d/.test(clean)) fallback = normalized;
    }
  }
  return fallback || 'Unbekannt';
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

function pickValue(source, keys) {
  if (!source || typeof source !== 'object') return null;
  for (const key of keys) {
    if (!Object.prototype.hasOwnProperty.call(source, key)) continue;
    const value = norm(source[key]);
    if (value) return value;
  }
  return null;
}

function pickCustomerMeta(complaint) {
  const payload = complaint?.payload || {};
  const account = complaint?.account || {};
  const customer = complaint?.customer || {};
  const user = complaint?.user || {};

  const emailSources = [
    complaint,
    payload,
    account,
    customer,
    user,
    payload?.customer,
    payload?.account,
  ];
  let email = null;
  for (const source of emailSources) {
    if (!source || typeof source !== 'object') continue;
    for (const key of CUSTOMER_EMAIL_KEYS) {
      const value = normLower(source[key]);
      if (value) { email = value; break; }
    }
    if (email) break;
  }

  const labelSources = [complaint, payload, account, customer, user, payload?.customer, payload?.account];
  let company = null;
  let contact = null;
  let customerNumber = null;
  for (const source of labelSources) {
    if (!company) company = pickValue(source, CUSTOMER_COMPANY_KEYS);
    if (!contact) contact = pickValue(source, CUSTOMER_CONTACT_KEYS);
    if (!customerNumber) customerNumber = pickValue(source, CUSTOMER_NUMBER_KEYS);
  }

  const label = company || contact || email || `Ticket ${complaint?.ticket || ''}`.trim() || 'Unbekannter Kunde';
  const key = email || (company ? company.toLowerCase() : (contact ? contact.toLowerCase() : label.toLowerCase()));
  return {
    key,
    label,
    company: company || undefined,
    contact: contact || undefined,
    email: email || undefined,
    customerNumber: customerNumber || undefined,
  };
}

function pickArticle(complaint) {
  const payload = complaint?.payload || {};
  const sources = [complaint, payload, payload?.product];
  for (const source of sources) {
    const value = pickValue(source, ARTICLE_KEYS);
    if (value) return value;
  }
  return '';
}

function pickSegment(complaint) {
  const payload = complaint?.payload || {};
  return pickValue(payload, SEGMENT_KEYS) || pickValue(complaint, SEGMENT_KEYS) || '';
}

function decisionLabel(decision) {
  const key = (decision || 'pending').toString().trim() || 'pending';
  return DECISION_LABEL[key] || DECISION_LABEL.pending;
}

function statusLabel(status) {
  return STATUS_LABEL[Number(status) || 0] || STATUS_LABEL[1];
}

function buildActiveUserDirectory(list) {
  const map = new Map();
  if (!Array.isArray(list)) return map;
  for (const user of list) {
    const email = normLower(user?.email);
    if (!email) continue;
    const company = norm(user?.company);
    const contact = norm(user?.contact);
    const label = company || contact || norm(user?.name) || norm(user?.customer) || norm(user?.customerName);
    const customerNumber = norm(
      user?.customerNumber ||
      user?.customer_number ||
      user?.customer_no ||
      user?.customerNo ||
      user?.kundennummer
    );
    map.set(email, {
      label: label || user?.email || email,
      company: company || contact || null,
      customerNumber: customerNumber || null,
    });
  }
  return map;
}

function mergeCustomerMetaWithDirectory(meta, directory = new Map()) {
  if (!meta) return meta;
  const email = normLower(meta.email);
  if (!email) return meta;
  const enriched = directory.get(email);
  if (!enriched) return meta;
  return {
    ...meta,
    label: enriched.label || meta.label,
    company: meta.company || enriched.company || meta.company,
    customerNumber: meta.customerNumber || enriched.customerNumber || meta.customerNumber,
  };
}

function buildCustomerBuckets(list, activeDirectory = new Map()) {
  const map = new Map();
  for (const c of list) {
    const meta = mergeCustomerMetaWithDirectory(pickCustomerMeta(c), activeDirectory);
    if (!meta?.key) continue;
    const current = map.get(meta.key) || { ...meta, count: 0 };
    current.count += 1;
    if (!current.company && meta.company) current.company = meta.company;
    if (!current.contact && meta.contact) current.contact = meta.contact;
    if (!current.email && meta.email) current.email = meta.email;
    if (!current.customerNumber && meta.customerNumber) current.customerNumber = meta.customerNumber;
    map.set(meta.key, current);
  }
  return Array.from(map.values()).sort((a, b) => b.count - a.count || a.label.localeCompare(b.label));
}

function resolvedAtMs(complaint) {
  const explicit = closedAtMs(complaint);
  if (explicit) return explicit;
  const status = Number(complaint?.status || 0);
  if (status === 5) {
    return (
      parseTimestamp(complaint?.statusUpdatedAt) ??
      parseTimestamp(complaint?.updatedAt) ??
      null
    );
  }
  const decision = (complaint?.decision || '').toString().trim();
  if (decision === 'rejected' || decision === 'accepted') {
    return parseTimestamp(complaint?.decisionAt) ?? parseTimestamp(complaint?.statusUpdatedAt) ?? null;
  }
  return null;
}

function percentile(sorted, p) {
  if (!sorted.length) return null;
  const target = (sorted.length - 1) * p;
  const lower = Math.floor(target);
  const upper = Math.ceil(target);
  if (lower === upper) return sorted[lower];
  const weight = target - lower;
  return sorted[lower] + (sorted[upper] - sorted[lower]) * weight;
}

function buildTimeToCloseStats(list) {
  const durations = [];
  let longRunnerOpen = 0;
  const now = Date.now();
  for (const c of list) {
    const created = createdAtMs(c);
    if (!created) continue;
    const resolved = resolvedAtMs(c);
    if (resolved && resolved > created) {
      durations.push(Math.max(0, resolved - created));
    }
    const status = Number(c?.status || 0);
    if (status !== 5) {
      const age = now - created;
      if (age >= LONG_RUNNER_DAYS * MS_PER_DAY) longRunnerOpen += 1;
    }
  }
  durations.sort((a, b) => a - b);
  const total = durations.length;
  const avg = total ? durations.reduce((sum, value) => sum + value, 0) / total : null;
  const median = percentile(durations, 0.5);
  const p90 = percentile(durations, 0.9);
  const toDays = (ms) => (ms == null ? null : ms / MS_PER_DAY);
  return {
    sampleSize: total,
    averageDays: toDays(avg),
    medianDays: toDays(median),
    p90Days: toDays(p90),
    longRunnerOpen,
    thresholdDays: LONG_RUNNER_DAYS,
  };
}

function buildTemporalLoad(list) {
  const weekdays = Array.from({ length: 7 }, (_, idx) => ({ weekday: idx, count: 0 }));
  const hours = Array.from({ length: 24 }, (_, idx) => ({ hour: idx, count: 0 }));
  for (const c of list) {
    const ts = createdAtMs(c);
    if (!ts) continue;
    const date = new Date(ts);
    const weekday = date.getUTCDay();
    const hour = date.getUTCHours();
    weekdays[weekday].count += 1;
    hours[hour].count += 1;
  }
  return { weekdays, hours };
}

function buildAuditEntries(list, repInfo = new Map(), activeDirectory = new Map()) {
  return list.map((c) => {
    const meta = mergeCustomerMetaWithDirectory(pickCustomerMeta(c), activeDirectory);
    const rep = pickRepMeta(c);
    const enriched = rep?.repId ? repInfo.get(rep.repId) : null;
    const repName = enriched?.name || rep?.repName || null;
    const repEmail = enriched?.email || rep?.repEmail || null;
    return {
      ticket: (c?.ticket || '').toString(),
      createdAt: createdAtMs(c),
      updatedAt: updatedAtMs(c),
      status: Number(c?.status || 0) || 0,
      statusLabel: statusLabel(c?.status),
      decision: (c?.decision || 'pending') || 'pending',
      decisionLabel: decisionLabel(c?.decision),
      country: pickCountry(c),
      customer: meta?.label || meta?.email || '',
      customerEmail: meta?.email || '',
      customerNumber: meta?.customerNumber || '',
      article: pickArticle(c),
      segment: pickSegment(c),
      repName: repName || '',
      repEmail: repEmail || '',
    };
  });
}

function buildStats(list, range, repInfo = new Map(), activeDirectory = new Map()) {
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

  const byCustomer = buildCustomerBuckets(list, activeDirectory);
  const timeToClose = buildTimeToCloseStats(list);
  const temporalLoad = buildTemporalLoad(list);
  const audit = buildAuditEntries(list, repInfo, activeDirectory);

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
    byCustomer,
    timeToClose,
    loadByWeekday: temporalLoad.weekdays,
    loadByHour: temporalLoad.hours,
    audit,
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
    const { complaintsAll, usersList } = await import('../_lib/store.js');

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

    const [allComplaints, activeUsers] = await Promise.all([
      complaintsAll(),
      (async () => {
        try {
          return await usersList();
        } catch (err) {
          console.warn('[admin/stats] users list unavailable', err?.message || err);
          return [];
        }
      })(),
    ]);
    const activeDirectory = buildActiveUserDirectory(activeUsers);

    const filtered = (allComplaints || []).filter((c) => {
      const ts = createdAtMs(c);
      return ts >= range.from.getTime() && ts <= range.to.getTime();
    });

    const repIds = Array.from(new Set(filtered.map((c) => pickRepMeta(c)?.repId).filter(Boolean)));
    const repInfo = await loadRepInfoMap(repIds);

    const payload = buildStats(filtered, range, repInfo, activeDirectory);
    return ok(res, payload);
  } catch (err) {
    console.error('[admin/stats] failed', err);
    return bad(res, 'internal error', 500);
  }
}
