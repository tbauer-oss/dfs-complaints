// /api/chat/v1/conversations/[id]/messages.js
export const config = { runtime: 'nodejs' };

import { bad, handlePreflight, methodNotAllowed, ok, readJson, setCors } from '../../../../_lib/http.js';
import { getAuthUser } from '../../../../_lib/auth.js';
import { redis } from '../../../../_lib/redis.js';
import { buildPortalUserDirectory } from '../../../../_lib/userDirectory.js';
import { createTrackedRedis, logRedisUsage } from '../../_lib/redisTracker.js';
import { purgeLegacyChatKeys } from '../../_lib/cleanup.js';
import { createRedisAdapter } from '../../_lib/redisAdapter.js';
import {
  appendMessage,
  buildMessagePayload,
  fetchConversationMeta,
  normalizeUserId,
  readMessages,
  registerConversationForUsers,
  upsertUserProfile,
  validateMessageBody,
} from '../../_lib/store.js';
import { buildMessageId, keyConversationMembers, parseTimestamp } from '../../_lib/schema.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const { id } = req.query || {};
  const convId = String(id || '').trim();

  if (!convId) return bad(res, 'missing conversation id', 400);

  const { client, counters } = createTrackedRedis(redis);
  const rdb = createRedisAdapter(client);

  if (process.env.NODE_ENV !== 'production') {
    const capabilities = {
      zrange: typeof client.zrange === 'function',
      zrevrange: typeof client.zrevrange === 'function',
      command: typeof client.command === 'function',
      zrangebyscore: typeof client.zrangebyscore === 'function',
    };
    console.debug('[chat/v1/messages] redis capabilities', capabilities);
  }

  try {
    const actor = getAuthUser(req);
    if (!actor) return bad(res, 'unauthorized', 401);

    const uid = normalizeUserId(actor.email);
    if (!uid) return bad(res, 'invalid user', 400);

    const meta = await fetchConversationMeta(rdb, convId);
    if (!meta) return bad(res, 'conversation not found', 404);

    const membersKey = keyConversationMembers(convId);
    const members = await rdb.smembers(membersKey);
    const isMember = Boolean(await rdb.sismember(membersKey, uid));

    if (!isMember) {
      console.warn('[chat/v1/messages] membership_denied', {
        email: actor.email,
        uid,
        convId,
        membersKey,
        members,
      });
      return bad(res, 'not_a_member', 403, { error: 'not_a_member' });
    }

    if (req.method === 'GET') {
      const afterTs = parseTimestamp(req.query?.afterTs);
      const beforeTs = parseTimestamp(req.query?.beforeTs);
      const limit = Number(req.query?.limit || 50);
      const timeline = await readMessages(rdb, convId, { afterTs, beforeTs, limit });
      logRedisUsage('[chat/v1/messages] read-only', counters, { convId });
      return ok(res, { ok: true, ...timeline });
    }

    if (req.method !== 'POST') return methodNotAllowed(res);

    await purgeLegacyChatKeys(client);

    const body = readJson(req);
    const text = validateMessageBody(body?.body);
    if (!text) return bad(res, 'empty body', 400);

    const requestedMessageId = body?.msgId?.toString();
    const tsMs = Date.now();
    const messageId = requestedMessageId?.startsWith(`${convId}:`)
      ? requestedMessageId
      : buildMessageId(convId, tsMs);

    const directory = await buildPortalUserDirectory();
    const normalizedEmail = actor.email?.toString().trim().toLowerCase();
    const directoryName = directory.get(uid) || (normalizedEmail ? directory.get(normalizedEmail) : null);
    const authorDisplayName =
      directoryName || actor.displayName || actor.name || actor.id || normalizedEmail || 'Unbekannter Nutzer';

    const authorProfile = {
      userId: uid,
      displayName: authorDisplayName,
      email: normalizedEmail,
    };

    await upsertUserProfile(rdb, uid, { displayName: authorProfile.displayName });
    const payload = buildMessagePayload(convId, authorProfile, text, tsMs, messageId);
    const message = await appendMessage(rdb, meta, payload);

    await registerConversationForUsers(rdb, convId, meta.participants, payload.timestampMs);

    logRedisUsage('[chat/v1/messages] write', counters, { convId });

    return ok(res, { ok: true, message });
  } catch (err) {
    console.error('[chat/v1/messages] error', err);
    return bad(res, 'server error', 500);
  }
}
