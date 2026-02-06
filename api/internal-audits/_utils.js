import { randomUUID } from 'crypto';
import { redis } from '../_lib/redis.js';
import { portalUserFromRequest, canWrite } from '../_lib/portalAuth.js';
import { bad, withCors } from '../_lib/http.js';
import {
  processIncomingFiles,
  normalizeProvidedUploads,
  deleteUploadsFromBlob,
} from '../_lib/uploads.js';

export function applyInternalCors(req, res) {
  withCors(req, res);
  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return true;
  }
  return false;
}

const WRITE_METHODS = new Set(['GET', 'HEAD', 'OPTIONS']);

function assertWriteAllowed(method, action, key) {
  if (WRITE_METHODS.has((method || '').toUpperCase())) {
    const err = new Error('redis write blocked for read-only request');
    err.details = { action, key, method };
    console.error('[internal-audits][write-guard]', { action, key, method });
    throw err;
  }
}

const KEY_AUDIT_INDEX = 'dfs:ia:index';
const KEY_AUDIT = (id) => `dfs:ia:${id}`;
const KEY_AUDIT_PLAN = (id) => `dfs:ia:${id}:plan`;
const KEY_AUDITOR_INDEX = 'dfs:ia:auditors:index';
const KEY_AUDITOR = (id) => `dfs:ia:auditor:${id}`;
const KEY_AUDIT_COUNTER = (year) => `dfs:ia:counter:${year}`;
const KEY_AUDIT_EVIDENCE = (id) => `dfs:ia:${id}:evidence`;
const KEY_PROGRAM_ARCHIVED = 'dfs:ia:program:archived';

function twoDigit(value) {
  return String(value).padStart(2, '0');
}

async function nextAuditNumber({ now, method }) {
  const date = now ? new Date(now) : new Date();
  const year = twoDigit(date.getFullYear() % 100);
  const counterKey = KEY_AUDIT_COUNTER(year);
  assertWriteAllowed(method, 'nextAuditNumber', counterKey);
  const sequence = await redis.incr(counterKey);
  return `IA-${year}-${twoDigit(sequence)}`;
}

function displayPeriod(start, end) {
  const fmt = (value) => {
    const d = new Date(value);
    if (Number.isNaN(d.getTime())) return null;
    return `${twoDigit(d.getDate())}.${twoDigit(d.getMonth() + 1)}.${d.getFullYear()}`;
  };
  const startText = start ? fmt(start) : null;
  const endText = end ? fmt(end) : null;
  if (startText && endText) return `${startText} – ${endText}`;
  return startText || endText || null;
}

function normalizeAuditMeta(payload, { actor, auditNumber }) {
  const now = Date.now();
  const id = payload.id || randomUUID();
  const plannedDate = payload.date || payload.plannedDate || null;
  const plannedStart = payload.plannedStart || plannedDate;
  const plannedEnd = payload.plannedEnd || plannedDate;
  const year = payload.year || (plannedStart ? new Date(plannedStart).getFullYear() : new Date(now).getFullYear());
  const cluster = payload.cluster || payload.quarter || deriveQuarter(plannedStart || plannedEnd);
  const auditeesOrgUnits = Array.isArray(payload.auditeesOrgUnits)
    ? payload.auditeesOrgUnits.filter(Boolean)
    : payload.orgUnit
    ? [payload.orgUnit]
    : [];

  return {
    id,
    auditNumber: auditNumber || payload.auditNumber || payload.auditNr || id,
    title: payload.title || '',
    year,
    cluster: cluster || 'Q1',
    site: payload.site || null,
    plannedStart,
    plannedEnd,
    status: payload.status || 'planned',
    scopeText: payload.scopeText || payload.scope || null,
    auditeesOrgUnits,
    leadAuditorId: payload.leadAuditorId || null,
    coAuditorId: payload.coAuditorId || null,
    createdAt: payload.createdAt || now,
    createdBy: payload.createdBy || actor?.email || 'unknown',
  };
}

function deriveQuarter(dateLike) {
  if (!dateLike) return null;
  const d = new Date(dateLike);
  const month = d.getMonth();
  if (Number.isNaN(month)) return null;
  if (month <= 2) return 'Q1';
  if (month <= 5) return 'Q2';
  if (month <= 8) return 'Q3';
  return 'Q4';
}

