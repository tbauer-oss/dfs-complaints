// api/chat/v1/_lib/cleanup.js
import { createTrackedRedis } from './redisTracker.js';

const LEGACY_PATTERNS = ['dfs:chat:*', 'chat:*'];
const KEEP_PREFIX = 'chat:v1:';

export async function purgeLegacyChatKeys(baseClient) {
  const { client, counters } = createTrackedRedis(baseClient);
  let deleted = 0;

  for (const pattern of LEGACY_PATTERNS) {
    let cursor = 0;
    do {
      const scan = await client.scan(cursor, { match: pattern, count: 100 });
      cursor = Number(scan?.cursor ?? scan?.[0] ?? 0);
      const keys = scan?.keys ?? scan?.[1] ?? [];
      const legacyKeys = (keys || []).filter((k) => typeof k === 'string' && !k.startsWith(KEEP_PREFIX));
      if (legacyKeys.length === 0) continue;
      const chunkSize = 10;
      for (let i = 0; i < legacyKeys.length; i += chunkSize) {
        const slice = legacyKeys.slice(i, i + chunkSize);
        await client.del(...slice);
        deleted += slice.length;
      }
    } while (cursor !== 0);
  }

  return { deleted, counters };
}
