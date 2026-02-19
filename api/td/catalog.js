export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors } from '../_lib/http.js';
import { loadActiveTdCatalogItemsFromFile } from '../_lib/tdCatalogFile.js';

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
    const items = await loadActiveTdCatalogItemsFromFile();
    return res.status(200).json({ ok: true, items });
  } catch (error) {
    console.warn('[td/catalog] catalog unavailable', { message: error?.message || String(error) });
    return softFail(res);
  }
}
