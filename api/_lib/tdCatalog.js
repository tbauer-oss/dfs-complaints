import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';

import { getDbClient, query, queryWithFallback } from './db.js';
import { redis } from './redis.js';

const CSV_PATH = path.join(process.cwd(), 'api', '_data', 'dfs_products.csv');
const CACHE_KEY = 'dfs:td:catalog:v1';
const CACHE_TTL_SECONDS = 600;

function normText(value) {
  const text = String(value ?? '').trim();
  return text.length ? text : null;
}

function detectDelimiter(headerLine = '') {
  const comma = (headerLine.match(/,/g) || []).length;
  const semi = (headerLine.match(/;/g) || []).length;
  return semi > comma ? ';' : ',';
}

function parseDelimitedRows(content, delimiter) {
  const rows = [];
  let row = [];
  let field = '';
  let inQuotes = false;

  for (let i = 0; i < content.length; i += 1) {
    const char = content[i];
    if (char === '"') {
      if (inQuotes && content[i + 1] === '"') {
        field += '"';
        i += 1;
        continue;
      }
      inQuotes = !inQuotes;
      continue;
    }

    if (!inQuotes && char === delimiter) {
      row.push(field);
      field = '';
      continue;
    }

    if (!inQuotes && (char === '\n' || char === '\r')) {
      if (char === '\r' && content[i + 1] === '\n') i += 1;
      row.push(field);
      rows.push(row);
      row = [];
      field = '';
      continue;
    }

    field += char;
  }

  row.push(field);
  if (row.length > 1 || String(row[0] || '').trim()) rows.push(row);
  return rows;
}

function normalizeTdKey(value) {
  const input = String(value ?? '').trim();
  if (!input) return '';
  const match = /\b(MDR-TD\s*\d+)\b/i.exec(input);
  if (!match) return '';
  return match[1].toUpperCase().replace(/\s+/g, '');
}

function normalizeTitle(value, tdKey) {
  const raw = String(value ?? '').trim();
  if (!raw) return tdKey;
  const cleaned = raw.replace(/^\s*MDR-TD\s*\d+\s*[-–—:]?\s*/i, '').trim();
  return cleaned || raw;
}

function firstValue(row, keys = []) {
  for (const key of keys) {
    const raw = row?.[key];
    if (raw == null) continue;
    const text = String(raw).trim();
    if (text) return text;
  }
  return '';
}

function isMissingRelationError(err, relationName = '') {
  const sqlState = String(err?.sqlState || err?.code || '').toUpperCase();
  if (sqlState === '42P01') return true;
  const relation = String(relationName || '').trim();
  const message = String(err?.message || '').toLowerCase();
  if (!message) return false;
  if (relation) {
    return message.includes(`relation \"${relation.toLowerCase()}\" does not exist`);
  }
  return message.includes('relation') && message.includes('does not exist');
}

async function loadTdCatalogFromCsvFallback() {
  const csvText = await readProductsCsvFromDisk();
  const rows = parseProductsCsv(csvText);
  return buildTdCatalog(rows).map((row) => ({
    td_key: row.td_key,
    product_group: row.product_group,
    title: row.title,
    mdr_classification: row.mdr_classification,
    active: true,
    source_row: row.source_row || null,
    updated_at: null,
  }));
}

export async function readProductsCsvFromDisk() {
  return fs.readFile(CSV_PATH, 'utf8');
}

export function parseProductsCsv(csvText) {
  const lines = String(csvText || '').split(/\r?\n/);
  const headerLine = lines.find((line) => String(line || '').trim().length > 0) || '';
  if (!headerLine) return [];
  const delimiter = detectDelimiter(headerLine);
  const parsed = parseDelimitedRows(csvText, delimiter);
  if (!parsed.length) return [];

  const headers = parsed[0].map((cell) => String(cell || '').trim().toLowerCase());
  const rows = [];

  for (const values of parsed.slice(1)) {
    if (!values || !values.length) continue;
    if (values.every((cell) => String(cell || '').trim() === '')) continue;
    const row = {};
    for (let i = 0; i < headers.length; i += 1) {
      if (!headers[i]) continue;
      row[headers[i]] = String(values[i] ?? '').trim();
    }
    rows.push(row);
  }

  return rows;
}

