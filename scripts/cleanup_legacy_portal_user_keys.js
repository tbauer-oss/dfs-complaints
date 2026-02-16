#!/usr/bin/env node
import { query } from '../api/_lib/db.js';

const LEGACY_PATTERN = 'dfs:portal:user:%';

async function main() {
  if (!String(process.env.DATABASE_URL || '').trim()) {
    console.error('[cleanup_legacy_portal_user_keys] missing DATABASE_URL');
    process.exit(1);
  }

  const dryRun = String(process.env.DRY_RUN || '').trim() === '1' || process.argv.includes('--dry-run');

  const countResult = await query(
    `SELECT COUNT(*)::int AS cnt
     FROM kv_store
     WHERE k LIKE $1`,
    [LEGACY_PATTERN],
  );
  const total = Number(countResult?.rows?.[0]?.cnt || 0);

  if (dryRun) {
    console.info(`[cleanup_legacy_portal_user_keys] dry-run: found ${total} legacy keys matching ${LEGACY_PATTERN}`);
    return;
  }

  const deleteResult = await query(
    `DELETE FROM kv_store
     WHERE k LIKE $1`,
    [LEGACY_PATTERN],
  );

  console.info(`[cleanup_legacy_portal_user_keys] deleted ${deleteResult.rowCount || 0} legacy keys (matched ${total})`);
}

main().catch((err) => {
  console.error('[cleanup_legacy_portal_user_keys] failed', err?.message || err);
  process.exit(1);
});
