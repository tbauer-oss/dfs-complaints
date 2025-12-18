// api/chat/v1/_lib/store.js
import { randomUUID } from 'crypto';
import {
  buildConversationId,
  buildGroupId,
  buildMessageId,
  isConversationId,
  keyConversationMembers,
  keyConversationMeta,
  keyConversationMetaLegacy,
  keyConversationMetaV2,
  keyConversationMessages,
  keyConversationMessagesV2,
  keyMessage,
  keyMessageV2,
  keyUser,
  keyUserV2,
  keyUserConversations,
  keyUserInbox,
  keyUserInboxV2,
  normalizeUserId,
  metaScanPatterns,
  parseParticipantList,
  parseConversationIdFromMetaKey,
  sanitizeBody,
  toIsoTimestamp,
} from './schema.js';
import { createRedisAdapter } from './redisAdapter.js';

function safeDisplayName(name, fallback = 'Unbekannter Nutzer') {
  const value = String(name || '').trim();
  if (!value) return fallback;
  return value;
}

function toTimestampMs(value) {
  if (value === null || value === undefined || value === '') return null;
  const num = Number(value);
  if (Number.isFinite(num)) return num;
  const parsed = Date.parse(String(value));
  return Number.isFinite(parsed) ? parsed : null;
}

function toIsoOrNull(value) {
  if (!value) return null;
  const ts = typeof value === 'number' ? value : Date.parse(value);
  if (!Number.isFinite(ts)) return null;
  return new Date(ts).toISOString();
}

function normalizeParticipants(raw) {
  if (!raw) return [];
  if (Array.isArray(raw)) return Array.from(new Set(raw.map((p) => normalizeUserId(p)).filter(Boolean)));
  try {
    const parsed = typeof raw === 'string' ? JSON.parse(raw) : raw;
    if (Array.isArray(parsed)) return Array.from(new Set(parsed.map((p) => normalizeUserId(p)).filter(Boolean)));
  } catch {}
  return [];
}

function normalizeTimestamp(value) {
  const ts = toTimestampMs(value);
  return ts === null ? null : ts;
}

async function persistConversationMeta(rdb, convId, payload) {
  const participants = normalizeParticipants(payload?.participants);
  const createdAt = normalizeTimestamp(payload?.createdAt);
  const updatedAt = normalizeTimestamp(payload?.updatedAt ?? payload?.lastMsgAt ?? payload?.lastMessageAt);
  const lastMsgAt = normalizeTimestamp(
    payload?.lastMsgAt ?? payload?.lastMessageAt ?? payload?.updatedAt ?? payload?.createdAt
  );

  const existingV2 = await rdb.getJson(keyConversationMetaV2(convId), {});
  const merged = {
    ...existingV2,
    id: convId,
    type: payload?.type || payload?.kind || existingV2.type || 'dm',
    participants: participants.length > 0 ? participants : existingV2.participants || [],
    createdAt: createdAt ?? existingV2.createdAt ?? null,
    updatedAt: updatedAt ?? existingV2.updatedAt ?? createdAt ?? existingV2.createdAt ?? null,
    lastMsgAt: lastMsgAt ?? existingV2.lastMsgAt ?? updatedAt ?? createdAt ?? null,
    lastMsgPreview: payload?.lastMsgPreview ?? payload?.lastMessagePreview ?? existingV2.lastMsgPreview ?? null,
    lastMsgAuthor: payload?.lastMsgAuthor ?? existingV2.lastMsgAuthor ?? null,
    lastMsgId: payload?.lastMsgId ?? existingV2.lastMsgId ?? null,
    title: payload?.title ?? existingV2.title ?? null,
    createdBy: payload?.createdBy ?? existingV2.createdBy ?? null,
  };

  await Promise.all([
    rdb.hset(keyConversationMeta(convId), payload),
    rdb.hset(keyConversationMetaLegacy(convId), payload),
    rdb.setJson(keyConversationMetaV2(convId), merged),
  ]);
}

