// /api/chat/v1/dm.js
export const config = { runtime: 'nodejs' };

import { bad, handlePreflight, methodNotAllowed, ok, readJson, setCors } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { redis } from '../../_lib/redis.js';
import { createTrackedRedis, logRedisUsage } from './_lib/redisTracker.js';
import {
  buildConversationId,
  keyConversationMembers,
  keyConversationMeta,
  keyUserConversations,
  normalizeUserId,
} from './_lib/schema.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { write: true });
  if (!actor) return;

  if (req.method !== 'POST') return methodNotAllowed(res);

  const { client, counters } = createTrackedRedis(redis);

  try {
    const body = readJson(req);
    const otherRaw = body?.otherUid ?? body?.participant ?? body?.userId ?? '';

    const selfId = normalizeUserId(actor.email || actor.id);
    const peerId = normalizeUserId(otherRaw);
    if (!selfId || typeof otherRaw !== 'string' || !peerId) return bad(res, 'invalid payload', 400);
    if (selfId === peerId) return bad(res, 'invalid payload', 400);

    const convId = buildConversationId(selfId, peerId);
    if (!convId) return bad(res, 'invalid payload', 400);
    const metaKey = keyConversationMeta(convId);
    let metaExists = false;

    try {
      metaExists = Boolean(await client.exists(metaKey));
      console.info('[chat/v1/dm] create', { uid: selfId, otherUid: peerId, convId, metaExists });

      if (!metaExists) {
        const nowIso = new Date().toISOString();
        const pipeline = typeof client.multi === 'function' ? client.multi() : null;

        if (pipeline) {
          pipeline.hset(metaKey, { type: 'dm', createdAt: nowIso, updatedAt: nowIso, lastMsgAt: 0 });
          pipeline.sadd(keyConversationMembers(convId), [selfId, peerId]);
          pipeline.zadd(keyUserConversations(selfId), { score: 0, member: convId });
          pipeline.zadd(keyUserConversations(peerId), { score: 0, member: convId });
          await pipeline.exec();
        } else {
          await Promise.all([
            client.hset(metaKey, { type: 'dm', createdAt: nowIso, updatedAt: nowIso, lastMsgAt: 0 }),
            client.sadd(keyConversationMembers(convId), [selfId, peerId]),
            client.zadd(keyUserConversations(selfId), { score: 0, member: convId }),
            client.zadd(keyUserConversations(peerId), { score: 0, member: convId }),
          ]);
        }
      }

      logRedisUsage('[chat/v1/dm] ensured', counters, { conversation: convId, metaExists });

      return ok(res, { convId });
    } catch (redisErr) {
      console.error('[chat/v1/dm] redis error', redisErr);
      return bad(res, 'dm_create_failed', 500);
    }
  } catch (err) {
    console.error('[chat/v1/dm] error', err);
    return bad(res, 'dm_create_failed', 500);
  }
}
