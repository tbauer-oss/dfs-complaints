export const config = { runtime: 'nodejs' };

const BASE = process.env.UPSTASH_REDIS_REST_URL;
const TOKEN = process.env.UPSTASH_REDIS_REST_TOKEN;

if (!BASE || !TOKEN) {
  console.warn('[upstash] Missing UPSTASH_REDIS_REST_URL / _TOKEN');
}

async function callPipeline(cmds) {
  // Upstash Redis REST: /pipeline  (Array von ["CMD","arg1","arg2"...])
  const res = await fetch(`${BASE}/pipeline`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(cmds),
  });
  if (!res.ok) {
    const txt = await res.text().catch(() => '');
    throw new Error(`[upstash] HTTP ${res.status}: ${txt}`);
  }
  return res.json(); // [{result: ...}, ...]
}

export async function redisGet(key) {
  const out = await callPipeline([["GET", key]]);
  return out?.[0]?.result ?? null;
}

export async function redisMGet(keys = []) {
  if (!keys.length) return [];
  const out = await callPipeline([["MGET", ...keys]]);
  return out?.[0]?.result ?? [];
}

export async function redisScanAll(match, count = 1000) {
  // Vollständiger SCAN (cursor-basiert)
  let cursor = "0";
  const keys = [];
  do {
    const resp = await callPipeline([["SCAN", cursor, "MATCH", match, "COUNT", String(count)]]);
    const r = resp?.[0]?.result;
    if (!r) break;
    cursor = r[0];            // neuer Cursor
    const batch = r[1] || []; // Keys
    for (const k of batch) keys.push(k);
  } while (cursor !== "0");
  return keys;
}
