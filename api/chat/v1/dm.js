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
import { createRedisAdapter } from './_lib/redisAdapter.js';
import { buildDmId, keyConversationMembers, normalizeUserId } from './_lib/schema.js';
import {
  ensureDmConversation,
  fetchConversationMeta,
  persistConversationMeta,
  registerConversationForUsers,
} from './_lib/store.js';

function toTimestampMs(value) {
  const num = Number(value);
  if (Number.isFinite(num)) return num;
  const parsed = Date.parse(String(value));
  return Number.isFinite(parsed) ? parsed : null;
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { write: true });
  if (!actor) return;

  if (req.method !== 'POST') return methodNotAllowed(res);

  const { client, counters } = createTrackedRedis(redis);
  const rdb = createRedisAdapter(client);
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
      typeof body?.peerEmail === 'string' && body.peerEmail.trim()
        ? body.peerEmail
        : typeof body?.otherEmail === 'string' && body.otherEmail.trim()
          ? body.otherEmail
          : body?.otherUid;

    const selfEmail = normalizeUserId(actor?.email);
    if (!selfEmail) return bad(res, 'unauthorized', 401);

    const otherEmail = normalizeUserId(rawOther);
    const isString = typeof rawOther === 'string';
    const isEmailLike = isString && /.+@.+\..+/.test(String(rawOther).trim());

    if (!isString || !otherEmail || !isEmailLike) return bad(res, 'invalid payload', 400);
    if (selfEmail === otherEmail) return bad(res, 'invalid payload', 400);

    const convId = buildDmId(selfEmail, otherEmail);
    if (!convId) return bad(res, 'invalid payload', 400);
    const [, a, b] = convId.split(':');

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
      const existing = await fetchConversationMeta(rdb, convId);
      const meta = existing || (await ensureDmConversation(rdb, a, b));
      const lastActivity =
        meta?.lastMessageAt || meta?.lastMsgAt || meta?.updatedAt || meta?.createdAt || nowIso;

      await registerConversationForUsers(rdb, convId, [a, b], toTimestampMs(lastActivity) || nowMs);
      await Promise.all([
        rdb.sadd(keyConversationMembers(convId), a, b),
        persistConversationMeta(rdb, convId, {
          updatedAt: nowIso,
          lastMsgAt: lastActivity,
          lastMessageAt: lastActivity,
          lastMsgPreview: meta?.lastMsgPreview || meta?.lastMessagePreview || '',
          lastMessagePreview: meta?.lastMsgPreview || meta?.lastMessagePreview || '',
          participants: JSON.stringify([a, b]),
          p1: a,
          p2: b,
        }),
      ]);

      logRedisUsage('[chat/v1/dm] ensured', counters, {
        conversation: convId,
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
