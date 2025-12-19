// /api/chat/v1/messages/[id].js
export const config = { runtime: 'nodejs' };

import { bad, handlePreflight, methodNotAllowed, ok, readJson, setCors } from '../../../_lib/http.js';
import { getAuthUser } from '../../../_lib/auth.js';
import { redis } from '../../../_lib/redis.js';
import { createTrackedRedis, logRedisUsage } from '../_lib/redisTracker.js';
import { normalizeUserId, readMessageById, updateMessageById, validateMessageBody } from '../_lib/store.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const { id } = req.query || {};
  const messageId = String(id || '').trim();
  if (!messageId) return bad(res, 'missing message id', 400);

  if (req.method !== 'PATCH' && req.method !== 'DELETE') return methodNotAllowed(res);

  const actor = getAuthUser(req);
  if (!actor) return bad(res, 'unauthorized', 401);

  const uid = normalizeUserId(actor.email);
  if (!uid) return bad(res, 'invalid user', 400);

  const { client, counters } = createTrackedRedis(redis);

  try {
    const existing = await readMessageById(client, messageId);
    if (!existing) return bad(res, 'message not found', 404);

    if (existing.message?.authorId !== uid) {
      return bad(res, 'forbidden', 403, { error: 'not_owner' });
    }

    if (req.method === 'PATCH') {
      if (existing.message?.deletedAt) return bad(res, 'already deleted', 409, { error: 'deleted' });
      const payload = readJson(req);
      const text = validateMessageBody(payload?.body);
      if (!text) return bad(res, 'empty body', 400);
      const updated = await updateMessageById(client, messageId, {
        body: text,
        text,
        editedAt: Date.now(),
      });
      logRedisUsage('[chat/v1/message] edit', counters, { messageId });
      return ok(res, { ok: true, message: updated });
    }

    const updated = await updateMessageById(client, messageId, {
      body: '',
      text: '',
      deletedAt: Date.now(),
      deletedBy: uid,
    });
    logRedisUsage('[chat/v1/message] delete', counters, { messageId });
    return ok(res, { ok: true, message: updated });
  } catch (err) {
    console.error('[chat/v1/message] error', err);
    return bad(res, 'server error', 500);
  }
}
