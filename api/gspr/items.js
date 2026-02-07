// /api/gspr/items.js – CRUD für GSPR Items
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { requirePortalAccess } from '../admin/_guard.js';
import { gsprAllByChapter, gsprSave, gsprAddAuditEvent } from '../_lib/store.js';

const GSPR_TILE = 'gspr';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const wantsWrite = ['POST'].includes(req.method);
  const actor = await requirePortalAccess(req, res, { tile: GSPR_TILE, write: wantsWrite });
  if (!actor) return;

  try {
    if (req.method === 'GET') {
      const chapter = (req.query?.chapter || '').toString();
      const items = await gsprAllByChapter(chapter);
      return ok(res, { ok: true, items });
    }

    if (req.method === 'POST') {
      const body = readJson(req) || {};
      const payload = { ...body, updatedBy: actor.email };
      const saved = await gsprSave(payload);
      await gsprAddAuditEvent(saved.id, {
        gsprItemId: saved.id,
        timestamp: Date.now(),
        actorUserId: actor.email,
        actorName: actor.displayName || actor.email,
        action: 'EDIT',
        fromStatus: null,
        toStatus: saved.status,
        comment: 'created',
      });
      return ok(res, { ok: true, item: saved });
    }

    return methodNotAllowed(res);
  } catch (err) {
    console.error('[gspr/items] error', err);
    return bad(res, err?.message || 'server error', 500);
  }
}
