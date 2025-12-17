// api/_lib/chat.js
import { redis } from './redis.js';
import { v4 as uuid } from 'uuid';

const CONTEXT_PREFIXES = {
  complaint: 'complaint',
  capa: 'capa',
  audit: 'audit',
  doc: 'doc',
  general: 'general',
};

const FLAG_WHITELIST = new Set(['todo']);

const LIST_FETCH_WINDOW = 500;
const MAX_BODY_LENGTH = 2000;

export function parseContextId(raw) {
  const value = String(raw || '').trim();
  if (!value.includes(':')) return null;
  const [prefix, ...rest] = value.split(':');
  const normalizedPrefix = CONTEXT_PREFIXES[prefix];
  const reference = rest.join(':').trim();
  if (!normalizedPrefix || !reference) return null;
  return {
    contextId: `${normalizedPrefix}:${reference}`,
    type: normalizedPrefix,
    reference,
  };
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

function keyUserReads(userId) {
  return `chat:user:${userId}:reads`;
}

function keyRate(userId) {
  return `chat:rate:${userId}`;
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
  const raw = await redis.lrange(messagesKey, -LIST_FETCH_WINDOW, -1);
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

export async function touchContextForUser(userId, contextId) {
  await redis.sadd(keyUserContexts(userId), contextId);
}

export async function touchContextsForUsers(userIds, contextId) {
  const unique = Array.from(new Set(userIds.filter(Boolean)));
  await Promise.all(unique.map((id) => touchContextForUser(id, contextId)));
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
  const name = actor?.displayName || actor?.name || actor?.email || id;
  return { id, name };
}
