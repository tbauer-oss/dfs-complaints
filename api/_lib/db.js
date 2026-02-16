let pool = null;
let dbOverride = null;
let warnedAboutSslMode = false;

const DATABASE_URL_ENV_KEYS = ['DATABASE_URL', 'POSTGRES_URL', 'SUPABASE_DB_URL'];

export function getDatabaseConnectionString() {
  for (const key of DATABASE_URL_ENV_KEYS) {
    const value = String(process.env[key] || '').trim();
    if (value) return value;
  }
  return '';
}

function parseConnectionTarget(connectionString = '') {
  try {
    const parsed = new URL(connectionString);
    const host = String(parsed.hostname || '').trim() || 'unknown-host';
    const port = String(parsed.port || '5432').trim();
    const dbName = String(parsed.pathname || '/').replace(/^\//, '') || 'postgres';
    return { host: host.toLowerCase(), port, dbName };
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
  if (!host) return { rejectUnauthorized: false };
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
    console.error('[db] connect failed', { target, message: err?.message || String(err) });
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
    console.error('[db] query failed', { target, message: err?.message || String(err) });
    throw toDbUnavailableError(err, target);
  }
}
