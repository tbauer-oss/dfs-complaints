const tableCaps = new Map();
const loggedMissing = new Set();
const CAP_TTL_MS = Math.max(1000, Number(process.env.DB_CAPS_TTL_MS || 60000));

function normalizeTable(tableName) {
  return String(tableName || '').trim().toLowerCase();
}

function normalizeColumn(columnName) {
  return String(columnName || '').trim().toLowerCase();
}

function ensureCaps(tableName) {
  const table = normalizeTable(tableName);
  if (!table) return null;
  if (!tableCaps.has(table)) {
    tableCaps.set(table, {
      table,
      probed: false,
      missing: new Set(),
      columns: new Set(),
      columnTypes: new Map(),
      updatedAt: 0,
    });
  }
  return tableCaps.get(table);
}

function toPublicCaps(caps) {
  if (!caps) return null;
  const out = {
    table: caps.table,
    probed: caps.probed === true,
    missing: Array.from(caps.missing || []),
    columnTypes: Object.fromEntries(caps.columnTypes || []),
  };
  for (const col of caps.columns || []) {
    out[`has_${col}`] = true;
  }
  for (const col of caps.missing || []) {
    out[`has_${col}`] = false;
  }
  return out;
}

export function getTableCaps(tableName) {
  return toPublicCaps(ensureCaps(tableName));
}

export function rememberMissingColumn(tableName, columnName) {
  const table = normalizeTable(tableName);
  const column = normalizeColumn(columnName);
  if (!table || !column) return;
  const caps = ensureCaps(table);
  caps.missing.add(column);
  caps.columns.delete(column);

  const logKey = `${table}:${column}`;
  if (!loggedMissing.has(logKey)) {
    loggedMissing.add(logKey);
    console.warn(`[dbCaps] table=${table} missing=${column} -> fallback=enabled`);
  }
}

export function rememberMissingTable(tableName) {
  const table = normalizeTable(tableName);
  if (!table) return;
  const caps = ensureCaps(table);
  caps.probed = true;
}

export function rememberTableColumns(tableName, columns = []) {
  const table = normalizeTable(tableName);
  if (!table) return;
  const caps = ensureCaps(table);
  caps.probed = true;
  const nextColumns = new Set((columns || []).map(normalizeColumn).filter(Boolean));
  caps.columns = nextColumns;
  caps.missing = new Set(Array.from(caps.missing || []).filter((col) => !nextColumns.has(col)));
  caps.updatedAt = Date.now();
}

export function rememberTableColumnTypes(tableName, columnTypeRows = []) {
  const table = normalizeTable(tableName);
  if (!table) return;
  const caps = ensureCaps(table);
  caps.probed = true;
  const nextColumns = new Set();
  const nextTypes = new Map();
  for (const row of columnTypeRows || []) {
    const column = normalizeColumn(row?.column_name);
    if (!column) continue;
    nextColumns.add(column);
    nextTypes.set(column, {
      dataType: String(row?.data_type || '').trim().toLowerCase(),
      udtName: String(row?.udt_name || '').trim().toLowerCase(),
    });
  }
  caps.columns = nextColumns;
  caps.columnTypes = nextTypes;
  caps.missing = new Set(Array.from(caps.missing || []).filter((col) => !nextColumns.has(col)));
  caps.updatedAt = Date.now();
}

export async function probeTableColumns(tableName, queryFn) {
  const table = normalizeTable(tableName);
  if (!table || typeof queryFn !== 'function') return getTableCaps(table);

  const caps = ensureCaps(table);
  if (caps.probed && Date.now() - Number(caps.updatedAt || 0) < CAP_TTL_MS) return toPublicCaps(caps);

  try {
    const result = await queryFn(
      `SELECT column_name, data_type, udt_name
         FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = $1`,
      [table],
    );
    rememberTableColumnTypes(table, result?.rows || []);
  } catch (err) {
    // Best-effort in serverless cold starts; do not block query flow on probe failures.
    console.warn('[dbCaps] probe failed', { table, message: err?.message || String(err) });
  }

  return getTableCaps(table);
}

export async function getTableColumnTypes(tableName, queryFn) {
  const caps = await probeTableColumns(tableName, queryFn);
  return caps?.columnTypes || {};
}