export async function ensureActor(req, res, { write = false } = {}) {
  const actor = await portalUserFromRequest(req);
  if (!actor) {
    bad(res, 'unauthorized', 401);
    return null;
  }
  if (write && !canWrite(actor.role)) {
    bad(res, 'forbidden', 403);
    return null;
  }
  return actor;
}

export async function listAudits() {
  const ids = (await redis.smembers(KEY_AUDIT_INDEX)) || [];
  if (!Array.isArray(ids)) return [];
  const results = [];
  for (const id of ids) {
    const meta = await redis.get(KEY_AUDIT(id));
    if (meta) results.push(meta);
  }
  return results;
}

export async function createAudit(meta, { method }) {
  assertWriteAllowed(method, 'createAudit', KEY_AUDIT(meta.id || 'new'));
  const now = Date.now();
  const auditNumber = await nextAuditNumber({ now, method });
  const normalized = normalizeAuditMeta(meta, { actor: meta.actor, auditNumber });
  await redis.sadd(KEY_AUDIT_INDEX, normalized.id);
  await redis.set(KEY_AUDIT(normalized.id), normalized);
  return normalized;
}

export async function getAudit(id) {
  return (await redis.get(KEY_AUDIT(id))) || null;
}

export async function updateAudit(id, patch, { method }) {
  const current = await getAudit(id);
  if (!current) return null;
  assertWriteAllowed(method, 'updateAudit', KEY_AUDIT(id));
  const merged = { ...current, ...patch, id: current.id };
  await redis.set(KEY_AUDIT(id), merged);
  return merged;
}

export async function deleteAudit(id, { method }) {
  assertWriteAllowed(method, 'deleteAudit', KEY_AUDIT(id));
  await redis.srem(KEY_AUDIT_INDEX, id);
  await redis.del(KEY_AUDIT(id));
  await redis.del(KEY_AUDIT_PLAN(id));
}

export async function getAuditPlan(id) {
  const plan = await redis.get(KEY_AUDIT_PLAN(id));
  if (!plan) return null;
  return plan;
}

export async function saveAuditPlan(id, planEntries, { method }) {
  assertWriteAllowed(method, 'saveAuditPlan', KEY_AUDIT_PLAN(id));
  const audit = await getAudit(id);
  if (!audit) return null;
  const normalized = Array.isArray(planEntries) ? planEntries : [];
  await redis.set(KEY_AUDIT_PLAN(id), { auditId: id, planEntries: normalized });
  return normalized;
}

export async function listAuditEvidence(id) {
  const existing = (await redis.get(KEY_AUDIT_EVIDENCE(id))) || {};
  const uploads = normalizeProvidedUploads(existing.uploads || existing.evidence || []);
  return uploads;
}

export async function addAuditEvidence(id, files, { method }) {
  assertWriteAllowed(method, 'addAuditEvidence', KEY_AUDIT_EVIDENCE(id));
  const audit = await getAudit(id);
  if (!audit) return null;
  const current = await listAuditEvidence(id);
  const { uploads } = await processIncomingFiles(files, {
    ticket: async () => audit.auditNumber || id,
    allowPreviewFallback: false,
    allowDataUrlFallback: true,
  });
  const enriched = uploads.map((entry) => ({
    ...entry,
    id: entry.id || randomUUID(),
    uploadedAt: entry.uploadedAt || Date.now(),
  }));
  const merged = [...current.filter((c) => !enriched.find((e) => e.name === c.name)), ...enriched];
  await redis.set(KEY_AUDIT_EVIDENCE(id), { auditId: id, uploads: merged });
  return merged;
}

export async function deleteAuditEvidence(id, evidenceId, { method }) {
  assertWriteAllowed(method, 'deleteAuditEvidence', KEY_AUDIT_EVIDENCE(id));
  const current = await listAuditEvidence(id);
  const removed = current.find((e) => e.id === evidenceId);
  if (!removed) return current;
  const remaining = current.filter((e) => e.id !== evidenceId);
  await redis.set(KEY_AUDIT_EVIDENCE(id), { auditId: id, uploads: remaining });
  await deleteUploadsFromBlob([removed]);
  return remaining;
}

