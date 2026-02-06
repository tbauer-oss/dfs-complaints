// /api/chat/v1/conversations/[id]
export const config = { runtime: 'nodejs' };

import { bad, handlePreflight, methodNotAllowed, ok, setCors } from '../../../../_lib/http.js';
import { requirePortalAccess } from '../../../../admin/_guard.js';
import { redis } from '../../../../_lib/redis.js';
import { createTrackedRedis, logRedisUsage } from '../../_lib/redisTracker.js';
import { createRedisAdapter } from '../../_lib/redisAdapter.js';
import {
  canonicalizeConversationId,
  keyConversationMembers,
  keyConversationMessages,
  keyConversationMessagesLegacy,
  keyConversationMessagesV2,
  keyConversationMeta,
  keyConversationMetaCompat,
  keyConversationMetaLegacy,
  keyConversationMetaV2,
  keyMessage,
  keyMessageV2,
  keyUserConversations,
  keyUserInbox,
  keyUserInboxV2,
} from '../../_lib/schema.js';
import { fetchConversationMeta, normalizeUserId } from '../../_lib/store.js';
import { normalizeRole, PORTAL_ROLES } from '../../../../_lib/portalAuth.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { write: false });
  if (!actor) return;

  if (req.method !== 'DELETE') return methodNotAllowed(res);

  const { id } = req.query || {};
  const requestedConvId = String(id || '').trim();
  const canonicalConvId = canonicalizeConversationId(requestedConvId) || requestedConvId;

  if (!requestedConvId) return bad(res, 'missing conversation id', 400);

  const { client, counters } = createTrackedRedis(redis);
  const rdb = createRedisAdapter(client);

  try {
    const uid = normalizeUserId(actor.email);
    if (!uid) return bad(res, 'invalid user', 400);

    const meta =
      (canonicalConvId && (await fetchConversationMeta(rdb, canonicalConvId))) ||
      (canonicalConvId !== requestedConvId ? await fetchConversationMeta(rdb, requestedConvId) : null);

    if (!meta) {
      logRedisUsage('[chat/v1/conversation] delete noop', counters, { convId: requestedConvId });
      return ok(res, { ok: true, id: canonicalConvId });
    }

    const convId = canonicalizeConversationId(meta.convId) || canonicalConvId || requestedConvId;
    const participants = Array.isArray(meta.participants) ? meta.participants : [];
    const isParticipant = participants.includes(uid);
    const isSuperuser = normalizeRole(actor.role) === PORTAL_ROLES.superuser;
    if (!isParticipant && !isSuperuser) {
      return bad(res, 'not_a_member', 403, { error: 'not_a_member' });
    }

    const messageIds = new Set();
    const messageSets = [
      keyConversationMessagesV2(convId),
      keyConversationMessages(convId),
      keyConversationMessagesLegacy(convId),
    ];

    for (const key of messageSets) {
      const members = await rdb.zrange(key, 0, -1);
      members.filter(Boolean).forEach((m) => messageIds.add(m));
    }

    const metaKeys = [
      keyConversationMeta(convId),
      keyConversationMetaCompat(convId),
      keyConversationMetaLegacy(convId),
      keyConversationMetaV2(convId),
      keyConversationMembers(convId),
      ...messageSets,
    ];

    const messageKeys = Array.from(messageIds.values()).flatMap((msgId) => [keyMessage(msgId), keyMessageV2(msgId)]);

    const inboxRemovals = participants.flatMap((participant) => [
      rdb.zrem(keyUserInboxV2(participant), convId),
      rdb.zrem(keyUserInbox(participant), convId),
      rdb.zrem(keyUserConversations(participant), convId),
    ]);

    if (messageKeys.length > 0) await rdb.del(...messageKeys);
    if (metaKeys.length > 0) await rdb.del(...metaKeys);
    if (inboxRemovals.length > 0) await Promise.all(inboxRemovals);

    logRedisUsage('[chat/v1/conversation] delete', counters, { convId });

    return ok(res, { ok: true, id: convId });
  } catch (err) {
    console.error('[chat/v1/conversation] delete error', err);
    return bad(res, 'server error', 500);
  }
}
