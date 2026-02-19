import { query } from '../_lib/db.js';

export const config = { runtime: 'nodejs' };

export default async function handler(req, res) {
  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'method not allowed' });
  }

  const t0 = Date.now();

  try {
    const { rows } = await query(`
      SELECT td_key, title, product_group, risk_class
      FROM td_catalog
      ORDER BY td_key ASC
    `);

    console.log('[perf][td/catalog]', Date.now() - t0);
    return res.status(200).json({
      ok: true,
      items: rows || [],
    });
  } catch (e) {
    console.error('[td/catalog]', e);
    console.log('[perf][td/catalog]', Date.now() - t0);
    return res.status(200).json({
      ok: false,
      items: [],
    });
  }
}
