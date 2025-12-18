// api/chat/v1/_lib/migrate.js
import {
  keyConversationMessages,
  keyConversationMessagesV2,
  keyMessage,
  keyMessageV2,
} from './schema.js';
import { createRedisAdapter } from './redisAdapter.js';
import {
  fetchConversationMeta,
  iterateConversationIds,
  registerConversationForUsers,
} from './store.js';

function inferTimestamp(raw) {
  const ts = Number(raw?.ts ?? raw?.timestamp ?? raw?.tsIso);
  if (Number.isFinite(ts) && ts > 0) return ts;
  const parsed = Date.parse(raw?.tsIso || raw?.timestamp || '');
  return Number.isFinite(parsed) ? parsed : Date.now();
}

async function migrateMessagesForConversation(rdb, convId) {
  const existing = await rdb.zcard(keyConversationMessagesV2(convId));
  if (existing > 0) return;

  const ids = await rdb.zrange(keyConversationMessages(convId), 0, -1, { withScores: true });
  for (const entry of ids || []) {
    const msgId = typeof entry === 'object' ? entry.member : entry;
    const raw = await rdb.hgetall(keyMessage(msgId));
    if (!raw || Object.keys(raw).length === 0) continue;
    const ts = typeof entry === 'object' ? Number(entry.score) : inferTimestamp(raw);
    const payload = { ...raw, id: raw.msgId || raw.id || msgId, ts };
    await Promise.all([
      rdb.setJson(keyMessageV2(msgId), payload),
      rdb.zadd(keyConversationMessagesV2(convId), { score: ts, member: msgId }),
    ]);
  }
}

export async function migrateV1toV2(redis, { migrateMessages = false } = {}) {
  const rdb = createRedisAdapter(redis);
  const convIds = await iterateConversationIds(rdb);

  for (const convId of convIds) {
    const meta = await fetchConversationMeta(rdb, convId);
    if (!meta) continue;

    const ts = meta.lastMsgAt || meta.updatedAt || meta.createdAt || Date.now();
    await registerConversationForUsers(rdb, convId, meta.participants, ts);

    if (migrateMessages) {
      await migrateMessagesForConversation(rdb, convId);
    }
  }
}

export default migrateV1toV2;
