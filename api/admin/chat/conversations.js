// /api/admin/chat/conversations.js
export const config = { runtime: 'nodejs' };

import { bad, handlePreflight, methodNotAllowed, ok, setCors } from '../../_lib/http.js';
import { requirePortalAccess } from '../_guard.js';
import { getContextMeta, getLastReads, listContextsForUser } from '../../_lib/chat.js';

function toBool(val) {
  return String(val || '').toLowerCase() === 'true';
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { write: false });
  if (!actor) return;

  if (req.method !== 'GET') return methodNotAllowed(res);

  try {
    const includeMeta = toBool(req.query?.meta ?? 'true');
    const contexts = await listContextsForUser(actor.email);
    const reads = await getLastReads(actor.email);

    const entries = await Promise.all(
      contexts.map(async (contextId) => {
        const lastRead = reads?.[contextId] ?? null;
        const meta = includeMeta ? await getContextMeta(contextId) : null;
        const updatedAt = meta?.updatedAt || null;
        const unread = updatedAt && (!lastRead || new Date(updatedAt).getTime() > new Date(lastRead).getTime());
        return {
          contextId,
          lastRead,
          unread: !!unread,
          meta: meta || null,
        };
      })
    );

    entries.sort((a, b) => {
      const tA = a.meta?.updatedAt ? new Date(a.meta.updatedAt).getTime() : 0;
      const tB = b.meta?.updatedAt ? new Date(b.meta.updatedAt).getTime() : 0;
      return tB - tA;
    });

    return ok(res, { ok: true, contexts: entries });
  } catch (err) {
    console.error('[admin/chat/conversations] error', err);
    return bad(res, 'server error', 500);
  }
}
