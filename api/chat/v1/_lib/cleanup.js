// api/chat/v1/_lib/cleanup.js
import { createTrackedRedis } from './redisTracker.js';

const LEGACY_PATTERNS = ['dfs:chat:*', 'chat:*'];
const RESET_PATTERN = 'chat:v1:*';
const RESET_FLAG_KEY = 'chat:v1:__reset__completed';
const KEEP_PREFIX = 'chat:v1:';

async function deleteByPattern(client, pattern, { skipKeys = new Set(), excludePrefix = null } = {}) {
  let cursor = 0;
  let removed = 0;

  do {
    const scan = await client.scan(cursor, { match: pattern, count: 100 });
    cursor = Number(scan?.cursor ?? scan?.[0] ?? 0);
    const keys = scan?.keys ?? scan?.[1] ?? [];
    const filtered = (keys || []).filter((k) => {
      if (typeof k !== 'string') return false;
      if (skipKeys.has(k)) return false;
      if (excludePrefix && k.startsWith(excludePrefix)) return false;
      return true;
    });
    if (filtered.length === 0) continue;
    const chunkSize = 10;
    for (let i = 0; i < filtered.length; i += chunkSize) {
      const slice = filtered.slice(i, i + chunkSize);
      await client.del(...slice);
      removed += slice.length;
    }
  } while (cursor !== 0);

  return removed;
}

async function purgeChatNamespaceOnce(client) {
  const alreadyPurged = await client.get(RESET_FLAG_KEY);
  if (alreadyPurged) return 0;

  const claimed = await client.set(RESET_FLAG_KEY, 'in-progress', { nx: true, ex: 300 });
  if (claimed !== 'OK') return 0;

  const skipKeys = new Set([RESET_FLAG_KEY]);
  const removed = await deleteByPattern(client, RESET_PATTERN, { skipKeys });
  await client.set(RESET_FLAG_KEY, 'done');
  return removed;
}

export async function purgeLegacyChatKeys(baseClient) {
  const { client, counters } = createTrackedRedis(baseClient);
  let deleted = 0;

  deleted += await purgeChatNamespaceOnce(client);

  for (const pattern of LEGACY_PATTERNS) {
    deleted += await deleteByPattern(client, pattern, {
      skipKeys: new Set([RESET_FLAG_KEY]),
      excludePrefix: KEEP_PREFIX,
    });
  }

  return { deleted, counters };
}
