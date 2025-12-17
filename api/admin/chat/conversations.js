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
    const contextsMap = new Map();
    const readEntries = [];

    for (const key of userKeys) {
      const ctxs = await listContextsForUser(key);
      for (const ctx of ctxs) {
        const existing = contextsMap.get(ctx.contextId);
        const ts = ctx.lastActivity ? new Date(ctx.lastActivity).getTime() : 0;
        const prevTs = existing?.lastActivity ? new Date(existing.lastActivity).getTime() : 0;
        if (!existing || ts > prevTs) {
          contextsMap.set(ctx.contextId, { ...ctx });
        }
      }
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
      Array.from(contextsMap.values()).map(async ({ contextId, lastActivity }) => {
        const parsedRaw = parseContextId(contextId);
        if (!parsedRaw) return null;
        const parsed = await migrateLegacyContext(parsedRaw);
        const normalizedContextId = parsed.contextId;
        const participants = (parsed?.participants || []).map((p) => ({
          userId: p,
          displayName: p === selfId ? selfDisplayName : userDirectory.get(p) || 'Unbekannter Nutzer',
        }));
        const lastRead = reads?.[normalizedContextId] ?? null;
        const metaRaw = includeMeta ? await getContextMeta(normalizedContextId) : null;
        const updatedAt = metaRaw?.updatedAt || lastActivity || null;
        const unread = updatedAt && lastRead
          ? new Date(updatedAt).getTime() > new Date(lastRead).getTime()
          : false;
        let meta = metaRaw || null;
        if (parsed?.type === 'dm') {
          const other = participants.find((p) => p.userId !== selfId) || participants[0];
          const reference = other.displayName || 'Direktnachricht';
          if (meta) {
            meta = { ...meta, reference };
          } else {
            meta = { contextId: normalizedContextId, type: 'dm', reference, updatedAt };
          }
        } else if (!meta && updatedAt) {
          meta = { contextId: normalizedContextId, type: parsed?.type, reference: parsed?.reference || '', updatedAt };
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

    console.info('[admin/chat/conversations] read-only', { contexts: filteredEntries.length, writes: 0 });

    return ok(res, { ok: true, contexts: filteredEntries });
  } catch (err) {
    console.error('[admin/chat/conversations] error', err);
    return bad(res, 'server error', 500);
  }
}
