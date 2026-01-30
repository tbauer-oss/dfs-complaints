// /api/me/permissions.js – Effektive Portal-Berechtigungen
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed } from '../_lib/http.js';
import {
  canReadTile,
  canWriteTile,
  canReadTrainingModule,
  canReadTrainingScope,
  canWriteTrainingScope,
  isAdminUser,
  portalUserFromRequest,
} from '../_lib/portalAuth.js';

const KNOWN_TILES = [
  'open',
  'all',
  'complaintList',
  'capaReports',
  'capaDashboard',
  'fmea',
  'internalErrors',
  'changeManagement',
  'audits',
  'trainings',
  'trainingNeeds',
  'trainingProgram',
  'trainingSessions',
  'trainingEffectiveness',
  'trainingArchive',
  'prrc',
  'stats',
  'supplierEvaluation',
  'approvedSuppliers',
  'pending',
  'users',
  'createCustomer',
  'reps',
  'downloads',
  'wiki',
  'news',
  'faq',
  'products',
  'push',
  'internalChat',
  'portalUsers',
  'catalogs',
  'appMeta',
  'testMode',
  'systemHealth',
  'activity',
];

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  if (req.method !== 'GET') return methodNotAllowed(res);

  const actor = await portalUserFromRequest(req);
  if (!actor) return bad(res, 'unauthorized', 401);

  const permissions = {};
  const tileGrants = new Set();
  for (const tile of KNOWN_TILES) {
    const canRead = canReadTile(actor, tile);
    const canWrite = canWriteTile(actor, tile);
    permissions[`${tile}Read`] = canRead;
    permissions[`${tile}Write`] = canWrite;
    if (canRead || canWrite) tileGrants.add(tile);
  }

  const tilePermissions = actor.tilePermissions || {};
  for (const [tile, perm] of Object.entries(tilePermissions)) {
    if (String(perm || '').toLowerCase() === 'none') continue;
    tileGrants.add(tile);
  }

  permissions.training_view = canReadTrainingModule(actor);
  permissions.training_needs_read = canReadTrainingScope(actor, 'trainingNeeds');
  permissions.training_needs_write = canWriteTrainingScope(actor, 'trainingNeeds');
  permissions.training_program_read = canReadTrainingScope(actor, 'trainingProgram');
  permissions.training_program_write = canWriteTrainingScope(actor, 'trainingProgram');
  permissions.training_sessions_read = canReadTrainingScope(actor, 'trainingSessions');
  permissions.training_sessions_write = canWriteTrainingScope(actor, 'trainingSessions');
  permissions.training_questionnaires_read = canReadTrainingScope(actor, 'trainingEffectiveness');
  permissions.training_questionnaires_write = canWriteTrainingScope(actor, 'trainingEffectiveness');
  permissions.training_delete = actor.role === 'superuser';

  const profile = {
    email: actor.email,
    displayName: actor.displayName || actor.contact || actor.company || actor.email,
    role: actor.role,
    portalStatus: actor.portalStatus,
    tilePermissions,
    isSales: actor.isSales === true,
    isPRRC: actor.isPRRC === true,
  };

  return ok(res, {
    ok: true,
    userId: actor.email,
    roles: [actor.role],
    isAdmin: isAdminUser(actor),
    isSuperuser: actor.role === 'superuser',
    tileGrants: Array.from(tileGrants),
    tilePermissions,
    permissions,
    profile,
  });
}
