// /api/admin/chat/[contextId].js
export const config = { runtime: 'nodejs' };

import { bad, handlePreflight, methodNotAllowed, ok, readJson, setCors } from '../../_lib/http.js';
import { requirePortalAccess } from '../_guard.js';
import {
  checkRateLimit,
  getContextMeta,
  parseContextId,
  readMessages,
  resolveAuthor,
  sanitizeBody,
  sanitizeFlags,
  sanitizeMentions,
  setLastRead,
  touchContextsForUsers,
  recordMessage,
  deleteContextForUser,
  hardDeleteContext,
  userIdAliases,
} from '../../_lib/chat.js';
import { normalizeRole, PORTAL_ROLES } from '../../_lib/portalAuth.js';

const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 200;

function parseLimit(raw) {
  const n = Number(raw ?? DEFAULT_LIMIT);
  if (Number.isNaN(n) || n <= 0) return DEFAULT_LIMIT;
  return Math.min(Math.round(n), MAX_LIMIT);
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const wantsWrite = req.method === 'POST' || req.method === 'DELETE';
  const actor = await requirePortalAccess(req, res, { write: wantsWrite });
  if (!actor) return;

  const context = parseContextId(req.query?.contextId);
  if (!context) return bad(res, 'invalid context', 400);

  try {
    if (req.method === 'GET') {
      const limit = parseLimit(req.query?.limit);
      const before = req.query?.before;
      const { items, hasMore } = await readMessages(context.contextId, { limit, before });
      const nowIso = new Date().toISOString();
      const actorIds = userIdAliases(actor.email);
      await touchContextsForUsers(actorIds, context.contextId, context.type);
      await Promise.all(actorIds.map((id) => setLastRead(id, context.contextId, nowIso)));
      return ok(res, { ok: true, messages: items, hasMore, lastRead: nowIso });
    }

    if (req.method === 'POST') {
      if (!await checkRateLimit(actor.email)) {
        return bad(res, 'rate limit', 429);
      }

      const body = readJson(req) || {};
      const text = sanitizeBody(body.body);
      if (!text) return bad(res, 'message required', 400);

      const mentions = sanitizeMentions(body.mentions);
      const flags = sanitizeFlags(body.flags);

      const author = resolveAuthor(actor);
      const saved = await recordMessage(context, author, { body: text, mentions, flags });

      const participants = context.participants || [];
      const actorIds = userIdAliases(actor.email);
      const participantIds = participants.flatMap((p) => userIdAliases(p));
      const mentionIds = mentions.flatMap((m) => userIdAliases(m));
      const allIds = Array.from(new Set([...actorIds, ...participantIds, ...mentionIds]));
      await touchContextsForUsers(allIds, context.contextId, context.type);

      const meta = await getContextMeta(context.contextId);
      return ok(res, { ok: true, message: saved, meta });
    }

    if (req.method === 'DELETE') {
      const hardMode = String(req.query?.mode || '').toLowerCase() === 'hard';
      if (hardMode && normalizeRole(actor.role) !== PORTAL_ROLES.superuser) {
        return bad(res, 'forbidden', 403);
      }

      if (hardMode) {
        await hardDeleteContext(context.contextId);
      } else {
        const actorIds = userIdAliases(actor.email);
        await Promise.all(actorIds.map((id) => deleteContextForUser(id, context.contextId, context.type)));
      }

      return ok(res, { ok: true, mode: hardMode ? 'hard' : 'soft' });
    }

    return methodNotAllowed(res);
  } catch (err) {
    console.error('[admin/chat/:contextId] error', err);
    return bad(res, 'server error', 500);
  }
}
