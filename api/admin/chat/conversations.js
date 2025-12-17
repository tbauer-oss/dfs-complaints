// /api/admin/chat/conversations.js
export const config = { runtime: 'nodejs' };

import { bad, handlePreflight, methodNotAllowed, ok, setCors } from '../../_lib/http.js';
import { requirePortalAccess } from '../_guard.js';
import {
  getContextMeta,
  getLastReads,
  listContextsForUser,
  migrateLegacyContext,
  parseContextId,
  userIdAliases,
  normalizeUserId,
} from '../../_lib/chat.js';
import { buildPortalUserDirectory } from '../../_lib/userDirectory.js';

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
        const parsed = parseContextId(contextId);
        const key = parsed?.contextId || contextId;
        const prev = reads[key];
        if (!prev || new Date(ts).getTime() > new Date(prev).getTime()) {
          reads[key] = ts;
        }
        if (parsed?.legacyId) {
          reads[parsed.legacyId] = reads[key];
        }
      }
    }

    const userDirectory = await buildPortalUserDirectory();

    const selfId = normalizeUserId(actor.email);
    const selfDisplayName = actor?.displayName || actor?.name || actor?.id || 'Unbekannter Nutzer';

    const entries = await Promise.all(
      Array.from(contextsSet.values()).map(async (contextId) => {
        const parsedRaw = parseContextId(contextId);
        if (!parsedRaw) return null;
        const parsed = await migrateLegacyContext(parsedRaw);
        const normalizedContextId = parsed.contextId;
        contextsSet.add(normalizedContextId);
        const participants = (parsed?.participants || []).map((p) => ({
          userId: p,
          displayName: p === selfId ? selfDisplayName : userDirectory.get(p) || 'Unbekannter Nutzer',
        }));
        const lastRead = reads?.[normalizedContextId] ?? null;
        const metaRaw = includeMeta ? await getContextMeta(normalizedContextId) : null;
        const updatedAt = metaRaw?.updatedAt || null;
        const unread = updatedAt && (!lastRead || new Date(updatedAt).getTime() > new Date(lastRead).getTime());
        let meta = metaRaw || null;
        if (parsed?.type === 'dm') {
          const other = participants.find((p) => p.userId !== selfId) || participants[0];
          const reference = other.displayName || 'Direktnachricht';
          if (meta) {
            meta = { ...meta, reference };
          } else {
            meta = { contextId: normalizedContextId, type: 'dm', reference };
          }
        }
        return {
          contextId: normalizedContextId,
          participants,
          lastRead,
          unread: !!unread,
          meta,
        };
      })
    );

    const filteredEntries = entries.filter(Boolean);

    filteredEntries.sort((a, b) => {
      const tA = a.meta?.updatedAt ? new Date(a.meta.updatedAt).getTime() : 0;
      const tB = b.meta?.updatedAt ? new Date(b.meta.updatedAt).getTime() : 0;
      return tB - tA;
    });

    return ok(res, { ok: true, contexts: filteredEntries });
  } catch (err) {
    console.error('[admin/chat/conversations] error', err);
    return bad(res, 'server error', 500);
  }
}
