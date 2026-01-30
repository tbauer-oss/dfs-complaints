// /api/training/program/need-link.js – Remove training program need link
export const config = { runtime: 'nodejs' };

import { withCorsHandler, ok, bad, methodNotAllowed, readJson } from '../../_lib/http.js';
import { requireTrainingScopeAccess } from '../../admin/_guard.js';
import { isAdminUser } from '../../_lib/portalAuth.js';
import {
  trainingProgramGet,
  trainingProgramUpdate,
  trainingProgramNeedLinkDelete,
} from '../../_lib/store.js';

const TRAINING_TILE = 'trainingProgram';

async function handler(req, res) {
  const actor = await requireTrainingScopeAccess(req, res, { tile: TRAINING_TILE, write: true });
  if (!actor) return;
  if (!isAdminUser(actor)) return bad(res, 'forbidden', 403);

  try {
    if (req.method !== 'DELETE') return methodNotAllowed(res);
    const body = readJson(req) || {};
    const programEntryId = body.programEntryId || req.query?.programEntryId;
    const trainingNeedId = body.trainingNeedId || req.query?.trainingNeedId;
    if (!programEntryId || !trainingNeedId) return bad(res, 'missing ids', 400);

    const program = await trainingProgramGet(programEntryId);
    if (!program) return bad(res, 'program not found', 404);
    const nextNeedIds = (program.needIds || []).filter((id) => id !== trainingNeedId);
    await trainingProgramUpdate(programEntryId, {
      needIds: nextNeedIds,
      updatedBy: actor.email,
    });
    const result = await trainingProgramNeedLinkDelete(programEntryId, trainingNeedId);
    return ok(res, { ok: true, removed: result.removed });
  } catch (err) {
    console.error('[training/program/need-link] error', err);
    return bad(res, 'server error', 500);
  }
}

export default withCorsHandler(handler);
