// /api/chat/v1/groups.js
export const config = { runtime: 'nodejs' };

import { bad, handlePreflight, methodNotAllowed, ok, readJson, setCors } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { redis } from '../../_lib/redis.js';
import { createTrackedRedis, logRedisUsage } from './_lib/redisTracker.js';
import { purgeLegacyChatKeys } from './_lib/cleanup.js';
import {
  appendMessage,
  buildConversationSummary,
  buildMessagePayload,
  buildProfilesMap,
  createGroupConversation,
  normalizeUserId,
  readUserProfile,
  registerConversationForUsers,
  upsertUserProfile,
  validateMessageBody,
} from './_lib/store.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { write: true });
  if (!actor) return;

  if (req.method !== 'POST') return methodNotAllowed(res);

  const { client, counters } = createTrackedRedis(redis);

  try {
    const body = readJson(req);
    const rawMembers = Array.isArray(body?.memberUids) ? body.memberUids : [];
    const title = (body?.title || '').toString();
    const initialBody = body?.initialMessage;

    const selfId = normalizeUserId(actor.email || actor.id);
    const memberIds = Array.from(new Set([...rawMembers, selfId].map((m) => normalizeUserId(m)).filter(Boolean)));
    if (!selfId || memberIds.length < 2) return bad(res, 'invalid members', 400);

    await purgeLegacyChatKeys(client);

    const convMeta = await createGroupConversation(client, title, memberIds, selfId);
    if (!convMeta) return bad(res, 'failed to create group', 500);

    const actorDisplayName = actor.displayName || actor.name || actor.id || 'Unbekannter Nutzer';
    await upsertUserProfile(client, selfId, { displayName: actorDisplayName });

    const tsMs = Date.now();
    let metaForSummary = { ...convMeta, lastMsgAt: convMeta.lastMsgAt || convMeta.createdAt };

    if (validateMessageBody(initialBody)) {
      const payload = buildMessagePayload(convMeta.convId, { userId: selfId, displayName: actorDisplayName }, initialBody, tsMs);
      const message = await appendMessage(client, convMeta, payload);
      await registerConversationForUsers(client, convMeta.convId, convMeta.participants, payload.timestampMs);
      metaForSummary = {
        ...convMeta,
        lastMsgAt: message.timestamp,
        lastMsgAuthor: message.authorDisplayName,
        lastMsgPreview: message.body,
      };
    } else {
      await registerConversationForUsers(client, convMeta.convId, convMeta.participants, tsMs);
    }

    const profileEntries = await Promise.all(convMeta.participants.map((pid) => readUserProfile(client, pid)));
    const profiles = buildProfilesMap([
      ...profileEntries.filter(Boolean),
      { userId: selfId, displayName: actorDisplayName },
    ]);
    const summary = buildConversationSummary(metaForSummary, profiles, selfId);

    logRedisUsage('[chat/v1/groups] created', counters, { conversation: convMeta.convId });
    return ok(res, { ok: true, convId: convMeta.convId, conversation: summary });
  } catch (err) {
    console.error('[chat/v1/groups] error', err);
    return bad(res, 'server error', 500);
  }
}
