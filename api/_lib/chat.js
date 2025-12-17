// api/_lib/chat.js
import { redis } from './redis.js';
import { v4 as uuid } from 'uuid';

const CONTEXT_PREFIXES = {
  complaint: 'complaint',
  capa: 'capa',
  audit: 'audit',
  doc: 'doc',
  general: 'general',
  dm: 'dm',
};

const FLAG_WHITELIST = new Set(['todo']);

const MAX_BODY_LENGTH = 2000;
const CONTEXT_TYPES = new Set(Object.values(CONTEXT_PREFIXES));

export function normalizeUserId(raw) {
  const value = String(raw || '').trim();
  if (!value) return null;
  const lowered = value.toLowerCase();
  if (!lowered.includes('@')) return lowered;
  return Buffer.from(lowered, 'utf8').toString('base64url').replace(/=+$/, '');
}

export function userIdAliases(raw) {
  const aliases = new Set();
  const normalized = normalizeUserId(raw);
  if (normalized) aliases.add(normalized);
  const email = String(raw || '').trim().toLowerCase();
  if (email && email.includes('@')) aliases.add(email);
  return Array.from(aliases.values());
}

export function parseContextId(raw) {
  const value = String(raw || '').trim();
  if (!value.includes(':')) return null;
  const [prefix, ...rest] = value.split(':');
  const normalizedPrefix = CONTEXT_PREFIXES[prefix];
  const reference = rest.join(':').trim();
  if (!normalizedPrefix || !reference) return null;

  if (normalizedPrefix === 'dm') {
    const rawParts = rest
      .join(':')
      .split(':')
      .map((p) => String(p || '').trim().toLowerCase())
      .filter(Boolean);
    if (rawParts.length !== 2) return null;
    const normalizedParts = rawParts.map((p) => normalizeUserId(p)).filter(Boolean);
    if (normalizedParts.length !== 2) return null;
    const [a, b] = normalizedParts.sort();
    const [rawA, rawB] = rawParts.sort();
    const canonicalId = `dm:${a}:${b}`;
    const legacyId = `dm:${rawA}:${rawB}`;
    const isLegacy = legacyId.includes('@') || legacyId !== canonicalId;
    const contextId = canonicalId;
    return {
      contextId,
      canonicalId,
      legacyId: isLegacy ? legacyId : null,
      type: 'dm',
      reference: `${a}:${b}`,
      participants: [a, b],
    };
  }

  return {
    contextId: `${normalizedPrefix}:${reference}`,
    type: normalizedPrefix,
    reference,
  };
}

export function buildDmContext(userA, userB) {
  const a = normalizeUserId(userA);
  const b = normalizeUserId(userB);
  if (!a || !b) return null;
  const [first, second] = [a, b].sort();
  return parseContextId(`dm:${first}:${second}`);
}

export async function migrateLegacyContext(context) {
  if (!context?.legacyId || context.legacyId === context.contextId) return context;

  const legacyMessagesKey = keyMessages(context.legacyId);
  const canonicalMessagesKey = keyMessages(context.contextId);
  const legacyMetaKey = keyMeta(context.legacyId);
  const canonicalMetaKey = keyMeta(context.contextId);

  const legacyMessages = await redis.lrange(legacyMessagesKey, 0, -1);
  if (legacyMessages && legacyMessages.length > 0) {
    await redis.rpush(canonicalMessagesKey, ...legacyMessages);
    await redis.del(legacyMessagesKey);
  }

  const legacyMeta = await redis.hgetall(legacyMetaKey);
  if (legacyMeta && Object.keys(legacyMeta).length > 0) {
    await redis.hset(canonicalMetaKey, { ...legacyMeta, contextId: context.contextId });
    await redis.del(legacyMetaKey);
  }

  const contextSetKeys = await redis.keys('chat:user:*:contexts*');
  if (Array.isArray(contextSetKeys) && contextSetKeys.length) {
    for (const key of contextSetKeys) {
      const present = await redis.sismember(key, context.legacyId);
      if (present) {
        await redis.sadd(key, context.contextId);
        await redis.srem(key, context.legacyId);
      }
    }
  }

  const readKeys = await redis.keys('chat:user:*:reads');
  if (Array.isArray(readKeys) && readKeys.length) {
    for (const key of readKeys) {
      const ts = await redis.hget(key, context.legacyId);
      if (ts) {
        await redis.hset(key, { [context.contextId]: ts });
        await redis.hdel(key, context.legacyId);
      }
    }
  }

  const deletedMarkers = await redis.keys(`chat:user:*:deleted:${context.legacyId}`);
  if (Array.isArray(deletedMarkers) && deletedMarkers.length) {
    for (const key of deletedMarkers) {
      const userId = key.split(':')[2];
      const ts = await redis.get(key);
      if (userId && ts) {
        await redis.set(keyUserDeletedContext(userId, context.contextId), ts);
      }
    }
    await redis.del(...deletedMarkers);
  }

  return context;
}

export function sanitizeBody(body) {
  const text = String(body || '').trim();
  if (!text) return null;
  if (text.length > MAX_BODY_LENGTH) return text.slice(0, MAX_BODY_LENGTH);
  return text;
}

export function sanitizeMentions(input) {
  const arr = Array.isArray(input) ? input : [];
  const sanitized = arr
    .map((m) => String(m || '').trim())
    .filter((m) => m.length > 1)
    .filter((m) => {
      if (m.includes('@')) return m.toLowerCase().endsWith('@dfs-diamon.de');
      return /^[a-z0-9_.-]+$/i.test(m);
    });
  return Array.from(new Set(sanitized));
}

