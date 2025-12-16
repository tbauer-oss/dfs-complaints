import { randomUUID } from 'crypto';
import { redis } from '../_lib/redis.js';
import { portalUserFromRequest, canWrite } from '../_lib/portalAuth.js';
import { bad } from '../_lib/http.js';

const PROD_ORIGIN = 'https://dfs-complaints-web.vercel.app';
const LOCAL_PATTERN = /^http:\/\/localhost(?::\d+)?$/i;

export function applyInternalCors(req, res) {
  const origin = req?.headers?.origin || '';
  const allowOrigin = origin === PROD_ORIGIN || LOCAL_PATTERN.test(origin) ? origin : PROD_ORIGIN;
  res.setHeader('Access-Control-Allow-Origin', allowOrigin);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('Access-Control-Max-Age', '86400');
  if (!res.getHeader('Content-Type')) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
  }
  if (req.method === 'OPTIONS') {
    res.statusCode = 204;
    res.end();
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

function normalizeAuditMeta(payload, { actor }) {
  const now = Date.now();
  const id = payload.id || randomUUID();
  return {
    id,
    auditNumber: payload.auditNumber || payload.auditNr || id,
    title: payload.title || '',
    date: payload.date || payload.plannedDate || null,
    status: payload.status || 'planned',
    leadAuditorId: payload.leadAuditorId || null,
    coAuditorId: payload.coAuditorId || null,
    createdAt: payload.createdAt || now,
    createdBy: payload.createdBy || actor?.email || 'unknown',
  };
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
  const normalized = normalizeAuditMeta(meta, { actor: meta.actor });
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
  const record = {
    id,
    name: data.name || '',
    email: data.email || '',
    active: data.active !== false,
    createdAt: data.createdAt || now,
  };
  await redis.sadd(KEY_AUDITOR_INDEX, id);
  await redis.set(KEY_AUDITOR(id), record);
  return record;
}

export async function deleteAuditor(id, { method }) {
  assertWriteAllowed(method, 'deleteAuditor', KEY_AUDITOR(id));
  await redis.srem(KEY_AUDITOR_INDEX, id);
  await redis.del(KEY_AUDITOR(id));
}

export const IA_KEYS = {
  KEY_AUDIT_INDEX,
  KEY_AUDIT,
  KEY_AUDIT_PLAN,
  KEY_AUDITOR_INDEX,
  KEY_AUDITOR,
};
