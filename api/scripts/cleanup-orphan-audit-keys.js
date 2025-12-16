import {
  getRedisInstance,
  redisRead,
  redisWrite,
  runWithRedisContext,
} from '../_lib/redisClient.js';

const INDEX_KEY = 'dfs:audits:index';
const AUDIT_PATTERN = 'dfs:audit:*';

async function scanKeys(pattern) {
  const client = getRedisInstance();
  if (!client) return [];
  const keys = [];
  let cursor = 0;
  do {
    const res = await redisRead.scan(cursor, { match: pattern, count: 1000 });
    if (Array.isArray(res)) {
      cursor = Number(res[0] || 0);
      keys.push(...(res[1] || []));
    } else {
      cursor = Number(res?.cursor || 0);
      keys.push(...(res?.members || res?.keys || []));
    }
  } while (cursor !== 0);
  return keys;
}

async function deleteOrphanedAuditKeys({ dryRun = true } = {}) {
  const indexMembers = new Set(await redisRead.smembers(INDEX_KEY));
  const allAuditKeys = await scanKeys(AUDIT_PATTERN);

  const orphanedKeys = [];
  for (const key of allAuditKeys) {
    const match = String(key || '').match(/^dfs:audit:([^:]+)(?::.*)?$/);
    const auditId = match?.[1];
    if (auditId && indexMembers.has(auditId)) continue;
    orphanedKeys.push(key);
  }

  if (!dryRun) {
    for (const key of orphanedKeys) {
      await redisWrite.del(key);
    }
  }

  return {
    dryRun,
    indexCount: indexMembers.size,
    scanned: allAuditKeys.length,
    orphanedKeys,
    deleted: dryRun ? 0 : orphanedKeys.length,
  };
}

async function main() {
  const dryRun = !process.argv.includes('--apply');
  const context = { route: 'scripts/cleanup-orphan-audit-keys', method: 'SCRIPT' };
  const result = await runWithRedisContext(context, () => deleteOrphanedAuditKeys({ dryRun }));
  console.log(JSON.stringify(result, null, 2));
}

main().catch((err) => {
  console.error('cleanup failed', err);
  process.exitCode = 1;
});
