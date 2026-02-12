// api/_lib/products.js
// Helper to load DFS product metadata from flutter_web/lib/data/dfs_products.csv
// and provide a cached index by article_number.

import fs from 'fs/promises';
import path from 'path';

const CSV_CANDIDATES = [
  process.env.DFS_PRODUCTS_CSV,
  path.join(process.cwd(), 'dfs_mobile', 'assets', 'data', 'dfs_products.csv'),
  path.join(process.cwd(), 'flutter_web', 'lib', 'data', 'dfs_products.csv'),
].filter(Boolean);

let _csvPath = null;
const CACHE_TTL_MS = Math.max(5 * 60 * 1000, Number(process.env.PRODUCT_CACHE_TTL_MS || 0));

let _cache = { loadedAt: 0, products: null, index: null, mtimeMs: 0, csvPath: '' };

function _normalizeArticleNumber(value) {
  return (value ?? '').toString().trim();
}

function _splitCsvLine(line) {
  const values = [];
  let current = '';
  let inQuotes = false;
  for (let i = 0; i < line.length; i++) {
    const char = line[i];
    const isQuote = char === '"';
    const isDelimiter = char === ';';

    if (isQuote) {
      const isEscapedQuote = inQuotes && i + 1 < line.length && line[i + 1] === '"';
      if (isEscapedQuote) {
        current += '"';
        i++;
        continue;
      }
      inQuotes = !inQuotes;
      continue;
    }

    if (isDelimiter && !inQuotes) {
      values.push(current);
      current = '';
      continue;
    }

    current += char;
  }
  values.push(current);
  return values;
}

function _parseCsv(content) {
  const lines = content
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l.length > 0);
  if (lines.length === 0) return [];

  const headers = _splitCsvLine(lines[0]).map((h) => h.trim());
  const products = [];

  for (const line of lines.slice(1)) {
    const cells = _splitCsvLine(line);
    if (cells.length === 0 || cells.every((c) => c.trim().length === 0)) continue;
    const map = {};
    for (let i = 0; i < headers.length && i < cells.length; i++) {
      map[headers[i]] = cells[i];
    }
    const articleNumber = _normalizeArticleNumber(map['article_number']);
    products.push({
      tdNumberAndName: map['td_number_and_name'] || '',
      basicUdiDi: map['basic_udi_di'] || '',
      productGroup: map['product_group'] || '',
      articleNumber,
      productName: map['product_name'] || '',
      isoCode: map['iso_code'] || '',
      packagingUnitVe: map['packaging_unit_ve'] || '',
      riskClass: map['risk_class'] || '',
      classificationRule: map['classification_rule'] || '',
      udiSingleUnit: map['udi_single_unit'] || '',
      udiVe: map['udi_ve'] || '',
      mdrCode: map['mdr_code'] || '',
      gmdn: map['gmdn'] || '',
      umdnsCode: map['umdns_code'] || '',
      emdn: map['emdn'] || '',
      dmidsNo: map['dmids_no'] || '',
      certificationNo: map['certification_no'] || '',
      material: map['material'] || '',
      surfaceInfo: map['surface_info'] || '',
      firstPlacingOnMarketDate: map['first_placing_on_market_date'] || '',
      legacyDevice: map['legacy_device'] || '',
      _raw: map,
    });
  }

  return products;
}


async function _resolveCsvPath() {
  if (_csvPath) return _csvPath;
  for (const candidate of CSV_CANDIDATES) {
    try {
      await fs.access(candidate);
      _csvPath = candidate;
      return _csvPath;
    } catch {}
  }
  throw new Error('dfs_products.csv not found in known locations');
}

async function _loadProductsFromDisk() {
  const csvPath = await _resolveCsvPath();
  const stat = await fs.stat(csvPath);
  const mtimeMs = stat.mtimeMs;
  if (_cache.products && _cache.mtimeMs === mtimeMs && _cache.csvPath === csvPath) return _cache.products;

  const buf = await fs.readFile(csvPath);
  let content;
  try {
    content = buf.toString('utf8');
  } catch (_) {
    content = buf.toString('latin1');
  }

  const products = _parseCsv(content);
  _cache = { ..._cache, products, mtimeMs, loadedAt: Date.now(), index: null, csvPath };
  return products;
}

async function _getProducts() {
  const now = Date.now();
  if (_cache.products && now - _cache.loadedAt < CACHE_TTL_MS) return _cache.products;
  return await _loadProductsFromDisk();
}

export async function getProducts() {
  return await _getProducts();
}

export async function getProductIndex() {
  if (_cache.index) return _cache.index;
  const products = await _getProducts();
  const index = new Map();
  for (const p of products) {
    const key = _normalizeArticleNumber(p.articleNumber);
    if (!key) continue;
    if (!index.has(key)) index.set(key, p);
  }
  _cache.index = index;
  return index;
}

export async function getProductByArticle(articleNumber) {
  const index = await getProductIndex();
  return index.get(_normalizeArticleNumber(articleNumber)) || null;
}

export function normalizeArticleNumber(value) {
  return _normalizeArticleNumber(value);
}


export function parseMdrTdCode(value) {
  const raw = (value ?? '').toString().trim();
  const match = /^\s*(MDR-TD\d+)/i.exec(raw);
  return match ? match[1].toUpperCase() : '';
}

export async function getUniqueMdrTdEntries() {
  const products = await _getProducts();
  const byCode = new Map();
  for (const product of products) {
    const source = (product?.tdNumberAndName ?? '').toString().trim();
    const code = parseMdrTdCode(source);
    if (!code) continue;
    if (!byCode.has(code)) {
      byCode.set(code, {
        code,
        label: source || code,
        title: source.replace(/^\s*MDR-TD\d+\s*[-–:]?\s*/i, '').trim() || source || code,
        classification: (product?.riskClass ?? '').toString().trim() || null,
        rule: (product?.classificationRule ?? '').toString().trim() || null,
        productGroup: (product?.productGroup ?? '').toString().trim() || null,
      });
    }
  }
  return Array.from(byCode.values()).sort((a, b) => a.code.localeCompare(b.code, undefined, { numeric: true }));
}
