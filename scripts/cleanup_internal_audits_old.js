import { redis } from '../api/_lib/redis.js';
import { IA_KEYS } from '../api/internal-audits/_utils.js';

async function run() {
  const prefixes = [
    'dfs:audit:',
    'dfs:audits:index',
    'dfs:audit:index',
    'dfs:audit:plan:',
    'dfs:audit:auditor:',
  ];

  const toDelete = new Set();
  for (const prefix of prefixes) {
    const keys = await redis.keys(`${prefix}*`);
    keys.forEach((k) => toDelete.add(k));
  }

  // avoid wiping new V2 keys
  const protectedKeys = new Set([
    IA_KEYS.KEY_AUDIT_INDEX,
    IA_KEYS.KEY_AUDITOR_INDEX,
  ]);
  for (const key of Array.from(toDelete)) {
    if (protectedKeys.has(key)) {
      toDelete.delete(key);
    }
  }

  if (toDelete.size === 0) {
    console.log('No legacy audit keys found.');
    return;
  }

  console.log('Deleting legacy audit keys:', Array.from(toDelete));
  await Promise.all(Array.from(toDelete).map((key) => redis.del(key)));
  console.log('Done.');
}

run().catch((err) => {
  console.error('Cleanup failed', err);
  process.exit(1);
});