async function readConversationMetaHash(rdb, convId) {
  const primary = await rdb.hgetall(keyConversationMeta(convId));
  if (primary && Object.keys(primary).length > 0) return { payload: primary, source: 'primary' };
  const legacy = await rdb.hgetall(keyConversationMetaLegacy(convId));
  if (legacy && Object.keys(legacy).length > 0) return { payload: legacy, source: 'legacy' };
  return { payload: null, source: null };
}

export async function readUserProfile(redis, uid) {
  const rdb = createRedisAdapter(redis);
  const profile = (await rdb.getJson(keyUserV2(uid))) || (await rdb.hgetall(keyUser(uid)));
  if (!profile || Object.keys(profile).length === 0) return null;
  return {
    userId: uid,
    displayName: safeDisplayName(profile.displayName, profile.email || uid),
    email: profile.email || uid,
    avatar: profile.avatarUrl || profile.avatar || null,
    active: profile.active !== undefined ? String(profile.active) === 'true' : true,
  };
}

export async function upsertUserProfile(redis, uid, { displayName, avatarUrl }) {
  const rdb = createRedisAdapter(redis);
  const payload = {};
  if (displayName) payload.displayName = displayName;
  if (avatarUrl) payload.avatarUrl = avatarUrl;
  if (Object.keys(payload).length === 0) return;
  await Promise.all([
    rdb.hset(keyUser(uid), payload),
    rdb.setJson(keyUserV2(uid), { uid, email: uid, ...payload, active: true }),
  ]);
}

