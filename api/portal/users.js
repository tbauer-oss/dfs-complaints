// api/portal/users.js – Benutzer- & Rollenverwaltung für DFS Portal
export const config = { runtime: 'nodejs' };

import bcrypt from 'bcryptjs';
import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { portalUsersList, portalUserSave, portalUserDelete, sanitizeTilePermissions } from '../_lib/store.js';
import { normalizeDepartments } from '../_lib/departments.js';
import {
  ADMIN_EMAILS,
  canManageUsers,
  normalizeRole,
  normalizeStatus,
  portalUserFromRequest,
  PORTAL_ROLES,
} from '../_lib/portalAuth.js';
import { createTrackedRedis } from '../chat/v1/_lib/redisTracker.js';
import { normalizeEmail } from '../_lib/identity.js';
import { createRedisAdapter } from '../chat/v1/_lib/redisAdapter.js';
import { keyAvatarMap, normalizeUserId } from '../chat/v1/_lib/schema.js';

const isTruthy = flag => flag === true || flag === 'true' || flag === 1 || flag === '1';

function sanitizeUser(u) {
  const role = normalizeRole(u.role);
  const portalStatus = normalizeStatus(u.portalStatus, u.revoked);
  const tilePermissions = sanitizeTilePermissions(u.tilePermissions || {});
  const hasSalesTile = Object.entries(tilePermissions).some(([key, value]) => {
    const normalizedKey = String(key || '').toLowerCase();
    if (!normalizedKey.includes('sales')) return false;
    const normalizedPerm = String(value || '').toLowerCase();
    return normalizedPerm === 'write';
  });
  const isSales = isTruthy(u.isSales) || isTruthy(u.canEditSales) || isTruthy(u.salesAllowed) || hasSalesTile;

  return {
    email: u.email,
    displayName: u.displayName || u.contact || u.company || '',
    role,
    portalStatus,
    isSales,
    canEditSales: isSales,
    salesAllowed: isSales,
    isPRRC: isTruthy(u.isPRRC),
    assignedDepartments: normalizeDepartments(u.assignedDepartments || []),
    createdAt: u.createdAt || null,
    tilePermissions,
  };
}

async function loadAvatarMap() {
  try {
    const { client } = createTrackedRedis();
    const rdb = createRedisAdapter(client);
    const raw = (await rdb.hgetall(keyAvatarMap())) || {};
    const normalized = {};
    for (const [key, value] of Object.entries(raw)) {
      const normalizedKey = normalizeUserId(key);
      if (normalizedKey) normalized[normalizedKey] = value;
    }
    return normalized;
  } catch (err) {
    console.error('[portal/users] avatarMap error', err);
    return {};
  }
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await portalUserFromRequest(req);
  if (!actor) return bad(res, 'unauthorized', 401);
  if (!canManageUsers(actor.role)) return bad(res, 'forbidden', 403);

  try {
    if (req.method === 'GET') {
      const list = await portalUsersList();
      const portalUsers = list.filter(u => normalizeRole(u.role) !== PORTAL_ROLES.user || u.portalStatus);
      const avatarMap = await loadAvatarMap();
      return ok(
        res,
        portalUsers.map((u) => {
          const normalizedEmail = normalizeUserId(u.email);
          const avatarUrl = normalizedEmail ? avatarMap[normalizedEmail] || null : null;
          const sanitized = sanitizeUser(u);
          return { ...sanitized, avatarUrl, avatar: avatarUrl };
        })
      );
    }

    if (req.method === 'POST') {
      const body = readJson(req) || {};
      const email = normalizeEmail(body.email);
      const password = String(body.password || '');
      const role = normalizeRole(body.role);
      const displayName = String(body.displayName || '').trim();
      const salesFlag = body.isSales ?? body.canEditSales ?? body.salesAllowed;
      const isSales = salesFlag === true || salesFlag === 'true' || salesFlag === 1 || salesFlag === '1';
      const isPRRC = isTruthy(body.isPRRC);
      const assignedDepartments = normalizeDepartments(body.assignedDepartments || []);
      const tilePermissions = sanitizeTilePermissions(body.tilePermissions || {});
      if (!email || !password) return bad(res, 'missing email or password', 400);

      const hash = await bcrypt.hash(password, 10);
      const user = {
        email,
        passhash: hash,
        role: ADMIN_EMAILS.has(email) ? PORTAL_ROLES.superuser : role,
        portalStatus: 'active',
        displayName,
        isSales,
        isPRRC,
        assignedDepartments,
        createdAt: Date.now(),
        tilePermissions,
      };
      await portalUserSave(user);
      return ok(res, sanitizeUser(user));
    }

    if (req.method === 'PATCH') {
      const body = readJson(req) || {};
      const email = normalizeEmail(body.email);
      if (!email) return bad(res, 'missing email', 400);
      const list = await portalUsersList();
      const existing = list.find(u => normalizeEmail(u.email) === email);
      if (!existing) return bad(res, 'not found', 404);

      const patch = { ...existing };
      if (body.displayName !== undefined) patch.displayName = String(body.displayName || '').trim();
      if (body.role) patch.role = normalizeRole(body.role);
      if (body.portalStatus) patch.portalStatus = normalizeStatus(body.portalStatus);
      const salesFlag = body.isSales ?? body.canEditSales ?? body.salesAllowed;
      if (salesFlag !== undefined)
        patch.isSales = salesFlag === true || salesFlag === 'true' || salesFlag === 1 || salesFlag === '1';
      if (body.isPRRC !== undefined) patch.isPRRC = isTruthy(body.isPRRC);
      if (body.assignedDepartments) patch.assignedDepartments = normalizeDepartments(body.assignedDepartments);
      if (body.tilePermissions !== undefined) patch.tilePermissions = sanitizeTilePermissions(body.tilePermissions || {});
      if (body.password) patch.passhash = await bcrypt.hash(String(body.password), 10);

      if (ADMIN_EMAILS.has(email)) {
        patch.role = PORTAL_ROLES.superuser;
        patch.portalStatus = 'active';
      }

      await portalUserSave(patch);
      return ok(res, sanitizeUser(patch));
    }

    if (req.method === 'DELETE') {
      const body = readJson(req) || {};
      const email = normalizeEmail(body.email);
      if (!email) return bad(res, 'missing email', 400);
      if (ADMIN_EMAILS.has(email)) return bad(res, 'cannot delete initial admins', 400);
      await portalUserDelete(email);
      return ok(res, { deleted: email });
    }

    return methodNotAllowed(res);
  } catch (err) {
    return bad(res, err?.message || 'server error', 500);
  }
}
