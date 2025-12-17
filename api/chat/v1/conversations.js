// /api/chat/v1/conversations.js
export const config = { runtime: 'nodejs' };

import { bad, handlePreflight, methodNotAllowed, ok, setCors } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { createTrackedRedis, logRedisUsage } from './_lib/redisTracker.js';
import {
  buildConversationSummary,
  buildProfilesMap,
  fetchConversationMeta,
  listUserConversations,
  normalizeUserId,
  readUserProfile,
} from './_lib/store.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { write: false });
  if (!actor) return;

  if (req.method !== 'GET') return methodNotAllowed(res);

  const { client, counters } = createTrackedRedis();

  try {
    const uid = normalizeUserId(actor.email || actor.id);
    if (!uid) return bad(res, 'invalid user', 400);

    const convRefs = await listUserConversations(client, uid);
    const metaList = [];
    for (const ref of convRefs) {
      const meta = await fetchConversationMeta(client, ref.convId);
      if (meta) metaList.push(meta);
    }

    const participantIds = new Set(metaList.flatMap((m) => m.participants));
    const profileEntries = await Promise.all(
      Array.from(participantIds.values()).map(async (pid) => readUserProfile(client, pid))
    );
    const profiles = buildProfilesMap(profileEntries.filter(Boolean));

    const conversations = metaList
      .map((meta) => buildConversationSummary(meta, profiles, uid))
      .sort((a, b) => new Date(b.lastMessageAt || 0) - new Date(a.lastMessageAt || 0));

    logRedisUsage('[chat/v1/conversations] read-only', counters, { conversations: conversations.length });

    return ok(res, { ok: true, conversations });
  } catch (err) {
    console.error('[chat/v1/conversations] error', err);
    return bad(res, 'server error', 500);
  }
}
