// api/chat/v1/_lib/cleanup.js
import { createTrackedRedis } from './redisTracker.js';

const LEGACY_PATTERNS = ['dfs:chat:*', 'chat:*'];
const RESET_PATTERN = 'chat:v1:*';
const RESET_FLAG_KEY = 'chat:v1:__reset__completed';
const KEEP_PREFIX = 'chat:v1:';

function normalizeKeys(input) {
  if (!input) return [];
  if (Array.isArray(input)) return input;
  if (typeof input === 'object') {
    if (Array.isArray(input.result)) return input.result;
    if (Array.isArray(input.data)) return input.data;
    if (Array.isArray(input.keys)) return input.keys;
  }
  if (typeof input === 'string') return [input];
  return [];
}

async function deleteByPattern(client, pattern, { skipKeys = new Set(), excludePrefix = null } = {}) {
  let cursor = 0;
  let removed = 0;
  const deleteChunkSize = 200;
  const maxBatchSize = 500;
  const maxIterations = 1000;
  let iterations = 0;

  do {
    if (iterations >= maxIterations) {
      console.warn('[chat/cleanup] aborting scan to avoid infinite loop', { pattern });
      break;
    }

    const scan = await client.scan(cursor, { match: pattern, count: deleteChunkSize });
    const nextCursor = Number(scan?.cursor ?? scan?.[0] ?? 0);
    cursor = Number.isFinite(nextCursor) ? nextCursor : 0;

    const keys =
      scan?.keys ??
      scan?.[1] ??
      scan?.result ??
      scan?.data ??
      scan;

    const filtered = normalizeKeys(keys)
      .filter((k) => typeof k === 'string' && k.length)
      .filter((k) => {
        if (skipKeys.has(k)) return false;
        if (excludePrefix && k.startsWith(excludePrefix)) return false;
        return true;
      })
      .slice(0, maxBatchSize);
    if (filtered.length > 0) {
      for (let i = 0; i < filtered.length; i += deleteChunkSize) {
        const slice = filtered.slice(i, i + deleteChunkSize);
        await client.del(...slice);
        removed += slice.length;
      }
    }
    iterations += 1;
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
