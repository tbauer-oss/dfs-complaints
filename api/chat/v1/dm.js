// /api/chat/v1/dm.js
export const config = { runtime: 'nodejs' };

import { bad, handlePreflight, methodNotAllowed, ok, readJson, setCors } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { redis } from '../../_lib/redis.js';
import { createTrackedRedis, logRedisUsage } from './_lib/redisTracker.js';
import { purgeLegacyChatKeys } from './_lib/cleanup.js';
import {
  buildConversationSummary,
  buildProfilesMap,
  ensureDmConversation,
  normalizeUserId,
  readUserProfile,
  registerConversationForUsers,
  upsertUserProfile,
} from './_lib/store.js';
import { buildConversationId, toIsoTimestamp } from './_lib/schema.js';

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
    if (!selfId || !peerId) return bad(res, 'invalid participants', 400);
    if (selfId === peerId) return bad(res, 'cannot chat with self', 400);

    await purgeLegacyChatKeys(client);

    const convId = buildConversationId(selfId, peerId);
    const participants = [selfId, peerId];
    const convMeta = await ensureDmConversation(client, selfId, peerId);

    const actorDisplayName = actor.displayName || actor.name || actor.id || 'Unbekannter Nutzer';
    const peerProfile = await readUserProfile(client, peerId);
    const peerDisplayName = peerProfile?.displayName || 'Unbekannter Nutzer';

    await upsertUserProfile(client, selfId, { displayName: actorDisplayName });
    await upsertUserProfile(client, peerId, { displayName: peerDisplayName });

    const tsMs = Date.now();
    await registerConversationForUsers(client, convId, participants, tsMs);

    const profiles = buildProfilesMap([
      { userId: selfId, displayName: actorDisplayName },
      { userId: peerId, displayName: peerDisplayName },
    ]);
    const summary = buildConversationSummary(
      { ...convMeta, updatedAt: convMeta.updatedAt || toIsoTimestamp(tsMs), lastMsgAt: convMeta.lastMsgAt || toIsoTimestamp(tsMs) },
      profiles,
      selfId
    );

    logRedisUsage('[chat/v1/dm] created', counters, { conversation: convId });

    return ok(res, { ok: true, conversation: summary });
  } catch (err) {
    console.error('[chat/v1/dm] error', err);
    return bad(res, 'server error', 500);
  }
}
