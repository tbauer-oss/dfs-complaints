// api/portal/users.js – Benutzer- & Rollenverwaltung für DFS Portal
export const config = { runtime: 'nodejs' };

import bcrypt from 'bcryptjs';
import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { portalUsersList, portalUserSave, portalUserDelete } from '../_lib/store.js';
import {
  ADMIN_EMAILS,
  canManageUsers,
  normalizeRole,
  normalizeStatus,
  portalUserFromRequest,
  PORTAL_ROLES,
} from '../_lib/portalAuth.js';

function sanitizeUser(u) {
  const role = normalizeRole(u.role);
  const portalStatus = normalizeStatus(u.portalStatus, u.revoked);
  return {
    email: u.email,
    displayName: u.displayName || u.contact || u.company || '',
    role,
    portalStatus,
    createdAt: u.createdAt || null,
  };
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
      return ok(res, portalUsers.map(sanitizeUser));
    }

    if (req.method === 'POST') {
      const body = readJson(req) || {};
      const email = String(body.email || '').trim().toLowerCase();
      const password = String(body.password || '');
      const role = normalizeRole(body.role);
      const displayName = String(body.displayName || '').trim();
      if (!email || !password) return bad(res, 'missing email or password', 400);

      const hash = await bcrypt.hash(password, 10);
      const user = {
        email,
        passhash: hash,
        role: ADMIN_EMAILS.has(email) ? PORTAL_ROLES.superuser : role,
        portalStatus: 'active',
        displayName,
        createdAt: Date.now(),
      };
      await portalUserSave(user);
      return ok(res, sanitizeUser(user));
    }

    if (req.method === 'PATCH') {
      const body = readJson(req) || {};
      const email = String(body.email || '').trim().toLowerCase();
      if (!email) return bad(res, 'missing email', 400);
      const list = await portalUsersList();
      const existing = list.find(u => String(u.email || '').toLowerCase() === email);
      if (!existing) return bad(res, 'not found', 404);

      const patch = { ...existing };
      if (body.displayName !== undefined) patch.displayName = String(body.displayName || '').trim();
      if (body.role) patch.role = normalizeRole(body.role);
      if (body.portalStatus) patch.portalStatus = normalizeStatus(body.portalStatus);
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
      const email = String(body.email || '').trim().toLowerCase();
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

