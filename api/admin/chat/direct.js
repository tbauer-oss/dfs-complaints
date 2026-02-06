// /api/admin/chat/direct.js
export const config = { runtime: 'nodejs' };

import { bad, handlePreflight, methodNotAllowed, ok, readJson, setCors } from '../../_lib/http.js';
import { requirePortalAccess } from '../_guard.js';
import {
  buildDmContext,
  getContextMeta,
  migrateLegacyContext,
  touchContextsForUsers,
  userIdAliases,
  normalizeUserId,
} from '../../_lib/chat.js';
import { buildPortalUserDirectory } from '../../_lib/userDirectory.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { write: true });
  if (!actor) return;

  if (req.method !== 'POST') return methodNotAllowed(res);

  try {
    const body = readJson(req) || {};
    const peer = String(body.participant || body.userId || '').trim();
    if (!peer) return bad(res, 'participant required', 400);

    const contextRaw = buildDmContext(actor.email, peer);
    if (!contextRaw) return bad(res, 'invalid participant', 400);

    const context = await migrateLegacyContext(contextRaw);
    const actorIds = userIdAliases(actor.email);
    const peerIds = userIdAliases(peer);
    const touchTs = new Date().toISOString();
    await touchContextsForUsers([...actorIds, ...peerIds], context.contextId, context.type, touchTs);

    const userDirectory = await buildPortalUserDirectory();

    const selfId = normalizeUserId(actor.email);
    const selfDisplayName =
      actor?.displayName || actor?.name || actor?.id || userDirectory.get(selfId) || 'Unbekannter Nutzer';

    const peerAliases = userIdAliases(peer);
    const peerId = context.participants.find((p) => p !== selfId) || context.participants[0];
    const peerDisplayName =
      peerAliases.map((a) => userDirectory.get(a)).find(Boolean) || userDirectory.get(peerId) || 'Unbekannter Nutzer';

    const participants = context.participants.map((p) => ({
      userId: p,
      displayName: p === selfId ? selfDisplayName : peerDisplayName,
    }));

    const metaRaw = await getContextMeta(context.contextId);
    let meta = metaRaw || null;
    const other = participants.find((p) => p.userId !== selfId) || participants[0];
    const reference = other.displayName || 'Direktnachricht';
    if (meta) {
      meta = { ...meta, reference };
    } else {
      meta = { contextId: context.contextId, type: 'dm', reference, updatedAt: touchTs };
    }

    return ok(res, {
      ok: true,
      context: {
        contextId: context.contextId,
        participants,
        meta,
        unread: false,
        lastRead: null,
      },
    });
  } catch (err) {
    console.error('[admin/chat/direct] error', err);
    return bad(res, 'server error', 500);
  }
}
