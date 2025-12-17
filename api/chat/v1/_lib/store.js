// api/chat/v1/_lib/store.js
import { randomUUID } from 'crypto';
import {
  buildConversationId,
  buildGroupId,
  buildMessageId,
  isConversationId,
  keyConversationMembers,
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
    email: profile.email || null,
    avatar: profile.avatarUrl || profile.avatar || null,
    active: profile.active !== undefined ? String(profile.active) === 'true' : true,
  };
}

export async function upsertUserProfile(redis, uid, { displayName, avatarUrl }) {
  const payload = {};
  if (displayName) payload.displayName = displayName;
  if (avatarUrl) payload.avatarUrl = avatarUrl;
  if (Object.keys(payload).length === 0) return;
  await redis.hset(keyUser(uid), payload);
}

async function readConversationParticipants(redis, convId, rawMeta) {
  const setKey = keyConversationMembers(convId);
  const hasSet = await redis.exists(setKey);
  if (hasSet) {
    const members = await redis.smembers(setKey);
    if (Array.isArray(members) && members.length > 0) return members;
  }
  const parsed = parseParticipantList(rawMeta);
  const fallbacks = [];
  if (rawMeta?.p1) fallbacks.push(rawMeta.p1);
  if (rawMeta?.p2) fallbacks.push(rawMeta.p2);
  const combined = [...new Set([...(Array.isArray(parsed) ? parsed : []), ...fallbacks])];
  return combined.filter(Boolean);
}

export async function fetchConversationMeta(redis, convId) {
  if (!isConversationId(convId)) return null;
  const raw = await redis.hgetall(keyConversationMeta(convId));
  if (!raw || Object.keys(raw).length === 0) return null;
  const participants = await readConversationParticipants(redis, convId, raw);
  return {
    convId,
    type: raw.type || raw.kind || 'dm',
    createdAt: raw.createdAt || null,
    updatedAt: raw.updatedAt || null,
    lastMsgAt: raw.lastMsgAt || raw.updatedAt || null,
    lastMsgId: raw.lastMsgId || null,
    lastMsgAuthor: raw.lastMsgAuthor || null,
    lastMsgPreview: raw.lastMsgPreview || null,
    title: raw.title || null,
    createdBy: raw.createdBy || null,
    participants,
    p1: raw.p1 || null,
    p2: raw.p2 || null,
  };
}

async function ensureMembersSet(redis, convId, participants) {
  if (!participants?.length) return;
  const setKey = keyConversationMembers(convId);
  await redis.sadd(setKey, participants);
}

export async function ensureDmConversation(redis, uidA, uidB) {
  const convId = buildConversationId(uidA, uidB);
  if (!convId) return null;
  const existing = await fetchConversationMeta(redis, convId);
  if (existing) return existing;
  const createdAt = toIsoTimestamp();
  const participants = [uidA, uidB];
  await redis.hset(keyConversationMeta(convId), {
    convId,
    type: 'dm',
    createdAt,
    updatedAt: createdAt,
    lastMsgAt: createdAt,
    participants: JSON.stringify(participants),
  });
  await ensureMembersSet(redis, convId, participants);
  return {
    convId,
    type: 'dm',
    createdAt,
    updatedAt: createdAt,
    lastMsgAt: createdAt,
    lastMsgId: null,
    lastMsgAuthor: null,
    lastMsgPreview: null,
    title: null,
    createdBy: null,
    participants,
  };
}

export async function createGroupConversation(redis, title, members, createdBy) {
  const filtered = Array.from(new Set((members || []).map((m) => normalizeUserId(m)).filter(Boolean)));
  if (filtered.length === 0) return null;
  const convId = buildGroupId(randomUUID());
  const createdAt = toIsoTimestamp();
  await redis.hset(keyConversationMeta(convId), {
    convId,
    type: 'group',
    title: safeDisplayName(title, 'Gruppe'),
    createdBy: createdBy || null,
    createdAt,
    updatedAt: createdAt,
    lastMsgAt: createdAt,
    participants: JSON.stringify(filtered),
  });
  await ensureMembersSet(redis, convId, filtered);
  return {
    convId,
    type: 'group',
    createdAt,
    updatedAt: createdAt,
    lastMsgAt: createdAt,
    lastMsgId: null,
    lastMsgAuthor: null,
    lastMsgPreview: null,
    title: safeDisplayName(title, 'Gruppe'),
    createdBy: createdBy || null,
    participants: filtered,
  };
}