async function readConversationParticipants(redis, convId, rawMeta) {
  const rdb = createRedisAdapter(redis);
  const direct = normalizeParticipants(rawMeta?.participants);
  if (direct.length > 0) return direct;
  const setKey = keyConversationMembers(convId);
  const hasSet = await rdb.exists(setKey);
  if (hasSet) {
    const members = await rdb.smembers(setKey);
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
  const rdb = createRedisAdapter(redis);
  const v2 = await rdb.getJson(keyConversationMetaV2(convId));
  if (v2 && Object.keys(v2).length > 0) {
    const participants = normalizeParticipants(v2.participants);
    const lastActivity = v2.lastMsgAt ?? v2.updatedAt ?? v2.createdAt ?? null;
    return {
      convId,
      type: v2.type || 'dm',
      createdAt: v2.createdAt ?? null,
      updatedAt: v2.updatedAt ?? null,
      lastMsgAt: lastActivity,
      lastMessageAt: lastActivity,
      lastMsgId: v2.lastMsgId ?? null,
      lastMsgAuthor: v2.lastMsgAuthor ?? null,
      lastMsgPreview: v2.lastMsgPreview ?? null,
      title: v2.title ?? null,
      createdBy: v2.createdBy ?? null,
      participants,
      p1: participants[0] || null,
      p2: participants[1] || null,
    };
  }

  const { payload: raw, source } = await readConversationMetaHash(rdb, convId);
  if (!raw || Object.keys(raw).length === 0) return null;
  if (source === 'legacy') await persistConversationMeta(rdb, convId, raw);
  const participants = await readConversationParticipants(rdb, convId, raw);
  const lastActivity = raw.lastMessageAt || raw.lastMsgAt || raw.updatedAt || raw.createdAt || null;
  const normalizedPayload = { ...raw, participants: JSON.stringify(participants) };
  await persistConversationMeta(rdb, convId, normalizedPayload);
  return {
    convId,
    type: raw.type || raw.kind || 'dm',
    createdAt: raw.createdAt || null,
    updatedAt: raw.updatedAt || null,
    lastMsgAt: lastActivity,
    lastMessageAt: lastActivity,
    lastMsgId: raw.lastMsgId || null,
    lastMsgAuthor: raw.lastMsgAuthor || null,
    lastMsgPreview: raw.lastMsgPreview || raw.lastMessagePreview || null,
    title: raw.title || null,
    createdBy: raw.createdBy || null,
    participants,
    p1: raw.p1 || participants[0] || null,
    p2: raw.p2 || participants[1] || null,
  };
}

async function ensureMembersSet(redis, convId, participants) {
  if (!participants?.length) return;
  const rdb = createRedisAdapter(redis);
  const setKey = keyConversationMembers(convId);
  await rdb.sadd(setKey, participants);
}

export async function ensureDmConversation(redis, uidA, uidB) {
  const rdb = createRedisAdapter(redis);
  const convId = buildConversationId(uidA, uidB);
  if (!convId) return null;
  const existing = await fetchConversationMeta(rdb, convId);
  if (existing) return existing;
  const createdAt = toIsoTimestamp();
  const participants = [uidA, uidB];
  await persistConversationMeta(rdb, convId, {
    convId,
    type: 'dm',
    createdAt,
    updatedAt: createdAt,
    lastMsgAt: createdAt,
    lastMessageAt: createdAt,
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
  const rdb = createRedisAdapter(redis);
  const filtered = Array.from(new Set((members || []).map((m) => normalizeUserId(m)).filter(Boolean)));
  if (filtered.length === 0) return null;
  const convId = buildGroupId(randomUUID());
  const createdAt = toIsoTimestamp();
  await persistConversationMeta(rdb, convId, {
    convId,
    type: 'group',
    title: safeDisplayName(title, 'Gruppe'),
    createdBy: createdBy || null,
    createdAt,
    updatedAt: createdAt,
    lastMsgAt: createdAt,
    lastMessageAt: createdAt,
    participants: JSON.stringify(filtered),
  });
  await ensureMembersSet(rdb, convId, filtered);
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
  const rdb = createRedisAdapter(redis);
  const normalizedLimit = Math.min(Math.max(Number(limit) || 0, 1), 500);

  async function readInbox(key) {
    const rows = await rdb.zrange(key, 0, normalizedLimit - 1, { withScores: true, rev: true });
    return (rows || []).map((row) => ({
      convId: row.member,
      lastActivityTs: Number(row.score) || 0,
    }));
  }

  const primaryV2 = await readInbox(keyUserInboxV2(uid));
  if (primaryV2.length > 0) return primaryV2;

  const primary = await readInbox(keyUserInbox(uid));
  if (primary.length > 0) {
    await Promise.all(
      primary.map((entry) => rdb.zadd(keyUserInboxV2(uid), { score: entry.lastActivityTs, member: entry.convId }))
    );
    return primary;
  }
  await rebuildInboxForUser(redis, uid);
  const rebuilt = await readInbox(keyUserInboxV2(uid));
  if (rebuilt.length > 0) return rebuilt;
  const legacy = await readInbox(keyUserConversations(uid));
  if (legacy.length > 0) {
    await Promise.all(
      legacy.map((entry) => rdb.zadd(keyUserInbox(uid), { score: entry.lastActivityTs, member: entry.convId }))
    );
  }
  return legacy;
}

async function resolveLastActivity(rdb, convId, meta) {
  const direct =
    toTimestampMs(meta?.lastMsgAt) ||
    toTimestampMs(meta?.lastMessageAt) ||
    toTimestampMs(meta?.updatedAt) ||
    toTimestampMs(meta?.createdAt);
  if (direct) return direct;
  const recentV2 = await rdb.zrange(keyConversationMessagesV2(convId), 0, 0, { withScores: true, rev: true });
  const scoreV2 = Array.isArray(recentV2) && recentV2.length > 0 ? Number(recentV2[0].score) : null;
  if (Number.isFinite(scoreV2) && scoreV2 > 0) return scoreV2;
  const recent = await rdb.zrange(keyConversationMessages(convId), 0, 0, { withScores: true, rev: true });
  const score = Array.isArray(recent) && recent.length > 0 ? Number(recent[0].score) : null;
  if (Number.isFinite(score) && score > 0) return score;
  return null;
}

async function iterateConversationIds(redis) {
  const rdb = createRedisAdapter(redis);
  const ids = new Set();
  for (const pattern of metaScanPatterns()) {
    let cursor = 0;
    do {
      const result = await rdb.scan(cursor, { match: pattern, count: 200 });
      const nextCursor = Array.isArray(result) ? Number(result[0]) : Number(result.cursor || 0);
      const keys = Array.isArray(result) ? result[1] : result.keys || [];
      for (const key of keys) {
        const convId = parseConversationIdFromMetaKey(key);
        if (convId) ids.add(convId);
      }
      cursor = nextCursor;
    } while (cursor !== 0);
  }
  return Array.from(ids.values());
}

export async function rebuildInboxForUser(redis, uid) {
  const rdb = createRedisAdapter(redis);
  const convIds = await iterateConversationIds(redis);
  for (const convId of convIds) {
    const meta = await fetchConversationMeta(rdb, convId);
    if (!meta) continue;
    if (!meta.participants.includes(uid)) continue;
    const ts = await resolveLastActivity(rdb, convId, meta);
    const score = Number.isFinite(ts) ? Number(ts) : Date.now();
    for (const participant of meta.participants) {
      await Promise.all([
        rdb.zadd(keyUserInboxV2(participant), { score, member: convId }),
        rdb.zadd(keyUserInbox(participant), { score, member: convId }),
        rdb.zadd(keyUserConversations(participant), { score, member: convId }),
      ]);
    }
  }
}

export async function registerConversationForUsers(redis, convId, participants, tsMs) {
  const rdb = createRedisAdapter(redis);
  const score = Number(tsMs || Date.now());
  for (const uid of participants || []) {
    await Promise.all([
      rdb.zadd(keyUserInboxV2(uid), { score, member: convId }),
      rdb.zadd(keyUserInbox(uid), { score, member: convId }),
      rdb.zadd(keyUserConversations(uid), { score, member: convId }),
    ]);
  }
}

export function buildMessagePayload(convId, author, body, timestampMs, providedMessageId) {
  const msgId = providedMessageId?.startsWith(`${convId}:`) ? providedMessageId : buildMessageId(convId, timestampMs);
  const ts = Number(msgId.split(':').pop());
  const senderEmail = author.email || author.userId || null;
  return {
    msgId,
    convId,
    senderUid: author.userId,
    senderEmail,
    senderName: safeDisplayName(author.displayName, senderEmail || 'Unbekannter Nutzer'),
    body: body || '',
    timestampMs: ts || timestampMs,
  };
}

export async function appendMessage(redis, convMeta, messagePayload) {
  const rdb = createRedisAdapter(redis);
  const timestampIso = toIsoTimestamp(messagePayload.timestampMs);
  const existingV2 = await rdb.getJson(keyMessageV2(messagePayload.msgId));
  if (existingV2) return hydrateMessage(messagePayload.msgId, existingV2);

  const msgKey = keyMessage(messagePayload.msgId);
  const exists = await rdb.exists(msgKey);
  if (exists) {
    const stored = await rdb.hgetall(msgKey);
    return hydrateMessage(messagePayload.msgId, stored);
  }

  const storedMessage = {
    id: messagePayload.msgId,
    convId: convMeta.convId,
    senderUid: messagePayload.senderUid,
    senderEmail: messagePayload.senderEmail || messagePayload.senderUid,
    senderName: messagePayload.senderName,
    body: messagePayload.body,
    text: messagePayload.body,
    ts: messagePayload.timestampMs,
    tsIso: timestampIso,
  };

  await Promise.all([
    rdb.hset(msgKey, storedMessage),
    rdb.setJson(keyMessageV2(messagePayload.msgId), storedMessage),
  ]);

  await Promise.all([
    rdb.zadd(keyConversationMessages(convMeta.convId), {
      score: messagePayload.timestampMs,
      member: messagePayload.msgId,
    }),
    rdb.zadd(keyConversationMessagesV2(convMeta.convId), {
      score: messagePayload.timestampMs,
      member: messagePayload.msgId,
    }),
  ]);

  const lastMessagePreview = messagePayload.body.slice(0, 240);
  await persistConversationMeta(rdb, convMeta.convId, {
    updatedAt: timestampIso,
    lastMsgAt: timestampIso,
    lastMessageAt: timestampIso,
    lastMsgId: messagePayload.msgId,
    lastMsgAuthor: messagePayload.senderName,
    lastMsgPreview: lastMessagePreview,
    lastMessagePreview,
  });

  return {
    id: messagePayload.msgId,
    convId: convMeta.convId,
    senderEmail: messagePayload.senderEmail || null,
    senderName: messagePayload.senderName,
    text: messagePayload.body,
    ts: messagePayload.timestampMs,
    authorId: messagePayload.senderUid,
    authorDisplayName: messagePayload.senderName,
    body: messagePayload.body,
    timestamp: timestampIso,
  };
}

function hydrateMessage(msgId, raw) {
  if (!raw || Object.keys(raw).length === 0) return null;
  const tsValue = raw.ts ?? raw.timestamp ?? raw.tsIso ?? raw.timestampMs;
  const tsMs = Number(tsValue);
  const timestampIso = Number.isFinite(tsMs) && tsMs > 0 ? new Date(tsMs).toISOString() : raw.tsIso || raw.timestamp || raw.ts;
  return {
    id: msgId,
    convId: raw.convId || raw.conversationId,
    senderEmail: raw.senderEmail || raw.sender || raw.authorEmail || null,
    senderName: raw.senderName || raw.author || raw.senderEmail || 'Unbekannter Nutzer',
    text: raw.text || raw.body || '',
    ts: Number.isFinite(tsMs) && tsMs > 0 ? tsMs : null,
    authorId: raw.senderUid || raw.authorId,
    authorDisplayName: raw.senderName || raw.author || raw.senderEmail || 'Unbekannter Nutzer',
    body: raw.text || raw.body || '',
    timestamp: timestampIso,
  };
}

async function fetchMessagesByIds(redis, ids) {
  const rdb = createRedisAdapter(redis);
  const items = [];
  for (const id of ids) {
    const rawV2 = await rdb.getJson(keyMessageV2(id));
    const parsed = hydrateMessage(id, rawV2 || (await rdb.hgetall(keyMessage(id))));
    if (parsed) items.push(parsed);
  }
  items.sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime());
  return items;
}

export async function readMessages(redis, convId, { afterTs = null, beforeTs = null, limit = 50 } = {}) {
  const rdb = createRedisAdapter(redis);
  const keyV2 = keyConversationMessagesV2(convId);
  const keyV1 = keyConversationMessages(convId);
  const fallbackKeys = [`chat:v1:msg:${convId}`, `chat:msg:${convId}`];
  const cappedLimit = Math.min(Math.max(Number(limit) || 0, 1), 200);

  const afterTsNumber = afterTs === null || afterTs === undefined ? null : Number(afterTs);
  const normalizedAfterTs = Number.isNaN(afterTsNumber) ? null : afterTsNumber;

  async function selectKey() {
    const v2Card = await rdb.zcard(keyV2);
    if (v2Card > 0) return { key: keyV2, total: v2Card };
    const v1Card = await rdb.zcard(keyV1);
    if (v1Card > 0) return { key: keyV1, total: v1Card };
    for (const altKey of fallbackKeys) {
      const card = await rdb.zcard(altKey);
      if (card > 0) return { key: altKey, total: card };
    }
    return { key: keyV2, total: v2Card };
  }

  const selected = await selectKey();

  if (beforeTs !== null) {
    const members = await rdb.zrangebyscore(selected.key, '-inf', beforeTs - 1, {
      limit: cappedLimit,
      offset: 0,
      rev: true,
    });
    const hasMore = members.length === cappedLimit;
    const messages = await fetchMessagesByIds(redis, members);
    return { messages, hasMoreBefore: hasMore, hasMoreAfter: false };
  }

  if (normalizedAfterTs !== null) {
    const members = await rdb.zrangebyscore(selected.key, normalizedAfterTs + 1, '+inf', {
      limit: cappedLimit,
      offset: 0,
      rev: false,
    });
    const hasMore = members.length === cappedLimit;
    const messages = await fetchMessagesByIds(redis, members);
    return { messages, hasMoreBefore: false, hasMoreAfter: hasMore };
  }

  const members = await rdb.zrevrange(selected.key, 0, cappedLimit - 1);
  const total = selected.total;
  const hasMoreBefore = total > members.length;
  const messages = await fetchMessagesByIds(redis, members);
  return { messages, hasMoreBefore, hasMoreAfter: false };
}

export function buildConversationSummary(meta, profiles, currentUserId) {
  const participants = meta.participants.map((uid) => ({
    userId: uid,
    displayName: safeDisplayName(profiles.get(uid)?.displayName, profiles.get(uid)?.email || uid),
    email: profiles.get(uid)?.email || uid,
    avatar: profiles.get(uid)?.avatar || null,
  }));
  const lastActivity = meta.lastMsgAt || meta.lastMessageAt || meta.updatedAt || meta.createdAt;
  const title = meta.type === 'group'
    ? meta.title || 'Gruppe'
    : participants.find((p) => p.userId !== currentUserId)?.displayName || 'Direktnachricht';
  return {
    id: meta.convId,
    convId: meta.convId,
    type: meta.type || 'dm',
    title,
    participants,
    lastMessage: meta.lastMsgPreview || meta.lastMessagePreview || null,
    lastMessagePreview: meta.lastMsgPreview || meta.lastMessagePreview || null,
    lastAuthor: meta.lastMsgAuthor || null,
    lastMessageAt: toIsoOrNull(lastActivity),
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
        displayName: safeDisplayName(entry.displayName, entry.email || entry.userId),
        email: entry.email || entry.userId,
        avatar: entry.avatar || null,
      });
    }
  }
  return map;
}

