// api/chat/v1/_lib/store.js
import {
  buildMessageId,
  isConversationId,
  keyConversationMeta,
  keyConversationMessages,
  keyMessage,
  keyUser,
  keyUserConversations,
  normalizeUserId,
  parseParticipantList,
  sanitizeBody,
  toIsoTimestamp,
} from './schema.js';

function safeDisplayName(name, fallback = 'Unbekannter Nutzer') {
  const value = String(name || '').trim();
  if (!value) return fallback;
  return value;
}

export async function readUserProfile(redis, uid) {
  const profile = await redis.hgetall(keyUser(uid));
  if (!profile || Object.keys(profile).length === 0) return null;
  return {
    userId: uid,
    displayName: safeDisplayName(profile.displayName),
    avatar: profile.avatar || null,
  };
}

export async function upsertUserProfile(redis, uid, { displayName, avatar }) {
  const payload = {};
  if (displayName) payload.displayName = displayName;
  if (avatar) payload.avatar = avatar;
  if (Object.keys(payload).length === 0) return;
  await redis.hset(keyUser(uid), payload);
}

export async function fetchConversationMeta(redis, convId) {
  if (!isConversationId(convId)) return null;
  const raw = await redis.hgetall(keyConversationMeta(convId));
  if (!raw || Object.keys(raw).length === 0) return null;
  const participants = parseParticipantList(raw);
  return {
    convId,
    createdAt: raw.createdAt || null,
    updatedAt: raw.updatedAt || null,
    lastMsgId: raw.lastMsgId || null,
    lastMsgAuthor: raw.lastMsgAuthor || null,
    lastMsgPreview: raw.lastMsgPreview || null,
    participants,
  };
}

export async function ensureConversation(redis, convId, participants) {
  const existing = await fetchConversationMeta(redis, convId);
  if (existing) return existing;
  const createdAt = toIsoTimestamp();
  await redis.hset(keyConversationMeta(convId), {
    convId,
    kind: 'dm',
    createdAt,
    updatedAt: createdAt,
    participants: JSON.stringify(participants),
  });
  return {
    convId,
    createdAt,
    updatedAt: createdAt,
    lastMsgId: null,
    lastMsgAuthor: null,
    lastMsgPreview: null,
    participants,
  };
}

export async function listUserConversations(redis, uid, { limit = 200 } = {}) {
  const entries = await redis.zrevrange(keyUserConversations(uid), 0, limit - 1, { withScores: true });
  return (entries || []).map((row) => ({
    convId: row.member,
    lastActivityTs: Number(row.score) || 0,
  }));
}

export async function registerConversationForUsers(redis, convId, participants, tsMs) {
  const score = Number(tsMs || Date.now());
  for (const uid of participants) {
    await redis.zadd(keyUserConversations(uid), { score, member: convId });
  }
}

export function buildMessagePayload(convId, author, body, timestampMs, providedMessageId) {
  const msgId = providedMessageId?.startsWith(`${convId}:`) ? providedMessageId : buildMessageId(convId, timestampMs);
  const ts = Number(msgId.split(':').pop());
  return {
    msgId,
    convId,
    authorId: author.userId,
    authorDisplayName: safeDisplayName(author.displayName, 'Unbekannter Nutzer'),
    body: body || '',
    timestampMs: ts || timestampMs,
  };
}

export async function appendMessage(redis, convMeta, messagePayload) {
  const timestampIso = toIsoTimestamp(messagePayload.timestampMs);
  const msgKey = keyMessage(messagePayload.msgId);
  const exists = await redis.exists(msgKey);
  if (exists) {
    const stored = await redis.hgetall(msgKey);
    return hydrateMessage(messagePayload.msgId, stored);
  }

  await redis.hset(msgKey, {
    msgId: messagePayload.msgId,
    convId: convMeta.convId,
    authorId: messagePayload.authorId,
    authorDisplayName: messagePayload.authorDisplayName,
    body: messagePayload.body,
    timestamp: timestampIso,
  });

  await redis.zadd(keyConversationMessages(convMeta.convId), {
    score: messagePayload.timestampMs,
    member: messagePayload.msgId,
  });

  await redis.hset(keyConversationMeta(convMeta.convId), {
    updatedAt: timestampIso,
    lastMsgId: messagePayload.msgId,
    lastMsgAuthor: messagePayload.authorDisplayName,
    lastMsgPreview: messagePayload.body.slice(0, 240),
  });

  return {
    id: messagePayload.msgId,
    convId: convMeta.convId,
    authorId: messagePayload.authorId,
    authorDisplayName: messagePayload.authorDisplayName,
    body: messagePayload.body,
    timestamp: timestampIso,
  };
}

function hydrateMessage(msgId, raw) {
  if (!raw || Object.keys(raw).length === 0) return null;
  return {
    id: msgId,
    convId: raw.convId,
    authorId: raw.authorId,
    authorDisplayName: raw.authorDisplayName || raw.author || 'Unbekannter Nutzer',
    body: raw.body || '',
    timestamp: raw.timestamp,
  };
}

async function fetchMessagesByIds(redis, ids) {
  const items = [];
  for (const id of ids) {
    const raw = await redis.hgetall(keyMessage(id));
    const parsed = hydrateMessage(id, raw);
    if (parsed) items.push(parsed);
  }
  items.sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime());
  return items;
}

export async function readMessages(redis, convId, { afterTs = null, beforeTs = null, limit = 50 } = {}) {
  const key = keyConversationMessages(convId);
  const cappedLimit = Math.min(Math.max(Number(limit) || 0, 1), 200);

  if (beforeTs !== null) {
    const members = await redis.zrevrangebyscore(key, beforeTs - 1, 0, { limit: { offset: 0, count: cappedLimit } });
    const hasMore = members.length === cappedLimit;
    const messages = await fetchMessagesByIds(redis, members);
    return { messages, hasMoreBefore: hasMore, hasMoreAfter: false };
  }

  if (afterTs !== null) {
    const members = await redis.zrangebyscore(key, `(${afterTs}`, '+inf', { limit: { offset: 0, count: cappedLimit } });
    const hasMore = members.length === cappedLimit;
    const messages = await fetchMessagesByIds(redis, members);
    return { messages, hasMoreBefore: false, hasMoreAfter: hasMore };
  }

  const total = await redis.zcard(key);
  const start = total > cappedLimit ? total - cappedLimit : 0;
  const end = total > 0 ? total - 1 : 0;
  const members = total > 0 ? await redis.zrange(key, start, end) : [];
  const hasMoreBefore = total > members.length;
  const messages = await fetchMessagesByIds(redis, members);
  return { messages, hasMoreBefore, hasMoreAfter: false };
}

export function buildConversationSummary(meta, profiles) {
  const participants = meta.participants.map((uid) => ({
    userId: uid,
    displayName: profiles.get(uid) || 'Unbekannter Nutzer',
  }));
  const lastActivity = meta.updatedAt || meta.createdAt;
  return {
    convId: meta.convId,
    participants,
    lastMessage: meta.lastMsgPreview || null,
    lastAuthor: meta.lastMsgAuthor || null,
    lastMessageAt: lastActivity,
  };
}

export function requireParticipant(meta, uid) {
  return meta.participants.includes(uid);
}

export function validateMessageBody(body) {
  const sanitized = sanitizeBody(body);
  if (!sanitized) return null;
  return sanitized;
}

export function buildProfilesMap(list = []) {
  const map = new Map();
  for (const entry of list) {
    if (entry?.userId) map.set(entry.userId, safeDisplayName(entry.displayName));
  }
  return map;
}

export { normalizeUserId };
