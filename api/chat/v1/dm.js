// /api/chat/v1/dm.js
export const config = { runtime: 'nodejs' };

import {
  bad,
  handlePreflight,
  methodNotAllowed,
  ok,
  readJsonBody,
  setCors,
} from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { redis } from '../../_lib/redis.js';
import { createTrackedRedis, logRedisUsage } from './_lib/redisTracker.js';
import { purgeLegacyChatKeys } from './_lib/cleanup.js';
import { keyConversationMembers, keyConversationMeta, keyUserConversations, normalizeUserId } from './_lib/schema.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { write: true });
  if (!actor) return;

  if (req.method !== 'POST') return methodNotAllowed(res);

  const { client, counters } = createTrackedRedis(redis);
  const isDev = process.env.NODE_ENV !== 'production';
  const hasRedisEnv = Boolean(process.env.UPSTASH_REDIS_REST_URL && process.env.UPSTASH_REDIS_REST_TOKEN);

  try {
    try {
      await purgeLegacyChatKeys(client);
    } catch (err) {
      console.warn('[chat/v1/dm] cleanup skipped', err);
    }

    let body = {};
    try {
      body = await readJsonBody(req);
    } catch (parseErr) {
      console.error('[chat/v1/dm] body parse error', parseErr);
      return bad(res, 'invalid payload', parseErr.statusCode || 400);
    }

    const rawOther =
      typeof body?.otherEmail === 'string' && body.otherEmail.trim() ? body.otherEmail : body?.otherUid;

    const selfEmail = normalizeUserId(actor?.email);
    if (!selfEmail) return bad(res, 'unauthorized', 401);

    const otherEmail = normalizeUserId(rawOther);
    const isString = typeof rawOther === 'string';
    const isEmailLike = isString && /.+@.+\..+/.test(String(rawOther).trim());

    if (!isString || !otherEmail || !isEmailLike) return bad(res, 'invalid payload', 400);
    if (selfEmail === otherEmail) return bad(res, 'invalid payload', 400);

    const [a, b] = [selfEmail, otherEmail].map((s) => s.trim().toLowerCase()).sort();
    const convId = `dm:${a}:${b}`;

    const metaKey = keyConversationMeta(convId);
    const membersKey = keyConversationMembers(convId);
    const z1 = keyUserConversations(a);
    const z2 = keyUserConversations(b);

    const nowMs = Date.now();
    const nowIso = new Date(nowMs).toISOString();

    if (isDev) {
      console.info('[chat/v1/dm] debug', {
        meEmail: selfEmail,
        otherEmail,
        convId,
        redisEnvMissing: !hasRedisEnv,
      });
    }

    try {
      const metaExists = Boolean(await client.exists(metaKey));
      const existingCreatedAt = metaExists ? await client.hget(metaKey, 'createdAt') : null;
      const metaPayload = { type: 'dm', updatedAt: nowIso };
      if (!existingCreatedAt) metaPayload.createdAt = nowIso;

      const pipeline = typeof client.multi === 'function' ? client.multi() : null;

      if (pipeline) {
        pipeline.sadd(membersKey, a, b);
        pipeline.hset(metaKey, metaPayload);
        pipeline.zadd(z1, { score: nowMs, member: convId });
        pipeline.zadd(z2, { score: nowMs, member: convId });
        await pipeline.exec();
      } else {
        await Promise.all([
          client.sadd(membersKey, a, b),
          client.hset(metaKey, metaPayload),
          client.zadd(z1, { score: nowMs, member: convId }),
          client.zadd(z2, { score: nowMs, member: convId }),
        ]);
      }

      logRedisUsage('[chat/v1/dm] ensured', counters, {
        conversation: convId,
        metaExists,
        participants: [a, b],
      });

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
