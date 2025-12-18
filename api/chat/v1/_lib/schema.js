// api/chat/v1/_lib/schema.js

const PREFIX = 'chat:v1';
const V2_PREFIX = 'chat:v2';
const MAX_BODY_LENGTH = 2000;

export const META_PREFIX = 'chat:conv:';

export function normalizeUserId(raw) {
  const value = String(raw || '').trim();
  if (!value) return null;
  return value.toLowerCase();
}

export function buildConversationId(userA, userB) {
  const a = normalizeUserId(userA);
  const b = normalizeUserId(userB);
  if (!a || !b) return null;
  const [min, max] = [a, b].sort();
  return `dm:${min}:${max}`;
}

const DM_ID_PATTERN = '[a-z0-9@._+%-]+';

export function isConversationId(value) {
  return new RegExp(`^(dm:${DM_ID_PATTERN}:${DM_ID_PATTERN}|grp:[a-z0-9-]+)$`, 'i').test(
    String(value || '').trim()
  );
}

export function buildGroupId(uuid) {
  const id = (uuid || '').toString().trim();
  if (!id) return null;
  return `grp:${id}`;
}

export function buildMessageId(convId, timestampMs) {
  const ts = Number(timestampMs || Date.now());
  return `${convId}:${ts}`;
}

export function keyUser(uid) {
  return `${PREFIX}:user:${uid}`;
}

export function keyUserV2(uid) {
  return `${V2_PREFIX}:user:${uid}`;
}

export function keyUserConversations(uid) {
  return `${PREFIX}:user:${uid}:convs`;
}

export function keyUserInbox(uid) {
  return `chat:inbox:${uid}`;
}

export function keyUserInboxV2(uid) {
  return `${V2_PREFIX}:inbox:${uid}`;
}

export function keyConversationMeta(convId) {
  return `${META_PREFIX}${convId}`;
}

export function keyConversationMetaV2(convId) {
  return `${V2_PREFIX}:conv:${convId}`;
}

export function keyConversationMetaLegacy(convId) {
  return `${PREFIX}:conv:${convId}:meta`;
}

export function keyConversationMembers(convId) {
  return `${PREFIX}:conv:${convId}:members`;
}

export function keyConversationMessages(convId) {
  return `${PREFIX}:conv:${convId}:msgs`;
}

export function keyConversationMessagesV2(convId) {
  return `${V2_PREFIX}:msgs:${convId}`;
}

export function keyMessage(msgId) {
  return `${PREFIX}:msg:${msgId}`;
}

export function keyMessageV2(msgId) {
  return `${V2_PREFIX}:msg:${msgId}`;
}

export function sanitizeBody(body) {
  const text = String(body || '').trim();
  if (!text) return null;
  if (text.length > MAX_BODY_LENGTH) return text.slice(0, MAX_BODY_LENGTH);
  return text;
}

export function toIsoTimestamp(ms = Date.now()) {
  return new Date(ms).toISOString();
}

export function parseTimestamp(value) {
  if (value === undefined || value === null || value === '') return null;
  const num = Number(value);
  if (!Number.isFinite(num) || num < 0) return null;
  return num;
}

export function metaScanPatterns() {
  return [`${META_PREFIX}*`, keyConversationMetaLegacy('*'), keyConversationMetaV2('*')];
}

export function parseConversationIdFromMetaKey(key) {
  if (!key) return null;
  if (key.startsWith(META_PREFIX)) return key.slice(META_PREFIX.length);
  const legacyPrefix = `${PREFIX}:conv:`;
  if (key.startsWith(legacyPrefix) && key.endsWith(':meta')) {
    return key.slice(legacyPrefix.length, -':meta'.length);
  }
  const v2Prefix = `${V2_PREFIX}:conv:`;
  if (key.startsWith(v2Prefix)) return key.slice(v2Prefix.length);
  return null;
}

export function parseParticipantList(raw) {
  if (!raw?.participants) return [];
  try {
    const parsed = typeof raw.participants === 'string' ? JSON.parse(raw.participants) : raw.participants;
    return Array.isArray(parsed) ? parsed.filter(Boolean) : [];
  } catch {
    return [];
  }
}
