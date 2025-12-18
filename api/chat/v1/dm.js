// /api/chat/v1/dm.js
export const config = { runtime: 'nodejs' };

import { bad, handlePreflight, methodNotAllowed, ok, readJson, setCors } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { redis } from '../../_lib/redis.js';
import { createTrackedRedis, logRedisUsage } from './_lib/redisTracker.js';
import { purgeLegacyChatKeys } from './_lib/cleanup.js';
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
    await purgeLegacyChatKeys(client);

    const body = readJson(req);
    const otherRaw = body?.otherEmail || '';

    const selfEmail = normalizeUserId(actor.email);
    const peerEmail = normalizeUserId(otherRaw);
    if (!selfEmail || typeof otherRaw !== 'string' || !peerEmail) return bad(res, 'invalid payload', 400);
    if (selfEmail === peerEmail) return bad(res, 'invalid payload', 400);

    const convId = buildConversationId(selfEmail, peerEmail);
    if (!convId) return bad(res, 'invalid payload', 400);
    const metaKey = keyConversationMeta(convId);
    let metaExists = false;

    try {
      metaExists = Boolean(await client.exists(metaKey));
      console.info('[chat/v1/dm] create', { uid: selfEmail, otherUid: peerEmail, convId, metaExists });

      const nowIso = new Date().toISOString();
      const participants = [selfEmail, peerEmail].sort();
      const existingMeta = metaExists ? await client.hgetall(metaKey) : null;
      const createdAt = existingMeta?.createdAt || existingMeta?.created_at || nowIso;
      const updatedAt = existingMeta?.updatedAt || existingMeta?.updated_at || existingMeta?.lastMsgAt || nowIso;
      const lastMsgAt = existingMeta?.lastMsgAt || existingMeta?.lastMsg_at || existingMeta?.updatedAt || existingMeta?.createdAt || 0;
      const serializedParticipants = existingMeta?.participants || JSON.stringify(participants);
      const p1 = existingMeta?.p1 || participants[0];
      const p2 = existingMeta?.p2 || participants[1];
      const pipeline = typeof client.multi === 'function' ? client.multi() : null;

      if (pipeline) {
        pipeline.hset(metaKey, {
          type: 'dm',
          createdAt,
          updatedAt,
          lastMsgAt,
          participants: serializedParticipants,
          p1,
          p2,
        });
        pipeline.sadd(keyConversationMembers(convId), participants);
        pipeline.zadd(keyUserConversations(selfEmail), { score: 0, member: convId });
        pipeline.zadd(keyUserConversations(peerEmail), { score: 0, member: convId });
        await pipeline.exec();
      } else {
        await Promise.all([
          client.hset(metaKey, {
            type: 'dm',
            createdAt,
            updatedAt,
            lastMsgAt,
            participants: serializedParticipants,
            p1,
            p2,
          }),
          client.sadd(keyConversationMembers(convId), participants),
          client.zadd(keyUserConversations(selfEmail), { score: 0, member: convId }),
          client.zadd(keyUserConversations(peerEmail), { score: 0, member: convId }),
        ]);
      }

      logRedisUsage('[chat/v1/dm] ensured', counters, { conversation: convId, metaExists, participants });

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