export async function searchActiveUsers(redis, query, limit = 50) {
  const rdb = createRedisAdapter(redis);
  const q = (query || '').toString().trim().toLowerCase();
  const matches = [];
  let cursor = 0;
  const maxLimit = Math.min(Math.max(limit, 1), 200);
  const matchPatterns = [`${keyUser('*')}`, `${keyUserV2('*')}`];

  for (const matchPattern of matchPatterns) {
    cursor = 0;
    do {
      const result = await rdb.scan(cursor, { match: matchPattern, count: 200 });
      const nextCursor = Array.isArray(result) ? Number(result[0]) : Number(result.cursor || 0);
      const keys = Array.isArray(result) ? result[1] : result.keys || [];

      for (const key of keys) {
        const profile = key.includes(':v2:') ? await rdb.getJson(key) : await rdb.hgetall(key);
        if (!profile || Object.keys(profile).length === 0) continue;
        const active = profile.active === undefined ? true : String(profile.active) === 'true';
        if (!active) continue;
        const uid = profile.uid || profile.email || key.split(':').pop();
        if (!uid) continue;
        const displayName = safeDisplayName(profile.displayName, profile.email || uid);
        const email = profile.email || '';
        if (q && !displayName.toLowerCase().includes(q) && !email.toLowerCase().includes(q)) continue;
        matches.push({ userId: uid, displayName, avatar: profile.avatarUrl || profile.avatar || null });
        if (matches.length >= maxLimit) return matches;
      }

      cursor = nextCursor;
    } while (cursor !== 0 && matches.length < maxLimit);
    if (matches.length >= maxLimit) break;
  }

  return matches;
}

export { normalizeUserId, persistConversationMeta, iterateConversationIds };
