let pool = null;
let dbOverride = null;

export function __setDbForTests(mock = null) {
  dbOverride = mock;
}

async function getPool() {
  if (pool) return pool;
  const connectionString = String(process.env.DATABASE_URL || '').trim();
  if (!connectionString) return null;

  const pg = await import('pg');
  const Pool = pg.Pool || pg.default?.Pool;
  pool = new Pool({
    connectionString,
    max: Number(process.env.DB_POOL_MAX || 3),
    connectionTimeoutMillis: Number(process.env.DB_CONNECTION_TIMEOUT_MS || 3000),
    idleTimeoutMillis: Number(process.env.DB_IDLE_TIMEOUT_MS || 5000),
    ssl: connectionString.includes('localhost') ? false : { rejectUnauthorized: false },
  });
  return pool;
}

export async function query(text, params = []) {
  if (dbOverride?.query) return dbOverride.query(text, params);
  const activePool = await getPool();
  if (!activePool) {
    const err = new Error('DATABASE_URL is not configured');
    err.code = 'DB_UNAVAILABLE';
    throw err;
  }
  return activePool.query(text, params);
}