export function buildTdCatalog(rows = []) {
  const byKey = new Map();

  for (const row of rows) {
    const tdRaw = firstValue(row, ['td_number_and_name', 'td', 'td_key', 'mdr_td']);
    const tdKey = normalizeTdKey(tdRaw);
    if (!tdKey) continue;

    const existing = byKey.get(tdKey);
    const titleSource = firstValue(row, ['td_number_and_name', 'title', 'product_name']);
    const productGroup = firstValue(row, ['product_group', 'productgroup']);
    const classification = firstValue(row, ['risk_class', 'mdr_classification', 'classification']);

    const next = {
      td_key: tdKey,
      product_group: normText(existing?.product_group || productGroup),
      title: normText(existing?.title || normalizeTitle(titleSource || tdRaw, tdKey)),
      mdr_classification: normText(existing?.mdr_classification || classification),
      active: true,
      source_row: row,
    };

    byKey.set(tdKey, next);
  }

  return Array.from(byKey.values()).sort((a, b) => a.td_key.localeCompare(b.td_key, undefined, { numeric: true }));
}

export function hashSource(csvText) {
  return crypto.createHash('sha256').update(String(csvText || ''), 'utf8').digest('hex');
}

async function invalidateTdCatalogCache() {
  try {
    await redis.del(CACHE_KEY);
  } catch {
    // optional
  }
}

export async function upsertTdCatalog(catalog = [], meta = {}) {
  const startedAt = Date.now();
  const client = await getDbClient();

  try {
    await client.query('BEGIN');

    const keepKeys = catalog.map((row) => row.td_key).filter(Boolean);
    if (keepKeys.length > 0) {
      await client.query('UPDATE public.td_catalog SET active = false WHERE td_key <> ALL($1::text[])', [keepKeys]);
    } else {
      await client.query('UPDATE public.td_catalog SET active = false');
    }

    for (const row of catalog) {
      await client.query(
        `INSERT INTO public.td_catalog (td_key, product_group, title, mdr_classification, active, source_row, updated_at)
         VALUES ($1, $2, $3, $4, true, $5::jsonb, now())
         ON CONFLICT (td_key)
         DO UPDATE SET
           product_group = EXCLUDED.product_group,
           title = EXCLUDED.title,
           mdr_classification = EXCLUDED.mdr_classification,
           active = true,
           source_row = EXCLUDED.source_row,
           updated_at = now()`,
        [row.td_key, row.product_group, row.title, row.mdr_classification, JSON.stringify(row.source_row || {})],
      );
    }

    const lastBuildMs = Number(meta.last_build_ms || Date.now() - startedAt);
    await client.query(
      `INSERT INTO public.td_catalog_meta (source_hash, source_updated_at, row_count, last_build_ms, last_error)
       VALUES ($1, now(), $2, $3, NULL)`,
      [String(meta.source_hash || ''), Number(catalog.length || 0), lastBuildMs],
    );

    await client.query('COMMIT');
    await invalidateTdCatalogCache();

    return {
      sourceHash: String(meta.source_hash || ''),
      rowCount: catalog.length,
      lastBuildMs,
      updatedAt: new Date().toISOString(),
    };
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch {}

    await query(
      `INSERT INTO public.td_catalog_meta (source_hash, source_updated_at, row_count, last_build_ms, last_error)
       VALUES ($1, now(), $2, $3, $4)`,
      [String(meta.source_hash || ''), Number(catalog.length || 0), Number(meta.last_build_ms || 0), String(err?.message || err)],
    ).catch(() => null);
    throw err;
  } finally {
    client.release();
  }
}

export async function loadTdCatalogFromDb() {
  let rows = [];
  try {
    const result = await queryWithFallback({
      tableHint: 'td_catalog',
      route: '/api/td/catalog',
      sqlTag: 'td_catalog_load',
      primarySql: `SELECT td_key, product_group, title, mdr_classification, active, source_row, updated_at
                   FROM public.td_catalog
                   WHERE active = true
                   ORDER BY td_key`,
      fallbackSql: `SELECT td_key, product_group, title, NULL::text AS mdr_classification, true AS active, NULL::jsonb AS source_row, now() AS updated_at
                    FROM public.td_catalog
                    ORDER BY td_key`,
    });
    rows = result.rows || [];
  } catch (err) {
    if (!isMissingRelationError(err, 'public.td_catalog')) throw err;
    console.warn('[tdCatalog] missing td_catalog relation, serving CSV fallback');
    return loadTdCatalogFromCsvFallback();
  }

  return rows.map((row) => ({
    td_key: String(row.td_key || '').trim().toUpperCase(),
    product_group: normText(row.product_group),
    title: normText(row.title),
    mdr_classification: normText(row.mdr_classification),
    active: row.active !== false,
    source_row: row.source_row || null,
    updated_at: row.updated_at || null,
  })).filter((row) => row.td_key);
}

