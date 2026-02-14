#!/usr/bin/env node
import { redis } from '../_lib/redis.js';


const P = 'dfs:';
const AUDIT_INDEX_KEY = `${P}audits:index`;
const AUDITOR_INDEX_KEY = `${P}auditors:index`;
const LEGACY_AUDIT_INDEX_KEY = `${P}audit:index`;
const LEGACY_PLAN_PREFIX = `${P}audit:plan:`;
const AUDITOR_PREFIX = `${P}audit:auditor:`;

async function scan(pattern) {
  let cursor = 0;
  const keys = [];
  do {
    const res = await redis.scan(cursor, { match: pattern, count: 1000 });
    cursor = Array.isArray(res) ? Number(res[0]) : Number(res.cursor || 0);
    const batch = Array.isArray(res) ? res[1] || [] : res.members || res.keys || [];
    keys.push(...batch);
  } while (cursor !== 0);
  return keys;
}

function auditIdFromKey(key) {
  if (key.startsWith(LEGACY_PLAN_PREFIX)) return key.slice(LEGACY_PLAN_PREFIX.length);
  const planMatch = key.match(/^dfs:audit:([^:]+):plan$/);
  if (planMatch) return planMatch[1];
  const metaMatch = key.match(/^dfs:audit:([^:]+)$/);
  if (metaMatch) return metaMatch[1];
  return null;
}

async function main() {
  const dryRun = !process.argv.includes('--apply');
  const auditIndex = new Set((await redis.smembers(AUDIT_INDEX_KEY))?.map(String) || []);
  const auditorIndex = new Set((await redis.smembers(AUDITOR_INDEX_KEY))?.map(String) || []);

  const deletions = new Set();

  const auditKeys = await scan(`${P}audit:*`);
  for (const key of auditKeys) {
    if (key === LEGACY_AUDIT_INDEX_KEY) {
      deletions.add(key);
      continue;
    }
    if (key.startsWith(LEGACY_PLAN_PREFIX)) {
      deletions.add(key);
      continue;
    }
    const auditId = auditIdFromKey(key);
    if (auditId && !auditIndex.has(auditId)) {
      deletions.add(key);
    }
  }

  const auditorKeys = await scan(`${P}audit:auditor:*`);
  for (const key of auditorKeys) {
    const auditorId = key.slice(AUDITOR_PREFIX.length);
    if (!auditorIndex.has(auditorId)) {
      deletions.add(key);
    }
  }

  if (dryRun) {
    console.log('[cleanup] dry run; use --apply to delete keys');
    console.log(`audit index entries: ${auditIndex.size}`);
    console.log(`auditor index entries: ${auditorIndex.size}`);
    console.log(`keys marked for deletion: ${deletions.size}`);
    deletions.forEach((k) => console.log(`  ${k}`));
    return;
  }

  const batches = Array.from(deletions);
  for (let i = 0; i < batches.length; i += 25) {
    const chunk = batches.slice(i, i + 25);
    if (chunk.length > 0) {
      await redis.del(...chunk);
    }
  }

  console.log('[cleanup] deleted keys', { count: deletions.size });
}

main().catch((err) => {
  console.error('[cleanup] failed', err);
  process.exit(1);
});
