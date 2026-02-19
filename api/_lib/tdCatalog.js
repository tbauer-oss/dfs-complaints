import crypto from 'node:crypto';
import fs from 'node:fs/promises';

import { getDbClient, queryWithFallback } from './db.js';
import { parseCsvObjects } from './csv.js';

const SOURCE_NAME = 'dfs_products.csv';
const CSV_URL = new URL('../_data/dfs_products.csv', import.meta.url);

function toIsoDate(value = new Date()) {
  return new Date(value).toISOString();
}

function firstValue(row, keys = []) {
  for (const key of keys) {
    const value = row?.[key];
    if (value == null) continue;
    const text = String(value).trim();
    if (text) return text;
  }
  return '';
}

function normalizeTdKey(value) {
  const text = String(value || '').trim();
  const match = /\b(MDR-TD\s*\d+)\b/i.exec(text);
  return match ? match[1].toUpperCase().replace(/\s+/g, '') : '';
}

function normalizeTitle(rawTitle, tdKey) {
  const cleaned = String(rawTitle || '').trim().replace(/^\s*MDR-TD\s*\d+\s*[-–—:]?\s*/i, '').trim();
  return cleaned || tdKey;
}

function numericTdSort(a, b) {
  const numA = Number((a.tdKey.match(/TD(\d+)/i) || [])[1] || 0);
  const numB = Number((b.tdKey.match(/TD(\d+)/i) || [])[1] || 0);
  return numA - numB;
}

export async function readCatalogSource() {
  const csvText = await fs.readFile(CSV_URL, 'utf8');
  const sourceHash = crypto.createHash('sha256').update(csvText, 'utf8').digest('hex');
  return { csvText, sourceHash };
}

export function buildCatalogItems(csvText, { sourceHash, generatedAt = new Date() } = {}) {
  const rows = parseCsvObjects(csvText);
  const byKey = new Map();
  const updatedAt = toIsoDate(generatedAt);

  for (const row of rows) {
    const tdSource = firstValue(row, ['td_number_and_name', 'td', 'td_key', 'mdr_td', 'tdNumberAndName']);
    const tdKey = normalizeTdKey(tdSource);
    if (!tdKey) continue;

    if (!byKey.has(tdKey)) {
      byKey.set(tdKey, {
        tdKey,
        title: normalizeTitle(firstValue(row, ['td_number_and_name', 'title', 'product_name']), tdKey),
        productFamily: firstValue(row, ['product_family', 'product_group', 'productgroup']) || null,
        rule: firstValue(row, ['classification_rule', 'rule', 'mdr_rule']) || null,
        riskClass: firstValue(row, ['risk_class', 'mdr_classification', 'classification']) || null,
        tags: [],
        updatedAt,
        sourceHash: sourceHash || null,
      });
    }
  }

  return Array.from(byKey.values()).sort(numericTdSort);
}

export async function getActiveCatalogRow() {
  const result = await queryWithFallback({
    tableHint: 'td_catalog',
    route: '/api/td/catalog',
    sqlTag: 'td_catalog_active',
    primarySql: `SELECT id, source, source_hash, generated_at, items_json
                 FROM public.td_catalog
                 WHERE active = true
                 ORDER BY generated_at DESC
                 LIMIT 1`,
    fallbacks: [
      {
        sql: `SELECT null::uuid AS id,
                     'legacy'::text AS source,
                     null::text AS source_hash,
                     now() AS generated_at,
                     jsonb_agg(jsonb_build_object(
                       'tdKey', td_key,
                       'title', coalesce(title, td_key),
                       'productFamily', product_group,
                       'rule', null,
                       'riskClass', risk_class,
                       'tags', '[]'::jsonb,
                       'updatedAt', to_char(coalesce(updated_at, now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
                       'sourceHash', null
                     ) ORDER BY td_key) AS items_json
              FROM public.td_catalog
              WHERE coalesce(active, true) = true`,
      },
      {
        sql: `SELECT null::uuid AS id,
                     'legacy'::text AS source,
                     null::text AS source_hash,
                     now() AS generated_at,
                     jsonb_agg(jsonb_build_object(
                       'tdKey', td_key,
                       'title', coalesce(title, td_key),
                       'productFamily', product_group,
                       'rule', null,
                       'riskClass', mdr_classification,
                       'tags', '[]'::jsonb,
                       'updatedAt', to_char(coalesce(updated_at, now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
                       'sourceHash', null
                     ) ORDER BY td_key) AS items_json
              FROM public.td_catalog
              WHERE coalesce(active, true) = true`,
      },
    ],
  });

  return result.rows?.[0] || null;
}

export async function saveActiveCatalog(items, { sourceHash, source = SOURCE_NAME } = {}) {
  const client = await getDbClient();
  try {
    await client.query('BEGIN');
    await client.query('UPDATE public.td_catalog SET active = false WHERE active = true');
    await client.query(
      `INSERT INTO public.td_catalog (source, source_hash, items_json, active)
       VALUES ($1, $2, $3::jsonb, true)`,
      [source, sourceHash, JSON.stringify(Array.isArray(items) ? items : [])],
    );
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK').catch(() => null);
    throw err;
  } finally {
    client.release();
  }
}

export async function loadOrRebuildCatalog() {
  const t0 = Date.now();
  const timings = { ms_total: 0, ms_db: 0, ms_fs: 0, ms_parse: 0 };

  const dbStart = Date.now();
  const activeRow = await getActiveCatalogRow();
  timings.ms_db = Date.now() - dbStart;

  const fsStart = Date.now();
  const { csvText, sourceHash } = await readCatalogSource();
  timings.ms_fs = Date.now() - fsStart;

  if (activeRow && String(activeRow.source_hash || '') === sourceHash) {
    timings.ms_total = Date.now() - t0;
    return {
      outcome: 'DB_HIT',
      items: Array.isArray(activeRow.items_json) ? activeRow.items_json : [],
      sourceHash,
      generatedAt: activeRow.generated_at || new Date().toISOString(),
      timings,
    };
  }

  const parseStart = Date.now();
  const generatedAt = new Date();
  const items = buildCatalogItems(csvText, { sourceHash, generatedAt });
  timings.ms_parse = Date.now() - parseStart;

  await saveActiveCatalog(items, { sourceHash, source: SOURCE_NAME });
  timings.ms_total = Date.now() - t0;

  return {
    outcome: activeRow ? 'SOURCE_HASH_CHANGED_IMPORT' : 'DB_MISS_IMPORT',
    items,
    sourceHash,
    generatedAt: generatedAt.toISOString(),
    timings,
  };
}

export async function rebuildTdCatalog() {
  const { csvText, sourceHash } = await readCatalogSource();
  const generatedAt = new Date();
  const items = buildCatalogItems(csvText, { sourceHash, generatedAt });
  await saveActiveCatalog(items, { sourceHash, source: SOURCE_NAME });
  return { sourceHash, catalogRows: items.length, generatedAt: generatedAt.toISOString() };
}

export async function clearTdCatalogCache() {
  return null;
}

export async function getTdCatalogEntries() {
  const row = await getActiveCatalogRow();
  const items = Array.isArray(row?.items_json) ? row.items_json : [];
  return items.map((item) => ({
    code: String(item?.tdKey || '').trim(),
    label: `${item?.tdKey || ''} – ${item?.title || item?.tdKey || ''}`,
    title: String(item?.title || item?.tdKey || '').trim(),
    classification: item?.riskClass || null,
    rule: item?.rule || null,
    productGroup: item?.productFamily || null,
  })).filter((entry) => entry.code);
}
