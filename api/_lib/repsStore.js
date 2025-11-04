// api/_lib/repsStore.js

// === Variante A: Vercel KV (empfohlen, falls vorhanden) ===================
// import { kv } from '@vercel/kv';
// const KEY = 'dfs:reps:v1';

// async function loadAll() { return (await kv.get(KEY)) || []; }
// async function saveAll(list) { await kv.set(KEY, list); }

// === Variante B: Upstash Redis REST (häufig im Projekt vorhanden) =========
const BASE = process.env.UPSTASH_REDIS_REST_URL;
const TOKEN = process.env.UPSTASH_REDIS_REST_TOKEN;
const KEY = 'dfs:reps:v1';

async function _redisFetch(body) {
  if (!BASE || !TOKEN) throw new Error('Upstash Redis not configured');
  const r = await fetch(BASE, {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${TOKEN}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!r.ok) throw new Error(`Upstash error: ${r.status}`);
  const j = await r.json();
  return j;
}

async function loadAll() {
  if (!BASE || !TOKEN) return []; // Fallback: leer (Dev)
  const j = await _redisFetch({ op: ['GET', KEY] });
  const raw = j?.result;
  if (!raw) return [];
  try { return JSON.parse(raw); } catch { return []; }
}

async function saveAll(list) {
  if (!BASE || !TOKEN) return; // Fallback: no-op (Dev)
  await _redisFetch({ op: ['SET', KEY, JSON.stringify(list)] });
}

// ==================== Normalizer & Helpers ====================
const norm = s => (s || '').toString().trim();
const normLower = s => norm(s).toLowerCase();

function sanitize(rep) {
  return {
    id: norm(rep.id || rep.email || ''),
    firstName: norm(rep.firstName),
    lastName:  norm(rep.lastName),
    email:     norm(rep.email),
    region:    norm(rep.region),
    customers: Array.isArray(rep.customers)
      ? [...new Set(rep.customers.map(normLower))] // uniq + lower
      : [],
  };
}

// ==================== Public API ==============================

export async function getAllRepsWithCustomers() {
  const list = await loadAll();
  return list.map(sanitize);
}

export async function upsertRep({ id, firstName, lastName, email, region }) {
  const list = await loadAll();
  const repId = norm(id || email);
  let idx = list.findIndex(r => norm(r.id) === repId);
  if (idx < 0) {
    list.push(sanitize({ id: repId, firstName, lastName, email, region, customers: [] }));
  } else {
    const cur = list[idx];
    list[idx] = sanitize({
      id: repId,
      firstName: firstName ?? cur.firstName,
      lastName:  lastName  ?? cur.lastName,
      email:     email     ?? cur.email,
      region:    region    ?? cur.region,
      customers: cur.customers || [],
    });
  }
  await saveAll(list);
  return list.find(r => norm(r.id) === repId);
}

export async function deleteRep(id) {
  const list = await loadAll();
  const repId = norm(id);
  const next = list.filter(r => norm(r.id) !== repId);
  await saveAll(next);
}

export async function assignCustomer(repId, email) {
  const list = await loadAll();
  const rid = norm(repId);
  const eml = normLower(email);
  const idx = list.findIndex(r => norm(r.id) === rid);
  if (idx < 0) throw new Error('rep not found');
  const set = new Set((list[idx].customers || []).map(normLower));
  set.add(eml);
  list[idx].customers = [...set];
  await saveAll(list);
  return list[idx].customers;
}

export async function unassignCustomer(repId, email) {
  const list = await loadAll();
  const rid = norm(repId);
  const eml = normLower(email);
  const idx = list.findIndex(r => norm(r.id) === rid);
  if (idx < 0) throw new Error('rep not found');
  list[idx].customers = (list[idx].customers || [])
    .map(normLower)
    .filter(e => e !== eml);
  await saveAll(list);
  return list[idx].customers;
}
