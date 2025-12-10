// api/admin/complaints_export.js
export const config = { runtime: 'nodejs' };

import JSZip from 'jszip';
import { setCors, noContent, bad, methodNotAllowed } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import { normalizeRole, PORTAL_ROLES } from '../_lib/portalAuth.js';
import { hasDepartmentOverlap, normalizeDepartments } from '../_lib/departments.js';
import { complaintByTicket, Status } from '../_lib/store.js';

const normEmail = (v = '') => v.toString().trim().toLowerCase();
const cleanName = (v = '', fallback = 'file') => {
  const name = (v || fallback).toString().trim();
  const safe = name.replace(/[^a-z0-9._-]+/gi, '-').replace(/-+/g, '-').replace(/^-+|-+$/g, '');
  return safe || fallback;
};

function normalizeHistory(list) {
  if (!Array.isArray(list)) return [];
  const normalized = list.map((entry = {}) => {
    const at = Number(entry?.at);
    const actor = (entry?.actor || 'system').toString().trim() || 'system';
    const type = (entry?.type || 'info').toString().trim() || 'info';
    const message = (entry?.message || '').toString();
    const data = (entry?.data && typeof entry.data === 'object') ? entry.data : undefined;
    return {
      at: Number.isFinite(at) && at > 0 ? at : Date.now(),
      actor,
      type,
      message,
      ...(data ? { data } : {}),
    };
  }).filter(Boolean);
  normalized.sort((a, b) => (a.at || 0) - (b.at || 0));
  return normalized;
}

function historyText(entries = []) {
  return entries.map((entry) => {
    const ts = new Date(entry.at || Date.now()).toISOString();
    const parts = [ts, entry.actor || 'system', entry.type || 'info'];
    if (entry.message) parts.push(entry.message);
    if (entry.data && Object.keys(entry.data).length > 0) {
      parts.push(JSON.stringify(entry.data));
    }
    return parts.join(' | ');
  }).join('\n');
}

function bufferFromDataUrl(url) {
  const match = /^data:([^;]+);base64,(.+)$/i.exec((url || '').toString());
  if (!match) return null;
  try {
    return Buffer.from(match[2], 'base64');
  } catch (err) {
    console.warn('[complaints_export] failed to decode data URL', err?.message || err);
    return null;
  }
}

async function downloadBuffer(url) {
  if (!url) return null;
  const str = url.toString();
  if (str.startsWith('data:')) return bufferFromDataUrl(str);

  try {
    const res = await fetch(str);
    if (!res.ok) throw new Error(`HTTP ${res.status} ${res.statusText}`);
    const ab = await res.arrayBuffer();
    return Buffer.from(ab);
  } catch (err) {
    console.warn('[complaints_export] download failed', str, err?.message || err);
    return null;
  }
}

async function addDownloads(folder, entries = [], label = 'file', errors = []) {
  if (!folder) return;
  const list = Array.isArray(entries) ? entries : [];
  for (let i = 0; i < list.length; i += 1) {
    const entry = list[i] || {};
    const filename = cleanName(entry.name || `${label}_${i + 1}`);
    const url = entry.downloadUrl || entry.url || null;
    const buffer = await downloadBuffer(url);
    if (buffer) {
      folder.file(filename, buffer);
    } else {
      errors.push(`${label} ${i + 1}: konnte ${url || 'ohne URL'} nicht laden`);
    }
  }
}

function collectReportLinks(complaint = {}) {
  const all = new Set();
  const add = (v) => {
    if (!v) return;
    const str = v.toString().trim();
    if (str) all.add(str);
  };

  add(complaint.reportLink);
  [complaint.reportLinks, complaint.externalReportLinks, complaint.internalReportLinks]
    .filter((m) => m && typeof m === 'object')
    .forEach((map) => {
      Object.values(map).forEach(add);
    });

  return Array.from(all);
}

function actorDepartments(actor) {
  return normalizeDepartments(actor?.assignedDepartments || []);
}

function withinScope(actor, complaint) {
  const deps = actorDepartments(actor);
  if (deps.length === 0) return true;
  return hasDepartmentOverlap(deps, complaint?.internalDepartments);
}

function canExport(complaint) {
  const status = Number(complaint?.status || 0);
  const decision = (complaint?.decision || '').toString().trim().toLowerCase();
  return status === Status.CLOSED || decision === 'rejected';
}

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);
  if (req.method !== 'GET') return methodNotAllowed(res);

  const actor = await requirePortalAccess(req, res, { write: false, tile: 'all' });
  if (!actor) return;
  const actorIsPrrc = actor?.isPRRC === true || normalizeRole(actor?.role) === PORTAL_ROLES.prrc;

  const ticket = (req.query?.ticket || '').toString().trim();
  if (!ticket) return bad(res, 'missing ticket', 400);

  const complaint = await complaintByTicket(ticket);
  if (!complaint) return bad(res, 'not found', 404);

  if (!actorIsPrrc && normalizeRole(actor?.role) !== PORTAL_ROLES.superuser) {
    delete complaint.prrcComment;
    delete complaint.prrcUserId;
    delete complaint.prrcTimestamp;
  }

  const normalizedEmail = normEmail(complaint.email || '');
  if (!withinScope(actor, complaint) && normEmail(actor?.email) !== normalizedEmail) {
    return bad(res, 'forbidden', 403);
  }

  if (!canExport(complaint)) {
    return bad(res, 'export available after closure or rejection', 409);
  }

  const zip = new JSZip();
  const errors = [];

  const history = normalizeHistory(complaint.history);
  zip.file('complaint.json', JSON.stringify(complaint, null, 2));
  zip.file('history.json', JSON.stringify(history, null, 2));
  zip.file('history.txt', historyText(history));

  const uploads = Array.isArray(complaint.uploads) ? complaint.uploads : [];
  if (uploads.length > 0) {
    const folder = zip.folder('uploads');
    await addDownloads(folder, uploads, 'upload', errors);
  }

  const reports = collectReportLinks(complaint);
  if (reports.length > 0) {
    const folder = zip.folder('reports');
    for (let i = 0; i < reports.length; i += 1) {
      const url = reports[i];
      const buffer = await downloadBuffer(url);
      if (buffer) folder.file(`report_${i + 1}.pdf`, buffer);
      else errors.push(`report ${i + 1}: konnte ${url || 'ohne URL'} nicht laden`);
    }
  }

  if (errors.length > 0) {
    zip.file('export_warnings.txt', errors.join('\n'));
  }

  const archive = await zip.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE' });

  res.setHeader('Content-Type', 'application/zip');
  res.setHeader('Content-Disposition', `attachment; filename="reklamation_${ticket}.zip"`);
  res.setHeader('Content-Length', archive.length);
  return res.status(200).send(archive);
}
