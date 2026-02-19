export const config = { runtime: 'nodejs' };

import fs from 'node:fs/promises';
import path from 'node:path';
import { handlePreflight, setCors } from '../_lib/http.js';

const CATALOG_PATH = path.join(process.cwd(), 'api', '_data', 'td_catalog.json');

function softFail(res) {
  return res.status(200).json({ ok: false, items: [], error: 'CATALOG_UNAVAILABLE' });
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  if (req.method !== 'GET') {
    return res.status(405).json({ ok: false, items: [], error: 'METHOD_NOT_ALLOWED' });
  }

  try {
    const raw = await fs.readFile(CATALOG_PATH, 'utf8');
    const parsed = JSON.parse(raw);
    const items = Array.isArray(parsed)
      ? parsed
          .filter((item) => item && item.active === true)
          .map((item) => ({
            td_key: String(item.td_key || '').trim(),
            title: String(item.title || '').trim(),
            mdr_rule: String(item.mdr_rule || '').trim(),
            ...(item.risk_class == null || String(item.risk_class).trim() === ''
              ? {}
              : { risk_class: String(item.risk_class).trim() }),
            active: true,
          }))
      : [];

    return res.status(200).json({ ok: true, items });
  } catch (error) {
    console.warn('[td/catalog] catalog unavailable', { message: error?.message || String(error) });
    return softFail(res);
  }
}
