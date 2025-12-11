// api/_lib/portalAuth.js
// Zentrale Portal-Auth (DFS Portal / vormals Adminbereich)
//  - Hinterlegte Admin-E-Mails
//  - Initialpasswort = ADMIN_SECRET (aus Umgebung)
//  - Rollenprüfung für Portal-Endpunkte

import bcrypt from 'bcryptjs';
import { getAuthUser } from './auth.js';
import { normalizeTilePermission, portalUserByEmail, portalUserSave, sanitizeTilePermissions } from './store.js';

// Die Portal-Rolle wird direkt am User-Objekt unter `user.role` gespeichert.
// Gültige Werte sind unten definiert und werden in den Guards/Handlers geprüft.
export const PORTAL_ROLES = {
  superuser: 'superuser',
  user: 'user',
  readonly: 'readonly',
  prrc: 'prrc',
};

export const DFS_PORTAL_EMAIL_FORBIDDEN_MSG =
  'Diese E-Mail gehört zu einem internen DFS-Account und kann nicht als Kundenkonto verwendet werden.';

// Hinterlegte Admin-E-Mails (Superuser) – Initialpasswort = ADMIN_SECRET
export const ADMIN_EMAILS = new Set([
  'tobias.bauer@dfs-diamon.de',
  'elisabeth.kersjes@dfs-diamon.de',
]);

const ADMIN_SECRET = process.env.ADMIN_SECRET || '';

export function normalizeRole(role) {
  const lc = String(role || '').trim().toLowerCase();
  if (lc === PORTAL_ROLES.superuser) return PORTAL_ROLES.superuser;
  if (lc === PORTAL_ROLES.readonly) return PORTAL_ROLES.readonly;
  if (lc === PORTAL_ROLES.prrc) return PORTAL_ROLES.prrc;
  return PORTAL_ROLES.user;
}

export function normalizeStatus(status, revoked = false) {
  if (revoked) return 'inactive';
  const lc = String(status || '').trim().toLowerCase();
  return lc === 'inactive' ? 'inactive' : 'active';
}

export async function isPortalEmail(email) {
  const mail = String(email || '').trim().toLowerCase();
  if (!mail) return false;
  if (ADMIN_EMAILS.has(mail)) return true;

  try {
    const portal = await portalUserByEmail(mail);
    return !!portal;
  } catch {
    return false;
  }
}

export function canWrite(role) {
  const r = normalizeRole(role);
  return r === PORTAL_ROLES.superuser || r === PORTAL_ROLES.user;
}

export function tilePermissionForUser(user, tileId) {
  if (!tileId) return canWrite(user?.role) ? 'write' : 'read';
  const normalized = normalizeTilePermission(user?.tilePermissions?.[tileId]);
  if (normalized) return normalized;
  return canWrite(user?.role) ? 'write' : 'read';
}

export function canReadTile(user, tileId) {
  const perm = tilePermissionForUser(user, tileId);
  return perm === 'write' || perm === 'read';
}

export function canWriteTile(user, tileId) {
  const override = normalizeTilePermission(user?.tilePermissions?.[tileId]);
  if (override) return override === 'write';
  return canWrite(user?.role);
}

export function canManageUsers(role) {
  return normalizeRole(role) === PORTAL_ROLES.superuser;
}

async function ensureInitialAdmin(email) {
  const mail = String(email || '').trim().toLowerCase();
  if (!mail) return null;
  const existing = await portalUserByEmail(mail).catch(() => null);
  const passhash = ADMIN_SECRET ? await bcrypt.hash(ADMIN_SECRET, 10) : '';
  const base = {
    email: mail,
    passhash,
    portalStatus: 'active',
    role: PORTAL_ROLES.superuser,
    displayName: mail.split('@')[0],
    createdAt: Date.now(),
  };

  if (!existing) {
    await portalUserSave(base);
    return base;
  }

  const toSave = { ...existing };
  if (!toSave.passhash && passhash) toSave.passhash = passhash;
  if (!toSave.role) toSave.role = PORTAL_ROLES.superuser;
  if (!toSave.portalStatus) toSave.portalStatus = 'active';
  await portalUserSave(toSave);
  return toSave;
}

export async function ensureInitialAdmins() {
  for (const mail of ADMIN_EMAILS) {
    await ensureInitialAdmin(mail);
  }
}

export async function portalUserFromRequest(req, { allowSecretFallback = true } = {}) {
  const tokenUser = getAuthUser(req);
  if (tokenUser?.email) {
    const stored = await portalUserByEmail(tokenUser.email).catch(() => null);
    if (stored) {
      const role = normalizeRole(stored.role);
      const status = normalizeStatus(stored.portalStatus, stored.revoked);
      const tilePermissions = sanitizeTilePermissions(stored.tilePermissions);
      if (status === 'active') {
        return { ...stored, role, portalStatus: status, tilePermissions };
      }
    } else if (normalizeRole(tokenUser.role) === PORTAL_ROLES.superuser) {
      const role = normalizeRole(tokenUser.role);
      const portalStatus = normalizeStatus(tokenUser.portalStatus);
      if (portalStatus === 'active') {
        return { ...tokenUser, role, portalStatus, tilePermissions: sanitizeTilePermissions(tokenUser.tilePermissions) };
      }
    }
  }

  if (allowSecretFallback) {
    const hdr = req.headers?.['x-admin-secret'];
    if (hdr && ADMIN_SECRET && hdr === ADMIN_SECRET) {
      // Legacy Secret bleibt Superuser
      return {
        email: 'admin-secret',
        role: PORTAL_ROLES.superuser,
        portalStatus: 'active',
        via: 'secret',
      };
    }
  }
  return null;
}

export async function requirePortalRole(req, res, { minRole = PORTAL_ROLES.user, allowSecretFallback = true } = {}) {
  const user = await portalUserFromRequest(req, { allowSecretFallback });
  if (!user) return false;

  const role = normalizeRole(user.role);
  if (minRole === PORTAL_ROLES.superuser && role !== PORTAL_ROLES.superuser) return false;
  return true;
}
