// /api/admin/chat/conversations.js
export const config = { runtime: 'nodejs' };

import { bad, handlePreflight, methodNotAllowed, ok, setCors } from '../../_lib/http.js';
import { requirePortalAccess } from '../_guard.js';
import { getContextMeta, getLastReads, listContextsForUser, parseContextId, userIdAliases, normalizeUserId } from '../../_lib/chat.js';
import { portalUsersList } from '../../_lib/store.js';

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
    const userKeys = userIdAliases(actor.email);
    const contextsSet = new Set();
    const readEntries = [];

    for (const key of userKeys) {
      const ctxs = await listContextsForUser(key);
      ctxs.forEach((c) => contextsSet.add(c));
      const r = await getLastReads(key);
      if (r) readEntries.push(r);
    }

    const reads = {};
    for (const entry of readEntries) {
      for (const [contextId, ts] of Object.entries(entry)) {
        const prev = reads[contextId];
        if (!prev || new Date(ts).getTime() > new Date(prev).getTime()) {
          reads[contextId] = ts;
        }
      }
    }

    const portalUsers = await portalUsersList();
    const userDirectory = new Map();
    for (const u of portalUsers) {
      const userId = normalizeUserId(u.email);
      if (!userId) continue;
      userDirectory.set(userId, u.displayName || u.contact || u.company || '');
    }

    const entries = await Promise.all(
      Array.from(contextsSet.values()).map(async (contextId) => {
        const parsed = parseContextId(contextId);
        const participants = (parsed?.participants || []).map((p) => ({
          userId: p,
          displayName: userDirectory.get(p) || 'Unbekannter Nutzer',
        }));
        const lastRead = reads?.[contextId] ?? null;
        const metaRaw = includeMeta ? await getContextMeta(contextId) : null;
        const updatedAt = metaRaw?.updatedAt || null;
        const unread = updatedAt && (!lastRead || new Date(updatedAt).getTime() > new Date(lastRead).getTime());
        let meta = metaRaw || null;
        if (meta && parsed?.type === 'dm' && participants.length > 0) {
          const selfId = normalizeUserId(actor.email);
          const other = participants.find((p) => p.userId !== selfId) || participants[0];
          meta = { ...meta, reference: other.displayName || 'Direktnachricht' };
        }
        return {
          contextId,
          participants,
          lastRead,
          unread: !!unread,
          meta,
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
