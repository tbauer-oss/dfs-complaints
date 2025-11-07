// /api/rep/assignable-customers.js
// Vercel (Node.js) API Route – JS only, robust gegen 500er

const ALLOWED_ORIGIN = process.env.ALLOWED_ORIGIN || '*'; // z. B. https://dfs-complaints-web.vercel.app

// ---------- CORS ----------
function setCors(res) {
  res.setHeader('Access-Control-Allow-Origin', ALLOWED_ORIGIN);
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Gate, X-Admin-Secret');
  res.setHeader('Access-Control-Max-Age', '600');
}
function ok(res, body) {
  setCors(res);
  res.setHeader('Cache-Control', 'no-store');
  res.statusCode = 200;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify(body));
}
function bad(res, code, msg) {
  setCors(res);
  res.setHeader('Cache-Control', 'no-store');
  res.statusCode = code;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify({ error: msg }));
}

// ---------- Auth-Stub (bitte mit echter JWT/Session ersetzen) ----------
async function getRepFromAuth(req) {
  try {
    const auth = req.headers['authorization'] || req.headers['Authorization'] || '';
    if (typeof auth !== 'string' || !auth.startsWith('Bearer ')) return null;
    const token = auth.slice(7).trim();
    if (!token) return null;

    // TODO: hier echte Verifikation (z. B. jwt.verify) + E-Mail extrahieren
    const repEmail = await fakeVerifyAndExtractRepEmail(token);
    return repEmail ? { email: repEmail.toLowerCase() } : null;
  } catch (_) {
    return null;
  }
}

// Fake-Verifikation → immer null (kein Crash). Bitte ersetzen.
async function fakeVerifyAndExtractRepEmail(_token) {
  return null;
}

// ---------- Datenzugänge (BITTE anbinden) ----------
async function loadAllCustomers() {
  // Erwartet: [{ email, company?, name? }, ...]
  // TODO: DB/KV/API anbinden.
  // Beispiel-Dummies, bis echte Quelle verdrahtet ist:
  return [
    // { email: 'kundex@y.example', company: 'Kunde X GmbH', name: 'Max Mustermann' },
    // { email: 'kundey@y.example', company: 'Kunde Y AG',   name: 'Erika Beispiel' },
  ];
}

async function loadAssignments() {
  // Erwartet: { 'customer@email': 'rep@email', ... }
  // TODO: DB/KV/API anbinden.
  // Beispiel: return { 'kundex@y.example': 'rep1@firma.de' };
  return {};
}

// ---------- Label-Helfer ----------
function buildLabel(c) {
  const em = c.email;
  const co = (c.company || '').trim();
  const nm = (c.name || '').trim();
  return co || (nm ? `${nm} • ${em}` : em);
}

// ---------- Handler ----------
module.exports = async function handler(req, res) {
  try {
    setCors(res);

    if (req.method === 'OPTIONS') {
      res.statusCode = 204;
      return res.end();
    }
    if (req.method !== 'GET') {
      return bad(res, 405, 'Method Not Allowed');
    }

    const rep = await getRepFromAuth(req); // null = nicht eingeloggt

    // Beides robust laden (niemals throw nach außen)
    let customers = [];
    let assignedMap = {};
    try {
      customers = await loadAllCustomers();
    } catch (_) {
      customers = [];
    }
    try {
      assignedMap = await loadAssignments();
    } catch (_) {
      assignedMap = {};
    }

    // Normalisieren
    const list = (Array.isArray(customers) ? customers : [])
      .map((c) => ({
        email: String((c && c.email) || '').toLowerCase(),
        company: String((c && c.company) || ''),
        name: String((c && c.name) || ''),
      }))
      .filter((c) => c.email);

    const out = list.map((c) => {
      const assRaw = assignedMap ? assignedMap[c.email] : null;
      const ass = assRaw ? String(assRaw).toLowerCase() : null;
      return {
        email: c.email,
        company: c.company,
        name: c.name,
        label: buildLabel(c),
        assigneeEmail: ass,     // null = frei
        assigneeName: null,     // optional, falls verfügbar
      };
    });

    // Sortierung
    out.sort((a, b) => a.label.toLowerCase().localeCompare(b.label.toLowerCase(), 'de'));

    // Public (ohne Auth): nur freie Kunden
    if (!rep) {
      const freeOnly = out.filter((x) => !x.assigneeEmail);
      return ok(res, freeOnly);
    }

    // Eingeloggt (Rep): alle Kunden inkl. assignee
    return ok(res, out);
  } catch (e) {
    const msg = (e && e.message) ? e.message : String(e);
    return bad(res, 500, `assignable-customers failed: ${msg}`);
  }
};
