export function withTiming(name, fn, context = {}) {
  const startedAt = Date.now();
  const stats = {
    name,
    route: context.route || name,
    tdId: context.tdId || null,
    ms_db: 0,
    ms_kv: 0,
    db_queries: 0,
    kv_ops: 0,
    rows: 0,
    cacheHit: false,
    coldStartSuspected: false,
  };

  const step = async (bucket, op) => {
    const t0 = Date.now();
    try {
      return await op();
    } finally {
      const elapsed = Date.now() - t0;
      if (bucket === 'db') {
        stats.ms_db += elapsed;
        stats.db_queries += 1;
      } else if (bucket === 'kv') {
        stats.ms_kv += elapsed;
        stats.kv_ops += 1;
      }
    }
  };

  const api = {
    stats,
    db: (op) => step('db', op),
    kv: (op) => step('kv', op),
    addRows: (count = 0) => {
      const numeric = Number(count);
      if (Number.isFinite(numeric)) stats.rows += numeric;
    },
    setCacheHit: (value) => {
      stats.cacheHit = Boolean(value);
    },
    setColdStartSuspected: (value) => {
      stats.coldStartSuspected = Boolean(value);
    },
    setServerTiming: (res) => {
      const total = Date.now() - startedAt;
      res.setHeader('Server-Timing', `app;dur=${total}, db;dur=${stats.ms_db}, kv;dur=${stats.ms_kv}`);
    },
  };

  return Promise.resolve()
    .then(() => fn(api))
    .finally(() => {
      const msTotal = Date.now() - startedAt;
      console.info('[perf]', {
        route: stats.route,
        tdId: stats.tdId,
        ms_total: msTotal,
        ms_db: stats.ms_db,
        ms_kv: stats.ms_kv,
        db_queries: stats.db_queries,
        kv_ops: stats.kv_ops,
        rows: stats.rows,
        cacheHit: stats.cacheHit,
        coldStartSuspected: stats.coldStartSuspected,
      });
    });
}