export async function loadTdCatalogMeta() {
  try {
    const result = await queryWithFallback({
      tableHint: 'td_catalog_meta',
      route: '/api/td/catalog',
      sqlTag: 'td_catalog_meta_load',
      primarySql: `SELECT source_hash, source_updated_at, row_count, last_build_ms, last_error
                   FROM public.td_catalog_meta
                   ORDER BY source_updated_at DESC
                   LIMIT 1`,
      fallbackSql: `SELECT ''::text AS source_hash, NULL::timestamptz AS source_updated_at, 0::int AS row_count, NULL::int AS last_build_ms, NULL::text AS last_error`,
    });
    return result.rows?.[0] || null;
  } catch (err) {
    if (!isMissingRelationError(err, 'public.td_catalog_meta')) throw err;
    console.warn('[tdCatalog] missing td_catalog_meta relation, serving default meta');
    return null;
  }
}

export async function rebuildTdCatalog() {
  const startedAt = Date.now();
  const csvText = await readProductsCsvFromDisk();
  const sourceHash = hashSource(csvText);
  const rows = parseProductsCsv(csvText);
  const catalog = buildTdCatalog(rows);

  const meta = await upsertTdCatalog(catalog, {
    source_hash: sourceHash,
    last_build_ms: Date.now() - startedAt,
  });

  return {
    ...meta,
    parsedRows: rows.length,
    catalogRows: catalog.length,
    sourceHash,
  };
}

export async function getTdCatalogCached() {
  const startedAt = Date.now();
  let cacheHit = false;
  let cacheMs = 0;
  let dbMs = 0;

  try {
    const cacheStarted = Date.now();
    const cachedRaw = await redis.get(CACHE_KEY);
    cacheMs = Date.now() - cacheStarted;
    if (cachedRaw) {
      const cached = typeof cachedRaw === 'string' ? JSON.parse(cachedRaw) : cachedRaw;
      if (cached?.items && Array.isArray(cached.items)) {
        cacheHit = true;
        return { ...cached, cacheHit, timings: { totalMs: Date.now() - startedAt, cacheMs, dbMs } };
      }
    }
  } catch (err) {
    console.warn('[tdCatalog] cache read failed', { message: err?.message || String(err) });
  }

  const dbStarted = Date.now();
  const [items, meta] = await Promise.all([loadTdCatalogFromDb(), loadTdCatalogMeta()]);
  dbMs = Date.now() - dbStarted;

  const payload = {
    items,
    meta: {
      rowCount: Number(meta?.row_count || items.length || 0),
      sourceHash: meta?.source_hash || null,
      sourceUpdatedAt: meta?.source_updated_at || null,
      lastBuildMs: meta?.last_build_ms ?? null,
      lastError: meta?.last_error || null,
      generatedAt: new Date().toISOString(),
    },
  };

  try {
    await redis.set(CACHE_KEY, JSON.stringify(payload), { ex: CACHE_TTL_SECONDS });
  } catch (err) {
    console.warn('[tdCatalog] cache write failed', { message: err?.message || String(err) });
  }

  return { ...payload, cacheHit, timings: { totalMs: Date.now() - startedAt, cacheMs, dbMs } };
}

export async function clearTdCatalogCache() {
  await invalidateTdCatalogCache();
}

export async function getTdCatalogEntries() {
  const items = await loadTdCatalogFromDb();
  return items.map((row) => ({
    code: row.td_key,
    label: row.title ? `${row.td_key} – ${row.title}` : row.td_key,
    title: row.title || row.td_key,
    classification: row.mdr_classification,
    rule: null,
    productGroup: row.product_group,
  }));
}
