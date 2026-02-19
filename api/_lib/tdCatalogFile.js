import fs from 'node:fs/promises';
import path from 'node:path';

const CATALOG_PATH = path.join(process.cwd(), 'api', '_data', 'td_catalog.json');

function normalizeItem(item) {
  if (!item || typeof item !== 'object') return null;
  const td_key = String(item.td_key || '').trim();
  const title = String(item.title || '').trim();
  const mdr_rule = String(item.mdr_rule || '').trim();
  const riskValue = item.risk_class == null ? '' : String(item.risk_class).trim();

  return {
    td_key,
    title,
    mdr_rule,
    ...(riskValue ? { risk_class: riskValue } : {}),
    active: item.active === true,
  };
}

export async function loadTdCatalogItemsFromFile() {
  const raw = await fs.readFile(CATALOG_PATH, 'utf8');
  const parsed = JSON.parse(raw);
  if (!Array.isArray(parsed)) return [];
  return parsed.map(normalizeItem).filter(Boolean);
}

export async function loadActiveTdCatalogItemsFromFile() {
  const items = await loadTdCatalogItemsFromFile();
  return items.filter((item) => item.active === true);
}
