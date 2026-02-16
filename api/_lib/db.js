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
  if (!isMissingColumn && !isMissingTable) return null;

  return {
    code: 'DB_SCHEMA_MISMATCH',
    sqlState: sqlState || null,
    message,
    columnName: isMissingColumn ? extractMissingColumnName(err) : null,
    cause: err,
  };
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

async function getPool() {
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
  primarySql,
  primaryParams = [],
  fallbackSql = null,
  fallbackParams = null,
  fallbackMapper = null,
  tableHint = null,
  route = null,
} = {}) {
  if (!primarySql) throw new Error('queryWithFallback primarySql is required');

  if (tableHint) {
    await probeTableColumns(tableHint, query).catch(() => null);
  }

  const primary = await safeQuery(primarySql, primaryParams);
  if (primary.ok) return primary.result;

  if (primary.error?.code !== 'DB_SCHEMA_MISMATCH' || !fallbackSql) {
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

  console.warn(`[dbQueryFallback] usedFallback=true sqlState=${primary.error.sqlState || 'unknown'} column=${primary.error.columnName || 'unknown'} route=${route || 'unknown'}`);

  const fallback = await safeQuery(fallbackSql, Array.isArray(fallbackParams) ? fallbackParams : primaryParams);
  if (!fallback.ok) {
    const fallbackErr = new Error(fallback.error?.message || 'fallback query failed');
    fallbackErr.code = fallback.error?.code || 'DB_QUERY_FAILED';
    fallbackErr.sqlState = fallback.error?.sqlState || null;
    fallbackErr.cause = fallback.error?.cause || null;
    throw fallbackErr;
  }

  if (typeof fallbackMapper === 'function') {
    fallback.result.rows = (fallback.result.rows || []).map((row) => fallbackMapper(row));
  }

  return fallback.result;
}
