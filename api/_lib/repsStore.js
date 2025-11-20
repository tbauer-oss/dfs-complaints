// api/_lib/repsStore.js
export const config = { runtime: 'nodejs' };

import { Redis } from '@upstash/redis';

// ---- Upstash / Redis – ENV akzeptieren mehrere Varianten ----
const redisUrl =
  process.env.REDIS_URL ||
  process.env.UPSTASH_REDIS_REST_URL ||
  '';
const redisToken =
  process.env.REDIS_TOKEN ||
  process.env.UPSTASH_REDIS_REST_TOKEN ||
  '';

const REDIS_TIMEOUT_MS = Math.max(0, Number(process.env.REDIS_TIMEOUT_MS || 2500));

if (!redisUrl || !redisToken) {
  console.warn('[repsStore] Redis not configured (set REDIS_URL/REDIS_TOKEN or UPSTASH_* envs).');
}

const redis = (redisUrl && redisToken)
  ? new Redis({ url: redisUrl, token: redisToken })
  : null;

// ---- Keys / Indizes ----
const PFX     = 'dfs:';                               // Projekt-Prefix
const SET_ALL = `${PFX}reps:all`;                     // Set aller Rep-IDs
const CNT     = `${PFX}reps:counter`;                 // Zähler für IDs
const KEY     = (id)      => `${PFX}reps:${id}`;      // Rep-Objekt
const IDX_E   = (email)   => `${PFX}repBy:${email.toLowerCase()}`; // email -> repId (alte Logik)
const SET_CUS = (repId)   => `${PFX}rep:${repId}:customers`;       // Set Kunden-Emails eines Reps
const IDX_ROF = (email)   => `${PFX}repOf:${email.toLowerCase()}`; // customerEmail -> repId (Reverse-Mapping)

// ---- Helpers ----
const S = (v) => (v ?? '').toString().trim();
const nowIso = () => new Date().toISOString();

const SUPPORTED_LANGS = new Set(['de', 'en', 'fr', 'it', 'es']);

const normalizeLang = (value, fallback = '') => {
  const lc = S(value).toLowerCase();
  if (SUPPORTED_LANGS.has(lc)) return lc;
  const fb = S(fallback).toLowerCase();
  return SUPPORTED_LANGS.has(fb) ? fb : '';
};

async function requireRedis() {
  if (!redis) {
    throw new Error('redis not configured (REDIS_URL/REDIS_TOKEN or UPSTASH_REDIS_REST_URL/UPSTASH_REDIS_REST_TOKEN)');
  }
}

async function redisWithTimeout(promise, label = 'redis op') {
  if (!REDIS_TIMEOUT_MS) return await promise;
  return await Promise.race([
    promise,
    new Promise((_, reject) => {
      setTimeout(() => {
        const err = new Error(`${label} timed out after ${REDIS_TIMEOUT_MS}ms`);
        err.code = 'REDIS_TIMEOUT';
        reject(err);
      }, REDIS_TIMEOUT_MS);
    }),
  ]);
}

async function redisCall(op, ...args) {
  await requireRedis();
  const fn = redis?.[op];
  if (typeof fn !== 'function') {
    throw new Error(`redis operation not supported: ${op}`);
  }
  return await redisWithTimeout(fn.apply(redis, args), `redis ${op}`);
}

// Defaults/Normalisierung für gespeicherte Rep-Objekte
function normalizeRep(rep) {
  if (!rep || typeof rep !== 'object') return null;

  const pick = (...values) => {
    for (const v of values) {
      const str = S(v);
      if (str) return str;
    }
    return '';
  };

  const id = pick(rep.id, rep.repId);

  let firstName = pick(rep.firstName, rep.firstname, rep.first_name);
  let lastName  = pick(rep.lastName, rep.lastname, rep.last_name, rep.surname);
  const fullName = pick(rep.name, rep.fullName, rep.displayName, rep.label);

  if (fullName) {
    const parts = fullName.split(/\s+/).filter(Boolean);
    if (!firstName && parts.length) {
      firstName = parts.shift() || '';
    }
    if (!lastName && parts.length) {
      lastName = parts.join(' ');
    }
    if (!firstName && !lastName) {
      firstName = fullName;
    }
  }

  const email = pick(
    rep.email,
    rep.mail,
    rep.emailAddress,
    rep.email_address,
    rep.user?.email,
    rep.contact?.email,
  ).toLowerCase();

  const region = pick(rep.region, rep.area, rep.territory, rep.regionName, rep.regions);
  const lang = normalizeLang(pick(rep.lang, rep.language, rep.locale, rep.langCode));

  return {
    id,
    firstName,
    lastName,
    email,
    region,
    lang,
    passHash: rep.passHash || null,
    mustChangePw: !!rep.mustChangePw,
    active: (rep.active === undefined ? true : !!rep.active),
    createdAt: rep.createdAt || null,
    updatedAt: rep.updatedAt || null,
  };
}

