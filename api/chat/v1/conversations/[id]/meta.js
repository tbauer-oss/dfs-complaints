// /api/chat/v1/conversations/[id]/meta.js
export const config = { runtime: 'nodejs' };

import { bad, handlePreflight, methodNotAllowed, ok, readJson, setCors } from '../../../../_lib/http.js';
import { getAuthUser } from '../../../../_lib/auth.js';
import { redis } from '../../../../_lib/redis.js';
import { createTrackedRedis, logRedisUsage } from '../../_lib/redisTracker.js';
import { createRedisAdapter } from '../../_lib/redisAdapter.js';
import { isValidGroupIconId, normalizeGroupIconId } from '../../_lib/groupIcons.js';
import { fetchConversationMeta, normalizeUserId, persistConversationMeta } from '../../_lib/store.js';
import { canonicalizeConversationId, keyConversationMembers } from '../../_lib/schema.js';

function buildMetaResponse(meta) {
  return {
    createdAt: meta?.createdAt ?? null,
    updatedAt: meta?.updatedAt ?? null,
    lastMsgAt: meta?.lastMsgAt ?? null,
    groupIcon: normalizeGroupIconId(meta?.groupIcon),
  };
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  if (req.method !== 'PATCH' && req.method !== 'PUT') return methodNotAllowed(res);

  const actor = getAuthUser(req);
  if (!actor) return bad(res, 'unauthorized', 401);

  const { id } = req.query || {};
  const requestedConvId = String(id || '').trim();
  const canonicalConvId = canonicalizeConversationId(requestedConvId) || requestedConvId;

  if (!requestedConvId) return bad(res, 'missing conversation id', 400);
  if (!canonicalConvId.startsWith('grp:')) return bad(res, 'group_only', 400);

  const { client, counters } = createTrackedRedis(redis);
  const rdb = createRedisAdapter(client);

  try {
    const uid = normalizeUserId(actor.email);
    if (!uid) return bad(res, 'invalid user', 400);

    const meta =
      (canonicalConvId && (await fetchConversationMeta(rdb, canonicalConvId))) ||
      (canonicalConvId !== requestedConvId ? await fetchConversationMeta(rdb, requestedConvId) : null);
    if (!meta) return bad(res, 'conversation not found', 404);

    const convId = canonicalizeConversationId(meta.convId) || canonicalConvId || requestedConvId;
    if (!convId.startsWith('grp:')) return bad(res, 'group_only', 400);

    const membersKey = keyConversationMembers(convId);
    const members = await rdb.smembers(membersKey);
    const normalizedMembers = Array.isArray(members?.[0]) ? members[0] : members;
    const isMember = normalizedMembers.includes(uid);
    if (!isMember) return bad(res, 'not_a_member', 403, { error: 'not_a_member' });

    const body = readJson(req);
    if (!Object.prototype.hasOwnProperty.call(body || {}, 'groupIcon')) {
      return bad(res, 'missing groupIcon', 400);
    }

    const rawGroupIcon = body?.groupIcon;
    const groupIcon = rawGroupIcon === '' ? null : rawGroupIcon;
    if (!isValidGroupIconId(groupIcon)) return bad(res, 'invalid groupIcon', 400);

    await persistConversationMeta(rdb, convId, { groupIcon: normalizeGroupIconId(groupIcon) });
    const updated = await fetchConversationMeta(rdb, convId);

    logRedisUsage('[chat/v1/conversations/meta] write', counters, { convId });
    return ok(res, { ok: true, convId, meta: buildMetaResponse(updated) });
  } catch (err) {
    console.error('[chat/v1/conversations/meta] error', err);
    return bad(res, 'server error', 500);
  }
}
