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
  ensureDmConversation,
  fetchConversationMeta,
  buildProfilesMap,
  normalizeUserId,
  readUserProfile,
  readMessages,
  registerConversationForUsers,
  upsertUserProfile,
  validateMessageBody,
} from '../../_lib/store.js';
import {
  buildMessageId,
  canonicalizeConversationId,
  keyConversationMembers,
  keyConversationMessages,
  parseTimestamp,
} from '../../_lib/schema.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const { id } = req.query || {};
  const requestedConvId = String(id || '').trim();
  const canonicalConvId = canonicalizeConversationId(requestedConvId) || requestedConvId;

  if (!requestedConvId) return bad(res, 'missing conversation id', 400);

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

    let meta =
      (canonicalConvId && (await fetchConversationMeta(rdb, canonicalConvId))) ||
      (canonicalConvId !== requestedConvId ? await fetchConversationMeta(rdb, requestedConvId) : null);

    if (!meta && canonicalConvId?.startsWith('dm:')) {
      const [, rawA, rawB] = canonicalConvId.split(':');
      const userA = normalizeUserId(rawA);
      const userB = normalizeUserId(rawB);
      const isParticipant = [userA, userB].includes(uid);
      if (userA && userB && isParticipant) {
        meta = await ensureDmConversation(rdb, userA, userB);
      }
      if (!meta && !isParticipant) return bad(res, 'not_a_member', 403, { error: 'not_a_member' });
    }

    if (!meta) return bad(res, 'conversation not found', 404);

    const convId = canonicalizeConversationId(meta.convId) || canonicalConvId || requestedConvId;

    const membersKey = keyConversationMembers(convId);
    const members = await rdb.smembers(membersKey);

    const isGroupConversation = convId?.startsWith('grp:');
    const normalizedMembers =
      (isGroupConversation && Array.isArray(members?.[0]) ? members[0] : members) || [];
    const dmParticipants =
      !isGroupConversation
        ? Array.isArray(meta?.participants) && meta.participants.length > 0
          ? meta.participants
          : convId?.startsWith('dm:')
            ? convId
              .split(':')
              .slice(1)
              .map((entry) => normalizeUserId(entry))
              .filter(Boolean)
            : []
        : [];
    const isMember = isGroupConversation
      ? normalizedMembers.includes(uid)
      : dmParticipants.length > 0
        ? dmParticipants.includes(uid)
        : Boolean(await rdb.sismember(membersKey, uid));

    if (!isMember) {
      console.warn('[chat/v1/messages] membership_denied', {
        email: actor.email,
        uid,
        convId,
        membersKey,
        members: normalizedMembers,
      });
      return bad(res, 'not_a_member', 403, { error: 'not_a_member' });
    }

    if (req.method === 'GET') {
      const afterTs = parseTimestamp(req.query?.afterTs);
      const beforeTs = parseTimestamp(req.query?.beforeTs);
      const limit = Number(req.query?.limit || 50);
      const timeline = await readMessages(rdb, convId, { afterTs, beforeTs, limit });
      const deletedByIds = new Set(
        (timeline.messages || [])
          .map((msg) => msg.deletedBy)
          .filter((value) => value && String(value).trim().length > 0)
      );
      const deletedProfiles = buildProfilesMap(
        (
          await Promise.all(
            Array.from(deletedByIds.values()).map(async (uid) => readUserProfile(client, uid))
          )
        ).filter(Boolean)
      );
      const timelineMessages = (timeline.messages || []).map((msg) => {
        if (!msg.isDeleted) return msg;
        const deletedBy = msg.deletedBy;
        const deletedProfile = deletedBy ? deletedProfiles.get(deletedBy) : null;
        const fallbackName = msg.senderName || msg.authorDisplayName || msg.senderEmail || 'Unbekannter Nutzer';
        const displayName = deletedProfile?.displayName || fallbackName;
        const tombstone = `Nachricht wurde von ${displayName} gelöscht!`;
        return {
          ...msg,
          body: tombstone,
          text: tombstone,
          isDeleted: true,
        };
      });
      const messagesKey = timeline.sourceKey || keyConversationMessages(convId);
      const zsetLength =
        typeof timeline.total === 'number' && !Number.isNaN(timeline.total)
          ? timeline.total
          : await rdb.zcard(messagesKey);
      console.info('[chat/v1/messages] read', {
        requestedConvId,
        canonicalConvId,
        convId,
        messagesKey,
        zsetLength,
        resultCount: timelineMessages.length || 0,
      });
      logRedisUsage('[chat/v1/messages] read-only', counters, { convId });
      return ok(res, { ok: true, convId, ...timeline, messages: timelineMessages });
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

    const messagesKey = keyConversationMessages(convId);
    const zsetLength = await rdb.zcard(messagesKey);
    console.info('[chat/v1/messages] write', {
      requestedConvId,
      canonicalConvId,
      convId,
      messagesKey,
      zsetLength,
      resultCount: 1,
    });

    logRedisUsage('[chat/v1/messages] write', counters, { convId });

    return ok(res, { ok: true, message });
  } catch (err) {
    console.error('[chat/v1/messages] error', err);
    return bad(res, 'server error', 500);
  }
}
