export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../../_lib/http.js';
import { requirePortalAccess } from '../_guard.js';
import { getDbClient } from '../../_lib/db.js';

const MDR_SLUG = 'mdr-2017-745';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { write: true, allowPrrc: true });
  if (!actor) return;
  if (req.method !== 'POST') return bad(res, 'method not allowed', 405);

  const client = await getDbClient();
  try {
    await client.query('BEGIN');

    const docQ = await client.query('select id from legal_documents where slug = $1 limit 1', [MDR_SLUG]);
    const docId = docQ.rows?.[0]?.id || null;
    if (!docId) throw new Error('document not found');

    await client.query(
      `delete from legal_section_changes
       where change_id in (select id from legal_changes where document_id = $1)`,
      [docId],
    );
    await client.query('delete from legal_changes where document_id = $1', [docId]);
    await client.query('delete from legal_sections where version_id in (select id from legal_versions where document_id = $1)', [docId]);
    await client.query('delete from legal_versions where document_id = $1', [docId]);
    await client.query('update legal_documents set current_version_id = null where id = $1', [docId]);

    await client.query('COMMIT');
    return ok(res, { ok: true, slug: MDR_SLUG, reset: true });
  } catch (err) {
    try { await client.query('ROLLBACK'); } catch {}
    console.error('[admin/regulatory/reset_mdr_cache] failed', err?.message || err);
    return bad(res, err?.message || 'reset failed', 500);
  } finally {
    client.release();
  }
}