export async function listAuditors() {
  const ids = (await redis.smembers(KEY_AUDITOR_INDEX)) || [];
  if (!Array.isArray(ids)) return [];
  const results = [];
  for (const id of ids) {
    const auditor = await redis.get(KEY_AUDITOR(id));
    if (auditor) results.push(auditor);
  }
  return results;
}

export async function createAuditor(data, { method }) {
  assertWriteAllowed(method, 'createAuditor', KEY_AUDITOR(data.id || 'new'));
  const now = Date.now();
  const id = data.id || randomUUID();
  const record = { id, createdAt: data.createdAt || now, active: data.active !== false, ...data };
  record.id = id;
  record.createdAt = record.createdAt || now;
  record.active = record.active !== false;
  await redis.sadd(KEY_AUDITOR_INDEX, id);
  await redis.set(KEY_AUDITOR(id), record);
  return record;
}

export async function deleteAuditor(id, { method }) {
  assertWriteAllowed(method, 'deleteAuditor', KEY_AUDITOR(id));
  await redis.srem(KEY_AUDITOR_INDEX, id);
  await redis.del(KEY_AUDITOR(id));
}

async function archivedYears() {
  const list = (await redis.smembers(KEY_PROGRAM_ARCHIVED)) || [];
  if (!Array.isArray(list)) return new Set();
  return new Set(list.map((y) => String(y)));
}

export async function listAuditPrograms() {
  const audits = await listAudits();
  const archived = await archivedYears();
  const nowYear = new Date().getFullYear();
  const auditors = await listAuditors();
  const auditorById = new Map(auditors.map((a) => [a.id, a]));

  const programs = new Map();
  for (const audit of audits) {
    const year = audit.year || nowYear;
    const existing = programs.get(year) || {
      id: `program-${year}`,
      year,
      title: `Auditprogramm ${year}`,
      status: archived.has(String(year)) || year < nowYear ? 'archived' : 'active',
      clusters: new Set(),
      entries: [],
    };

    if (audit.cluster) existing.clusters.add(audit.cluster);

    const lead = audit.leadAuditorId ? auditorById.get(audit.leadAuditorId) : null;
    const co = audit.coAuditorId ? auditorById.get(audit.coAuditorId) : null;

    existing.entries.push({
      auditId: audit.id,
      auditNumber: audit.auditNumber,
      cluster: audit.cluster || null,
      title: audit.title || '',
      scope: audit.scopeText || null,
      processes: Array.isArray(audit.auditeesOrgUnits) ? audit.auditeesOrgUnits : [],
      references: Array.isArray(audit.references) ? audit.references : [],
      responsible: Array.isArray(audit.processOwners) ? audit.processOwners : [],
      participants: Array.isArray(audit.participants) ? audit.participants : [],
      site: audit.site || null,
      status: audit.status || 'planned',
      plannedPeriod: displayPeriod(audit.plannedStart, audit.plannedEnd),
      leadAuditor: lead?.name || null,
      coAuditor: co?.name || null,
    });

    programs.set(year, existing);
  }

  return Array.from(programs.values()).map((p) => ({
    ...p,
    totalAudits: p.entries.length,
    clusters: Array.from(p.clusters.size ? p.clusters : ['Q1', 'Q2', 'Q3', 'Q4']),
  }));
}

export async function setProgramArchived(year, archivedFlag, { method }) {
  const key = KEY_PROGRAM_ARCHIVED;
  assertWriteAllowed(method, 'setProgramArchived', key);
  if (!year) return null;
  const yearStr = String(year);
  if (archivedFlag) {
    await redis.sadd(key, yearStr);
  } else {
    await redis.srem(key, yearStr);
  }
  const programs = await listAuditPrograms();
  return programs.find((p) => String(p.year) === yearStr) || null;
}

export const IA_KEYS = {
  KEY_AUDIT_INDEX,
  KEY_AUDIT,
  KEY_AUDIT_PLAN,
  KEY_AUDITOR_INDEX,
  KEY_AUDITOR,
  KEY_AUDIT_COUNTER,
  KEY_PROGRAM_ARCHIVED,
};
