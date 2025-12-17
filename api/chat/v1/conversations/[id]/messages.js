// /api/chat/v1/conversations/[id]/messages.js
export const config = { runtime: 'nodejs' };

import { bad, handlePreflight, methodNotAllowed, ok, readJson, setCors } from '../../../../_lib/http.js';
import { requirePortalAccess } from '../../../../admin/_guard.js';
import { redis } from '../../../../_lib/redis.js';
import { createTrackedRedis, logRedisUsage } from '../../_lib/redisTracker.js';
import { purgeLegacyChatKeys } from '../../_lib/cleanup.js';
import {
  appendMessage,
  buildMessagePayload,
  fetchConversationMeta,
  normalizeUserId,
  readMessages,
  registerConversationForUsers,
  requireParticipant,
  upsertUserProfile,
  validateMessageBody,
} from '../../_lib/store.js';
import { buildMessageId, parseTimestamp } from '../../_lib/schema.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { write: req.method === 'POST' });
  if (!actor) return;

  const { id } = req.query || {};
  const convId = String(id || '').trim();

  if (!convId) return bad(res, 'missing conversation id', 400);

  const { client, counters } = createTrackedRedis(redis);

  try {
    const meta = await fetchConversationMeta(client, convId);
    if (!meta) return bad(res, 'conversation not found', 404);

    const uid = normalizeUserId(actor.email || actor.id);
    if (!uid || !requireParticipant(meta, uid)) return bad(res, 'forbidden', 403);

    if (req.method === 'GET') {
      const afterTs = parseTimestamp(req.query?.afterTs);
      const beforeTs = parseTimestamp(req.query?.beforeTs);
      const limit = Number(req.query?.limit || 50);
      const timeline = await readMessages(client, convId, { afterTs, beforeTs, limit });
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

    const authorProfile = {
      userId: uid,
      displayName: actor.displayName || actor.name || actor.id || 'Unbekannter Nutzer',
    };

    await upsertUserProfile(client, uid, { displayName: authorProfile.displayName });
    const payload = buildMessagePayload(convId, authorProfile, text, tsMs, messageId);
    const message = await appendMessage(client, meta, payload);

    await registerConversationForUsers(client, convId, meta.participants, payload.timestampMs);

    logRedisUsage('[chat/v1/messages] write', counters, { convId });

    return ok(res, { ok: true, message });
  } catch (err) {
    console.error('[chat/v1/messages] error', err);
    return bad(res, 'server error', 500);
  }
}