export function sanitizeFlags(input) {
  const arr = Array.isArray(input) ? input : [];
  return Array.from(new Set(arr.map((f) => String(f || '').trim().toLowerCase()).filter((f) => FLAG_WHITELIST.has(f))));
}

function keyMessages(contextId) {
  return `chat:${contextId}:messages`;
}

function keyMeta(contextId) {
  return `chat:${contextId}:meta`;
}

function keyUserContexts(userId) {
  return `chat:user:${userId}:contexts`;
}

function keyUserContextsAll(userId) {
  return `chat:user:${userId}:contexts:all`;
}

function keyUserContextsByType(userId, type) {
  return `chat:user:${userId}:contexts:${type}`;
}

function keyUserDeletedContext(userId, contextId) {
  return `chat:user:${userId}:deleted:${contextId}`;
}

function keyUserReads(userId) {
  return `chat:user:${userId}:reads`;
}

function keyRate(userId) {
  return `chat:rate:${userId}`;
}

function resolveContextType(contextId, explicitType) {
  const type = (explicitType || '').toString().trim();
  if (type && CONTEXT_TYPES.has(type)) return type;
  const prefix = String(contextId || '').split(':')[0];
  return CONTEXT_TYPES.has(prefix) ? prefix : null;
}

function userContextSets(userId, contextType) {
  const keys = [keyUserContexts(userId), keyUserContextsAll(userId)];
  if (contextType) keys.push(keyUserContextsByType(userId, contextType));
  return keys;
}

export async function checkRateLimit(userId) {
  const key = keyRate(userId);
  const count = await redis.incr(key);
  if (count === 1) {
    await redis.expire(key, 10);
  }
  return count <= 10;
}

export async function recordMessage(context, author, { body, mentions = [], flags = [] }) {
  const timestamp = new Date().toISOString();
  const message = {
    id: uuid(),
    contextId: context.contextId,
    authorId: author.id,
    authorName: author.name,
    timestamp,
    type: 'user',
    body,
    mentions,
    flags,
  };

  const payload = JSON.stringify(message);
  const messagesKey = keyMessages(context.contextId);
  await redis.rpush(messagesKey, payload);

  await redis.hset(keyMeta(context.contextId), {
    contextId: context.contextId,
    type: context.type,
    reference: context.reference,
    updatedAt: timestamp,
    lastMessage: body.slice(0, 240),
    lastAuthor: author.name,
  });

  return message;
}

export async function readMessages(contextId, { limit = 50, before } = {}) {
  const messagesKey = keyMessages(contextId);
  const raw = await redis.lrange(messagesKey, 0, -1);
  const parsed = raw
    .map((r) => {
      try {
        const obj = JSON.parse(r);
        return obj?.id ? obj : null;
      } catch {
        return null;
      }
    })
    .filter(Boolean);

  const cutoff = before ? new Date(before).getTime() : null;
  const filtered = cutoff ? parsed.filter((m) => new Date(m.timestamp).getTime() < cutoff) : parsed;
  const slice = filtered.length > limit ? filtered.slice(filtered.length - limit) : filtered;
  return {
    items: slice,
    hasMore: filtered.length > slice.length,
  };
}

export async function getContextMeta(contextId) {
  const meta = await redis.hgetall(keyMeta(contextId));
  if (!meta || Object.keys(meta).length === 0) return null;
  return meta;
}

export async function touchContextForUser(userId, contextId, contextType) {
  const type = resolveContextType(contextId, contextType);
  const deletedKey = keyUserDeletedContext(userId, contextId);
  const wasDeleted = await redis.get(deletedKey);
  if (wasDeleted) return;
  const keys = userContextSets(userId, type);
  await Promise.all(keys.map((key) => redis.sadd(key, contextId)));
}

export async function touchContextsForUsers(userIds, contextId, contextType) {
  const unique = Array.from(new Set(userIds.filter(Boolean)));
  await Promise.all(unique.map((id) => touchContextForUser(id, contextId, contextType)));
}

export async function deleteContextForUser(userId, contextId, contextType) {
  const type = resolveContextType(contextId, contextType);
  const keys = userContextSets(userId, type);
  await Promise.all(keys.map((key) => redis.srem(key, contextId)));
  await redis.set(keyUserDeletedContext(userId, contextId), new Date().toISOString());
}

export async function hardDeleteContext(contextId) {
  const messagesKey = keyMessages(contextId);
  const metaKey = keyMeta(contextId);
  await redis.del(messagesKey, metaKey);

  const contextSets = await redis.keys('chat:user:*:contexts*');
  if (Array.isArray(contextSets) && contextSets.length) {
    await Promise.all(contextSets.map((key) => redis.srem(key, contextId)));
  }

  const readKeys = await redis.keys('chat:user:*:reads');
  if (Array.isArray(readKeys) && readKeys.length) {
    await Promise.all(readKeys.map((key) => redis.hdel(key, contextId)));
  }

  const deletedMarkers = await redis.keys(`chat:user:*:deleted:${contextId}`);
  if (Array.isArray(deletedMarkers) && deletedMarkers.length) {
    await redis.del(...deletedMarkers);
  }
}

export async function listContextsForUser(userId) {
  return await redis.smembers(keyUserContexts(userId));
}

export async function getLastReads(userId) {
  return await redis.hgetall(keyUserReads(userId));
}

export async function setLastRead(userId, contextId, timestamp) {
  await redis.hset(keyUserReads(userId), { [contextId]: timestamp });
}

export function resolveAuthor(actor) {
  const id = actor?.email || actor?.id || 'unknown';
  const name = actor?.displayName || actor?.name || actor?.id || 'Unbekannt';
  return { id, name };
}
