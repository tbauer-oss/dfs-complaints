import { probeTableColumns, rememberMissingColumn, rememberMissingTable } from './dbCaps.js';

let pool = null;
let dbOverride = null;
let warnedAboutSslMode = false;

const DATABASE_URL_ENV_KEYS = ['DATABASE_URL', 'POSTGRES_URL', 'SUPABASE_DB_URL'];
const CONNECTIVITY_ERROR_CODES = new Set([
  'DB_UNAVAILABLE',
  'STORE_UNAVAILABLE',
  'ETIMEDOUT',
  'ECONNREFUSED',
  'ECONNRESET',
  'ENOTFOUND',
  'EAI_AGAIN',
  '57P01',
]);
const SCHEMA_DRIFT_ERROR_CODES = new Set(['42703', '42804', '22P02', '42883', '42P01']);
const schemaFallbackLogGuard = new Map();

export function getDatabaseConnectionString() {
  for (const key of DATABASE_URL_ENV_KEYS) {
    const value = String(process.env[key] || '').trim();
    if (value) return value;
  }
  return '';
}

function parseConnectionTarget(connectionString = '') {
  try {
    const u = new URL(connectionString);
    const dbName = (u.pathname || '').replace(/^\//, '') || 'postgres';
    return {
      host: String(u.hostname || '').trim().toLowerCase() || 'unknown-host',
      port: String(u.port || '5432').trim(),
      dbName,
    };
  } catch {
    return { host: 'unknown-host', port: 'unknown-port', dbName: 'unknown-db' };
  }
}

export function getSanitizedDbTarget(connectionString = getDatabaseConnectionString()) {
  const { host, port, dbName } = parseConnectionTarget(connectionString);
  return `${host}:${port}/${dbName}`;
}

function sanitizeConnectionString(connectionString = '') {
  try {
    const parsed = new URL(connectionString);
    parsed.searchParams.delete('sslmode');
    parsed.searchParams.delete('uselibpqcompat');
    return parsed.toString();
  } catch {
    return connectionString;
  }
}

function getSslConfigForHost(host = '') {
  if (host === 'localhost' || host === '127.0.0.1' || host === '::1') return false;
  return { rejectUnauthorized: false };
}

function toDbUnavailableError(err, target) {
  if (err && typeof err === 'object') {
    err.code = 'DB_UNAVAILABLE';
    err.target = target;
    return err;
  }

  const unavailableErr = new Error(String(err || `DB unavailable (${target})`));
  unavailableErr.code = 'DB_UNAVAILABLE';
  unavailableErr.target = target;
  return unavailableErr;
}

export function extractMissingColumnName(err) {
  const direct = String(err?.column || '').trim();
  if (direct) return direct;
  const message = String(err?.message || '');
  const quoted = message.match(/column\s+"([^"]+)"/i);
  if (quoted?.[1]) return quoted[1];
  const plain = message.match(/column\s+([a-zA-Z0-9_\.]+)\s+does not exist/i);
  return plain?.[1] || null;
}

export function mapSchemaMismatchError(err) {
  const sqlState = String(err?.code || err?.sqlState || '').toUpperCase();
  const message = String(err?.message || '');
  const lower = message.toLowerCase();
  const isMissingColumn = sqlState === '42703' || lower.includes('undefined_column') || (lower.includes('column') && lower.includes('does not exist'));
  const isMissingTable = sqlState === '42P01' || (lower.includes('relation') && lower.includes('does not exist'));
  const isSchemaDriftCode = SCHEMA_DRIFT_ERROR_CODES.has(sqlState);
  if (!isMissingColumn && !isMissingTable && !isSchemaDriftCode) return null;

  return {
    code: 'DB_SCHEMA_MISMATCH',
    sqlState: sqlState || null,
    message,
    columnName: isMissingColumn ? extractMissingColumnName(err) : null,
    isSchemaDrift: true,
    cause: err,
  };
}

function logSchemaFallbackOnce({ area = 'db', code = 'unknown', message = '', sqlTag = 'unknown' } = {}) {
  const normalizedMessage = String(message || '').slice(0, 200);
  const key = `${area}:${code}:${sqlTag}:${normalizedMessage}`;
  const now = Date.now();
  const last = schemaFallbackLogGuard.get(key) || 0;
  if (now - last < 1000) return;
  schemaFallbackLogGuard.set(key, now);
  console.warn('[dbSchemaFallback]', { area, code, message: normalizedMessage, usedFallback: true, sqlTag });
}

export function isConnectivityError(err) {
  const code = String(err?.code || '').toUpperCase();
  if (CONNECTIVITY_ERROR_CODES.has(code)) return true;
  const lower = String(err?.message || '').toLowerCase();
  return lower.includes('timeout') || lower.includes('connect') || lower.includes('connection');
}

export function __setDbForTests(mock = null) {
  dbOverride = mock;
}

export async function getPool() {
  if (pool) return pool;
  const connectionString = getDatabaseConnectionString();
  if (!connectionString) return null;

  const lowerConn = connectionString.toLowerCase();
  if (!warnedAboutSslMode && (lowerConn.includes('sslmode=') || lowerConn.includes('uselibpqcompat='))) {
    warnedAboutSslMode = true;
    if (lowerConn.includes('sslmode=')) {
      console.warn('Remove sslmode from DATABASE_URL; SSL is handled in db.js');
    }
    if (lowerConn.includes('uselibpqcompat=')) {
      console.warn('Remove uselibpqcompat from DATABASE_URL; SSL is handled in db.js');
    }
  }

  const target = parseConnectionTarget(connectionString);
  const sanitizedConnectionString = sanitizeConnectionString(connectionString);

  const pg = await import('pg');
  const Pool = pg.Pool || pg.default?.Pool;
  pool = new Pool({
    connectionString: sanitizedConnectionString,
    max: Number(process.env.DB_POOL_MAX || 2),
    connectionTimeoutMillis: Number(process.env.DB_CONNECTION_TIMEOUT_MS || 8000),
    idleTimeoutMillis: Number(process.env.DB_IDLE_TIMEOUT_MS || 5000),
    ssl: getSslConfigForHost(target.host),
  });
  return pool;
}