export async function listUserConversations(redis, uid, { limit = 200 } = {}) {
  const entries = await redis.zrange(keyUserConversations(uid), 0, limit - 1, { withScores: true, rev: true });
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
    senderUid: author.userId,
    senderName: safeDisplayName(author.displayName, 'Unbekannter Nutzer'),
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
    senderUid: messagePayload.senderUid,
    senderName: messagePayload.senderName,
    text: messagePayload.body,
    ts: timestampIso,
  });

  await redis.zadd(keyConversationMessages(convMeta.convId), {
    score: messagePayload.timestampMs,
    member: messagePayload.msgId,
  });

  await redis.hset(keyConversationMeta(convMeta.convId), {
    updatedAt: timestampIso,
    lastMsgAt: timestampIso,
    lastMsgId: messagePayload.msgId,
    lastMsgAuthor: messagePayload.senderName,
    lastMsgPreview: messagePayload.body.slice(0, 240),
  });

  return {
    id: messagePayload.msgId,
    convId: convMeta.convId,
    authorId: messagePayload.senderUid,
    authorDisplayName: messagePayload.senderName,
    body: messagePayload.body,
    timestamp: timestampIso,
  };
}

function hydrateMessage(msgId, raw) {
  if (!raw || Object.keys(raw).length === 0) return null;
  return {
    id: msgId,
    convId: raw.convId,
    authorId: raw.senderUid || raw.authorId,
    authorDisplayName: raw.senderName || raw.author || 'Unbekannter Nutzer',
    body: raw.text || raw.body || '',
    timestamp: raw.ts || raw.timestamp,
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
    const members = await redis.zrangebyscore(key, beforeTs - 1, 0, {
      limit: { offset: 0, count: cappedLimit },
      rev: true,
    });
    const hasMore = members.length === cappedLimit;
    const messages = await fetchMessagesByIds(redis, members);
    return { messages, hasMoreBefore: hasMore, hasMoreAfter: false };
  }

  if (afterTs !== null) {
    const members = await redis.zrangebyscore(key, `(${afterTs}`, '+inf', {
      limit: { offset: 0, count: cappedLimit },
    });
    const hasMore = members.length === cappedLimit;
    const messages = await fetchMessagesByIds(redis, members);
    return { messages, hasMoreBefore: false, hasMoreAfter: hasMore };
  }

  const members = await redis.zrevrange(key, 0, cappedLimit - 1);
  const total = await redis.zcard(key);
  const hasMoreBefore = total > members.length;
  const messages = await fetchMessagesByIds(redis, members);
  return { messages, hasMoreBefore, hasMoreAfter: false };
}

export function buildConversationSummary(meta, profiles, currentUserId) {
  const participants = meta.participants.map((uid) => ({
    userId: uid,
    displayName: profiles.get(uid)?.displayName || 'Unbekannter Nutzer',
    avatar: profiles.get(uid)?.avatar || null,
  }));
  const lastActivity = meta.lastMsgAt || meta.updatedAt || meta.createdAt;
  const title = meta.type === 'group'
    ? meta.title || 'Gruppe'
    : participants.find((p) => p.userId !== currentUserId)?.displayName || 'Direktnachricht';
  return {
    convId: meta.convId,
    type: meta.type || 'dm',
    title,
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
    if (entry?.userId) {
      map.set(entry.userId, {
        displayName: safeDisplayName(entry.displayName),
        avatar: entry.avatar || null,
      });
    }
  }
  return map;
}

export async function searchActiveUsers(redis, query, limit = 50) {
  const q = (query || '').toString().trim().toLowerCase();
  const matches = [];
  let cursor = 0;
  const maxLimit = Math.min(Math.max(limit, 1), 200);
  const matchPattern = `${keyUser('*')}`;

  do {
    const result = await redis.scan(cursor, { match: matchPattern, count: 200 });
    const nextCursor = Array.isArray(result) ? Number(result[0]) : Number(result.cursor || 0);
    const keys = Array.isArray(result) ? result[1] : result.keys || [];

    for (const key of keys) {
      const profile = await redis.hgetall(key);
      if (!profile || Object.keys(profile).length === 0) continue;
      const active = profile.active === undefined ? true : String(profile.active) === 'true';
      if (!active) continue;
      const uid = profile.uid || key.split(':').pop();
      if (!uid) continue;
      const displayName = safeDisplayName(profile.displayName, profile.email || uid);
      const email = profile.email || '';
      if (q && !displayName.toLowerCase().includes(q) && !email.toLowerCase().includes(q)) continue;
      matches.push({ userId: uid, displayName, avatar: profile.avatarUrl || profile.avatar || null });
      if (matches.length >= maxLimit) return matches;
    }

    cursor = nextCursor;
  } while (cursor !== 0 && matches.length < maxLimit);

  return matches;
}

export { normalizeUserId };
