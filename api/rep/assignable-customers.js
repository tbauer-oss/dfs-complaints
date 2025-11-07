// /api/rep/assignable-customers.js
// Vercel (Node.js) – Upstash KV angebunden, robust & CORS-fähig

const ALLOWED_ORIGIN = process.env.ALLOWED_ORIGIN || '*';
const ADMIN_SECRET   = process.env.ADMIN_SECRET || '';

/** ---------- CORS Helper ---------- */
function setCors(res) {
  res.setHeader('Access-Control-Allow-Origin', ALLOWED_ORIGIN);
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers',
    'Content-Type, Authorization, X-Gate, X-Admin-Secret');
  res.setHeader('Access-Control-Max-Age', '600');
}
function send(res, code, body) {
  setCors(res);
  res.statusCode = code;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.end(JSON.stringify(body));
}
function ok(res, body)  { send(res, 200, body); }
function bad(res, c, m) { send(res, c, { error: m }); }

/** ---------- Upstash KV (REST) ---------- */
const KV_URL   = process.env.UPSTASH_REDIS_REST_URL;
const KV_TOKEN = process.env.UPSTASH_REDIS_REST_TOKEN;

async function kvCmd(cmd) {
  // POST { "cmd": ["SCAN", "0", "MATCH", "dfs:user:*", "COUNT", "1000"] }
  const r = await fetch(KV_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${KV_TOKEN}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ cmd })
  });
  if (!r.ok) {
    const t = await r.text().catch(()=>'');
    throw new Error(`Upstash error ${r.status}: ${t||r.statusText}`);
  }
  return r.json();
}

// Vollständiges SCAN über ein Pattern (holt alle Seiten)
async function kvScanAll(pattern, count = 1000) {
  const keys = [];
  let cursor = '0';
  do {
    const { result } = await kvCmd(['SCAN', cursor, 'MATCH', pattern, 'COUNT', String(count)]);
    cursor = result[0];
    const batch = result[1] || [];
    keys.push(...batch);
  } while (cursor !== '0');
  return keys;
}
async function kvMGet(keys) {
  if (!keys.length) return [];
  const { result } = await kvCmd(['MGET', ...keys]);
  return result;
}

/** ---------- Datenquellen-Mapping ----------
 * Kunden:    Keys  dfs:user:*          (JSON, enthält "email","company","name", …)
 * Zuweisung: Keys  dfs:repOf<email>    → Value = Vertreter-E-Mail
 * (Beispiele siehst du im Screenshot: dfs:user:… , dfs:repOfdancinlutin@web.de)
 * ----------------------------------------- */

function buildLabel(user) {
  const em = (user.email || '').toLowerCase();
  const co = (user.company || '').trim();
  const nm = (user.name || '').trim();
  return co || (nm ? `${nm} • ${em}` : em);
}

function isActiveCustomer(user) {
  // konservativ: nur aktive, nicht widerrufene Datensätze
  if (!user || typeof user !== 'object') return false;
  const em = (user.email || '').toString().toLowerCase();
  if (!em) return false;
  const status = (user.status || '').toString().toLowerCase();
  const revoked = Boolean(user.revoked);
  // optional: nur Einträge mit Firma sinnvoll
  // const hasCompany = (user.company || '').toString().trim().length > 0;
  return status === 'active' && !revoked; // && hasCompany;
}

async function loadAllCustomersFromKV() {
  // alle Kundenobjekte aus dfs:user:*
  const keys = await kvScanAll('dfs:user:*');
  if (!keys.length) return [];

  const raw = await kvMGet(keys);
  const out = [];
  for (const v of raw) {
    if (!v) continue;
    let obj = null;
    try { obj = typeof v === 'string' ? JSON.parse(v) : v; } catch (_) {}
    if (!obj) continue;
    if (!isActiveCustomer(obj)) continue;

    out.push({
      email: String(obj.email || '').toLowerCase(),
      company: String(obj.company || ''),
      name: String(obj.name || obj.contact || ''), // kleine Toleranz
    });
  }
  // Eindeutig nach E-Mail
  const dedup = new Map();
  for (const c of out) dedup.set(c.email, c);
  return Array.from(dedup.values());
}

async function loadAssignmentsFromKV() {
  // Zuweisungen in Keys dfs:repOf<email>  →  value = repEmail
  const keys = await kvScanAll('dfs:repOf*');
  if (!keys.length) return {};
  const vals = await kvMGet(keys);
  const map = {};
  for (let i = 0; i < keys.length; i++) {
    const k = keys[i];
    const v = vals[i];
    const email = k.replace(/^dfs:repOf/i, '').toLowerCase();
    const rep   = (v || '').toString().toLowerCase();
    if (email) map[email] = rep || null;
  }
  return map;
}

/** ---------- Admin-Check ---------- */
function isAdmin(req) {
  const s = req.headers['x-admin-secret'] || req.headers['X-Admin-Secret'];
  return ADMIN_SECRET && s === ADMIN_SECRET;
}

/** ---------- Handler ---------- */
module.exports = async function handler(req, res) {
  try {
    setCors(res);
    if (req.method === 'OPTIONS') { res.statusCode = 204; return res.end(); }
    if (req.method !== 'GET')     { return bad(res, 405, 'Method Not Allowed'); }

    const wantAdminView = isAdmin(req); // Admin wie im Adminbereich

    // Laden (robust; niemals 500 auf leere Datensätze)
    let customers = [];
    let assigned  = {};
    try { customers = await loadAllCustomersFromKV(); } catch (_) {}
    try { assigned  = await loadAssignmentsFromKV();   } catch (_) {}

    // Liste formen
    const list = customers.map((c) => {
      const ass = assigned[c.email] || null;
      return {
        email: c.email,
        company: c.company,
        name: c.name,
        label: buildLabel(c),
        assigneeEmail: ass,   // null = frei
        assigneeName: null,   // optional, wenn du Namen der Reps auflösen willst
      };
    });

    // Sortiert zurück (de, case-insensitive)
    list.sort((a, b) => a.label.toLowerCase().localeCompare(b.label.toLowerCase(), 'de'));

    if (wantAdminView) {
      // Admin: komplette Liste inkl. assignee (grau/disabled im UI)
      return ok(res, list);
    } else {
      // Vertreter/Public: nur freie Kunden zeigen
      const free = list.filter((x) => !x.assigneeEmail);
      return ok(res, free);
    }
  } catch (e) {
    return bad(res, 500, (e && e.message) ? e.message : String(e));
  }
};