export async function getDbClient() {
  if (dbOverride?.connect) return dbOverride.connect();
  const activePool = await getPool();
  if (!activePool) {
    const err = new Error(`${DATABASE_URL_ENV_KEYS.join(' / ')} is not configured`);
    err.code = 'DB_UNAVAILABLE';
    throw err;
  }
  const target = getSanitizedDbTarget();
  try {
    return await activePool.connect();
  } catch (err) {
    console.error('[db] connect failed', {
      target,
      message: err?.message || String(err),
      cause: err?.cause,
    });
    throw toDbUnavailableError(err, target);
  }
}



async function runWithStatementTimeout(sql, params = [], timeoutMs = 4000) {
  const client = await getDbClient();
  try {
    await client.query('BEGIN');
    await client.query(`SET LOCAL statement_timeout = ${Number(timeoutMs) || 4000}`);
    const result = await client.query(sql, params);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    try { await client.query('ROLLBACK'); } catch {}
    if (String(err?.code || '') === '57014') {
      const timeoutErr = new Error('Query timeout');
      timeoutErr.code = 'DB_TIMEOUT';
      timeoutErr.cause = err;
      throw timeoutErr;
    }
    throw err;
  } finally {
    client.release();
  }
}

export async function query(text, params = []) {
  if (dbOverride?.query) return dbOverride.query(text, params);
  const activePool = await getPool();
  if (!activePool) {
    const err = new Error(`${DATABASE_URL_ENV_KEYS.join(' / ')} is not configured`);
    err.code = 'DB_UNAVAILABLE';
    throw err;
  }
  const target = getSanitizedDbTarget();
  try {
    return await activePool.query(text, params);
  } catch (err) {
    const schemaMismatch = mapSchemaMismatchError(err);
    if (schemaMismatch) {
      throw err;
    }

    if (isConnectivityError(err)) {
      console.error('[db] query connectivity failed', {
        target,
        message: err?.message || String(err),
        code: err?.code || null,
      });
      throw toDbUnavailableError(err, target);
    }

    throw err;
  }
}

export async function safeQuery(text, params = []) {
  try {
    const result = await query(text, params);
    return { ok: true, result, error: null };
  } catch (err) {
    const schemaMismatch = mapSchemaMismatchError(err);
    if (schemaMismatch) return { ok: false, result: null, error: schemaMismatch };
    if (isConnectivityError(err)) {
      return {
        ok: false,
        result: null,
        error: {
          code: 'DB_UNAVAILABLE',
          sqlState: String(err?.code || ''),
          message: err?.message || String(err),
          cause: err,
        },
      };
    }
    throw err;
  }
}

export async function queryWithFallback({
  sql = null,
  params = [],
  primarySql = null,
  primaryParams = null,
  fallbackSql = null,
  fallbackParams = null,
  fallbackMapper = null,
  fallbacks = null,
  tableHint = null,
  route = null,
  sqlTag = null,
} = {}) {
  const effectiveSql = primarySql || sql;
  const effectiveParams = Array.isArray(primaryParams) ? primaryParams : params;
  if (!effectiveSql) throw new Error('queryWithFallback sql is required');

  if (tableHint) {
    await probeTableColumns(tableHint, query).catch(() => null);
  }

  const primary = await safeQuery(effectiveSql, effectiveParams);
  if (primary.ok) return primary.result;

  const fallbackChain = Array.isArray(fallbacks) && fallbacks.length
    ? fallbacks
    : (fallbackSql ? [{ sql: fallbackSql, params: fallbackParams, mapper: fallbackMapper }] : []);

  if (primary.error?.code !== 'DB_SCHEMA_MISMATCH' || !fallbackChain.length) {
    const err = new Error(primary.error?.message || 'queryWithFallback failed');
    err.code = primary.error?.code || 'DB_QUERY_FAILED';
    err.sqlState = primary.error?.sqlState || null;
    err.cause = primary.error?.cause || null;
    throw err;
  }

  if (tableHint) {
    if (primary.error.columnName) rememberMissingColumn(tableHint, primary.error.columnName);
    if (String(primary.error.sqlState || '').toUpperCase() === '42P01') rememberMissingTable(tableHint);
  }

  logSchemaFallbackOnce({
    area: route || tableHint || 'db',
    code: primary.error.sqlState || 'unknown',
    message: primary.error.message || 'schema drift fallback',
    sqlTag: sqlTag || 'unknown',
  });

  let lastError = null;
  for (const candidate of fallbackChain) {
    const fallback = await safeQuery(candidate?.sql, Array.isArray(candidate?.params) ? candidate.params : effectiveParams);
    if (!fallback.ok) {
      lastError = fallback.error;
      continue;
    }
    if (typeof candidate?.mapper === 'function') {
      fallback.result.rows = (fallback.result.rows || []).map((row) => candidate.mapper(row));
    }
    return fallback.result;
  }
  const fallbackErr = new Error(lastError?.message || 'fallback query failed');
  fallbackErr.code = lastError?.code || 'DB_QUERY_FAILED';
  fallbackErr.sqlState = lastError?.sqlState || null;
  fallbackErr.cause = lastError?.cause || null;
  throw fallbackErr;
}


export async function queryWithStatementTimeout(text, params = [], timeoutMs = 4000) {
  return runWithStatementTimeout(text, params, timeoutMs);
}
