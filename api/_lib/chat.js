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

const CHAT_PREFIX = 'dfs:chat:v2';

const keyMessages = (contextId) => `${CHAT_PREFIX}:ctx:${contextId}:msgs`;
const keyMetaHash = () => `${CHAT_PREFIX}:meta`;
const keyUserContexts = (userId) => `${CHAT_PREFIX}:user:${userId}:contexts`;
const keyUserContextActivity = (userId) => `${CHAT_PREFIX}:user:${userId}:activity`;
const keyUserReads = (userId) => `${CHAT_PREFIX}:user:${userId}:reads`;
const keyRate = (userId) => `${CHAT_PREFIX}:rate:${userId}`;

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
    const parts = rest
      .join(':')
      .split(':')
      .map((p) => String(p || '').trim())
      .filter(Boolean);
    if (parts.length !== 2) return null;
    const normalizedParts = parts.map((p) => normalizeUserId(p)).filter(Boolean);
    if (normalizedParts.length !== 2) return null;
    const [a, b] = normalizedParts.sort();
    return {
      contextId: `dm:${a}:${b}`,
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
  return context;
}

export function sanitizeBody(body) {
  const text = String(body || '')
    .replace(/\r\n/g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .replace(/[ \t]{2,}/g, ' ')
    .trim();
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

function resolveContextType(contextId, explicitType) {
  const type = (explicitType || '').toString().trim();
  if (type && CONTEXT_TYPES.has(type)) return type;
  const prefix = String(contextId || '').split(':')[0];
  return CONTEXT_TYPES.has(prefix) ? prefix : null;
}

function parseMeta(rawValue) {
  if (!rawValue) return null;
  try {
    const parsed = typeof rawValue === 'string' ? JSON.parse(rawValue) : rawValue;
    return parsed && typeof parsed === 'object' ? parsed : null;
  } catch {
    return null;
  }
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

  const meta = {
    contextId: context.contextId,
    type: context.type,
    reference: context.reference,
    updatedAt: timestamp,
    lastMessage: body.slice(0, 240),
    lastAuthor: author.name,
    participants: Array.isArray(context.participants) ? context.participants : undefined,
  };

  const pipeline = redis.pipeline();
  pipeline.rpush(keyMessages(context.contextId), JSON.stringify(message));
  pipeline.hset(keyMetaHash(), { [context.contextId]: JSON.stringify(meta) });
  await pipeline.exec();

  return message;
}

export async function readMessages(contextId, { limit = 50, before } = {}) {
  const raw = await redis.lrange(keyMessages(contextId), 0, -1);
  const parsed = (raw || [])
    .map((r) => {
      try {
        const obj = JSON.parse(r);
        return obj?.id ? obj : null;
      } catch {
        return null;
      }
    })
    .filter(Boolean)
    .sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime());

  const cutoff = before ? new Date(before).getTime() : null;
  const filtered = cutoff ? parsed.filter((m) => new Date(m.timestamp).getTime() < cutoff) : parsed;
  const slice = filtered.length > limit ? filtered.slice(filtered.length - limit) : filtered;
  return {
    items: slice,
    hasMore: filtered.length > slice.length,
  };
}

export async function getContextMeta(contextId) {
  const raw = await redis.hget(keyMetaHash(), contextId);
  return parseMeta(raw);
}

export async function touchContextForUser(userId, contextId, contextType, updatedAt = null) {
  const uid = normalizeUserId(userId);
  if (!uid || !contextId) return;
  const type = resolveContextType(contextId, contextType);
  if (!type) return;
  const timestamp = updatedAt || new Date().toISOString();
  const pipeline = redis.pipeline();
  pipeline.sadd(keyUserContexts(uid), contextId);
  pipeline.hset(keyUserContextActivity(uid), { [contextId]: timestamp });
  await pipeline.exec();
}

export async function touchContextsForUsers(userIds, contextId, contextType, updatedAt = null) {
  const unique = Array.from(new Set((userIds || []).map((id) => normalizeUserId(id)).filter(Boolean)));
  await Promise.all(unique.map((id) => touchContextForUser(id, contextId, contextType, updatedAt)));
}

export async function deleteContextForUser(userId, contextId, contextType) {
  const uid = normalizeUserId(userId);
  if (!uid || !contextId) return;
  const type = resolveContextType(contextId, contextType);
  if (!type) return;
  const pipeline = redis.pipeline();
  pipeline.srem(keyUserContexts(uid), contextId);
  pipeline.hdel(keyUserContextActivity(uid), contextId);
  pipeline.hdel(keyUserReads(uid), contextId);
  await pipeline.exec();
}

export async function hardDeleteContext(contextId) {
  const meta = await getContextMeta(contextId);
  const participants = Array.isArray(meta?.participants) ? meta.participants : [];
  const pipeline = redis.pipeline();
  pipeline.del(keyMessages(contextId));
  pipeline.hdel(keyMetaHash(), contextId);
  for (const userId of participants) {
    const uid = normalizeUserId(userId);
    if (!uid) continue;
    pipeline.srem(keyUserContexts(uid), contextId);
    pipeline.hdel(keyUserContextActivity(uid), contextId);
    pipeline.hdel(keyUserReads(uid), contextId);
  }
  await pipeline.exec();
}

export async function listContextsForUser(userId) {
  const uid = normalizeUserId(userId);
  if (!uid) return [];
  const [ids, activityRaw] = await Promise.all([
    redis.smembers(keyUserContexts(uid)),
    redis.hgetall(keyUserContextActivity(uid)),
  ]);
  const activity = activityRaw || {};
  const items = (ids || []).map((contextId) => ({
    contextId,
    lastActivity: activity[contextId] || null,
  }));

  items.sort((a, b) => {
    const tA = a.lastActivity ? new Date(a.lastActivity).getTime() : 0;
    const tB = b.lastActivity ? new Date(b.lastActivity).getTime() : 0;
    return tB - tA;
  });

  return items;
}

export async function getLastReads(userId) {
  const uid = normalizeUserId(userId);
  if (!uid) return {};
  return (await redis.hgetall(keyUserReads(uid))) || {};
}

export async function setLastRead(userId, contextId, timestamp) {
  const uid = normalizeUserId(userId);
  if (!uid || !contextId) return;
  await redis.hset(keyUserReads(uid), { [contextId]: timestamp });
}

export function resolveAuthor(actor) {
  const id = actor?.email || actor?.id || 'unknown';
  const name = actor?.displayName || actor?.name || actor?.id || 'Unbekannt';
  return { id, name };
}

export function describeKeySchema(contextId, userId) {
  return {
    messagesKey: keyMessages(contextId),
    metaKey: keyMetaHash(),
    userContextsKey: keyUserContexts(userId),
    userContextActivityKey: keyUserContextActivity(userId),
    userReadsKey: keyUserReads(userId),
    rateLimitKey: keyRate(userId),
  };
}