// ---- Low-level: IDs / Laden / Speichern ----
async function nextId() {
  const n = await redisCall('incr', CNT);
  return `rep_${String(n)}`;
}

export async function loadRepById(id) {
  if (!id) return null;
  const raw = await redisCall('get', KEY(id));
  return normalizeRep(raw);
}

export async function loadRepIdByEmail(email) {
  email = S(email).toLowerCase();
  if (!email) return null;
  const repId = await redisCall('get', IDX_E(email));
  return repId || null;
}

// ✅ NEU: unterstützt beide Varianten – dfs:repBy:<email> UND dfs:reps:email:<email>
export async function loadRepByEmail(email) {
  await requireRedis();
  email = S(email).toLowerCase();
  if (!email) return null;

  // Versuche alten Index zuerst (Standard)
  const idByOldIndex = await redisCall('get', `${PFX}repBy:${email}`);
  // Neue Keystruktur (dein aktueller Upstash-Stand)
  const idByNewIndex = await redisCall('get', `${PFX}reps:email:${email}`);

  let id = idByOldIndex || idByNewIndex;

  // Wenn ID fehlt, prüfen, ob direkt ein Objekt unter dfs:reps:email:<addr> liegt
  if (!id) {
    const repDirect = await redisCall('get', `${PFX}reps:email:${email}`);
    if (repDirect && repDirect.id) return normalizeRep(repDirect);
    return null;
  }

  const rep = await loadRepById(id);
  return normalizeRep(rep);
}

export async function repCustomers(repId) {
  const list = await redisCall('smembers', SET_CUS(repId));
  return Array.isArray(list) ? list : [];
}

async function saveRep(repObj) {
  const rep = normalizeRep(repObj);
  if (!rep || !rep.id) throw new Error('invalid rep in saveRep');

  await redisCall('set', KEY(rep.id), rep);
  await redisCall('sadd', SET_ALL, rep.id);

  // Email-Index setzen (alte Struktur)
  if (rep.email) {
    await redisCall('set', IDX_E(rep.email), rep.id);
  }
  return rep;
}

// ---- Public API ----

export async function getAllRepIds() {
  const ids = await redisCall('smembers', SET_ALL);
  return Array.isArray(ids) ? ids : [];
}

export async function getAllRepsWithCustomers() {
  const ids = await getAllRepIds();
  if (!ids?.length) return [];

  const keys = ids.map((id) => KEY(id));
  const repsRaw = await redisCall('mget', ...keys);
  const reps = (repsRaw || []).map(normalizeRep).filter(Boolean);

  const withCus = await Promise.all(reps.map(async (r) => {
    const list = await repCustomers(r.id);
    return { ...r, customers: list || [] };
  }));

  return withCus;
}

export async function upsertRep({ id, firstName, lastName, email, region, lang, active }) {
  await requireRedis();

  firstName = S(firstName);
  lastName  = S(lastName);
  email     = S(email).toLowerCase();
  region    = S(region);
  lang      = normalizeLang(lang);
  const activeFlag = (active === undefined ? true : !!active);

  if (!firstName || !lastName || !email || !region) {
    throw new Error('missing fields for upsertRep');
  }

  let rep = null;
  let repId = S(id);

  if (repId) {
    rep = await loadRepById(repId);
  }
  if (!rep) {
    const viaEmailId = await loadRepIdByEmail(email);
    if (viaEmailId) {
      repId = viaEmailId;
      rep   = await loadRepById(repId);
    }
  }

  if (rep) {
    const prevEmail = S(rep.email).toLowerCase();
    const updated = normalizeRep({
      ...rep,
      firstName,
      lastName,
      email,
      region,
      lang: normalizeLang(lang, rep.lang),
      active: activeFlag,
      passHash: rep.passHash ?? null,
      mustChangePw: (rep.mustChangePw === undefined ? false : !!rep.mustChangePw),
      updatedAt: nowIso(),
    });

    if (prevEmail && prevEmail !== email) {
      await redisCall('del', IDX_E(prevEmail));
    }
    const saved = await saveRep(updated);
    const customers = await repCustomers(saved.id);
    return { ...saved, customers: customers || [] };
  } else {
    const newId = await nextId();
    const created = normalizeRep({
      id: newId,
      firstName,
      lastName,
      email,
      region,
      lang: normalizeLang(lang, 'de'),
      passHash: null,
      mustChangePw: true,
      active: activeFlag,
      createdAt: nowIso(),
      updatedAt: nowIso(),
    });
    const saved = await saveRep(created);
    return { ...saved, customers: [] };
  }
}

export async function deleteRep(id) {
  await requireRedis();
  id = S(id);
  if (!id) return;

  const rep = await loadRepById(id);
  const customers = await repCustomers(id);
  if (customers?.length) {
    const jobs = [];
    for (const mail of customers) {
      const key = IDX_ROF(mail);
      jobs.push(redisCall('del', key));
    }
    await Promise.all(jobs);
  }

  if (rep?.email) {
    await redisCall('del', IDX_E(S(rep.email).toLowerCase()));
  }
  await redisCall('del', SET_CUS(id));
  await redisCall('del', KEY(id));
  await redisCall('srem', SET_ALL, id);
}

export async function assignCustomer(repId, email) {
  await requireRedis();
  repId = S(repId);
  email = S(email).toLowerCase();
  if (!repId || !email) throw new Error('missing repId or email');

  // Exklusiver Index: customerEmail -> repId
  const key = IDX_ROF(email);

  // 1) Exklusiv belegen (nur wenn noch nicht vorhanden)
  //    - bei Erstzuweisung: OK
  //    - wenn schon vorhanden: kein OK → prüfen, wem es gehört
  const nx = await redisCall('set', key, repId, { nx: true });
  if (nx !== 'OK') {
    const current = await redisCall('get', key);

    if (current && current !== repId) {
      // Bereits einem anderen Vertreter zugeordnet → HARTE Sperre
      const err = new Error('customer already assigned to another rep');
      err.statusCode = 409; // damit dein Route-Handler sauber 409 senden kann
      throw err;
    }
    // Idempotent: current === repId → weiter (kein Fehler)
  }

  // 2) Kundenliste des Reps aktualisieren (Set nutzen, sortieren)
  //    (wir fassen keinen Fremd-Rep an – das ist Absicht!)
  await redisCall('sadd', SET_CUS(repId), email);

  // 3) Ergebnisliste (geordnet) zurückgeben
  const list = await repCustomers(repId);
  const sorted = (list || []).map(String).sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase(), 'de'));
  return sorted;
}

export async function unassignCustomer(repId, email) {
  await requireRedis();
  repId = S(repId);
  email = S(email).toLowerCase();
  if (!repId || !email) throw new Error('missing repId or email');

  const key = IDX_ROF(email);
  const current = await redisCall('get', key);

  if (current === repId) {
    await redisCall('del', key);
  }

  await redisCall('srem', SET_CUS(repId), email);
  const list = await repCustomers(repId);
  const sorted = (list || []).map(String).sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase(), 'de'));
  return sorted;
}

export async function getRepOf(email) {
  await requireRedis();
  email = S(email).toLowerCase();
  if (!email) return null;
  const repId = await redisCall('get', IDX_ROF(email));
  if (!repId) return null;
  const rep = await loadRepById(repId);
  return rep || null;
}

// --- Passwort-Management ---
export async function setRepPassword(repId, passHash, mustChange = false) {
  await requireRedis();
  repId = S(repId);
  if (!repId || !passHash) throw new Error('missing repId or passHash');

  const rep = await loadRepById(repId);
  if (!rep) throw new Error('rep not found');

  const updated = normalizeRep({
    ...rep,
    passHash,
    mustChangePw: !!mustChange,
    updatedAt: nowIso(),
  });
  const saved = await saveRep(updated);
  const customers = await repCustomers(repId);
  return { ...saved, customers: customers || [] };
}

export async function updateRepPassword(repId, newHash) {
  return await setRepPassword(repId, newHash, false);
}

export async function setRepActive(repId, isActive) {
  await requireRedis();
  repId = S(repId);
  const rep = await loadRepById(repId);
  if (!rep) throw new Error('rep not found');

  const updated = normalizeRep({
    ...rep,
    active: !!isActive,
    updatedAt: nowIso(),
  });
  const saved = await saveRep(updated);
  const customers = await repCustomers(repId);
  return { ...saved, customers: customers || [] };
}

export async function repAssign(repId, email) {
  return await assignCustomer(repId, email);
}

export async function repUnassign(repId, email) {
  return await unassignCustomer(repId, email);
}
