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

if (!redisUrl || !redisToken) {
  // Wir exportieren trotzdem Funktionen, werfen aber konsistente Errors
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
const IDX_E   = (email)   => `${PFX}repBy:${email.toLowerCase()}`; // email -> repId
const SET_CUS = (repId)   => `${PFX}rep:${repId}:customers`;       // Set Kunden-Emails eines Reps
const IDX_ROF = (email)   => `${PFX}repOf:${email.toLowerCase()}`; // customerEmail -> repId (Reverse-Mapping)

// ---- Helpers ----
const S = (v) => (v ?? '').toString().trim();
const nowIso = () => new Date().toISOString();

async function requireRedis() {
  if (!redis) {
    throw new Error('redis not configured (REDIS_URL/REDIS_TOKEN or UPSTASH_REDIS_REST_URL/UPSTASH_REDIS_REST_TOKEN)');
  }
}

// Defaults/Normalisierung für gespeicherte Rep-Objekte
function normalizeRep(rep) {
  if (!rep || typeof rep !== 'object') return null;
  return {
    id: S(rep.id),
    firstName: S(rep.firstName),
    lastName:  S(rep.lastName),
    email:     S(rep.email).toLowerCase(),
    region:    S(rep.region),
    passHash:  rep.passHash || null,           // bcrypt Hash oder null
    mustChangePw: !!rep.mustChangePw,          // bool
    active: (rep.active === undefined ? true : !!rep.active), // Default: aktiv
    createdAt: rep.createdAt || null,
    updatedAt: rep.updatedAt || null,
  };
}

// ---- Low-level: IDs / Laden / Speichern ----
async function nextId() {
  await requireRedis();
  const n = await redis.incr(CNT);
  return `rep_${String(n)}`;
}

export async function loadRepById(id) {
  await requireRedis();
  if (!id) return null;
  const raw = await redis.get(KEY(id));
  return normalizeRep(raw);
}

export async function loadRepIdByEmail(email) {
  await requireRedis();
  email = S(email).toLowerCase();
  if (!email) return null;
  const repId = await redis.get(IDX_E(email));
  return repId || null;
}

export async function loadRepByEmail(email) {
  await requireRedis();
  const id = await loadRepIdByEmail(email);
  if (!id) return null;
  return await loadRepById(id);
}

export async function repCustomers(repId) {
  await requireRedis();
  const list = await redis.smembers(SET_CUS(repId));
  return Array.isArray(list) ? list : [];
}

async function saveRep(repObj) {
  await requireRedis();
  const rep = normalizeRep(repObj);
  if (!rep || !rep.id) throw new Error('invalid rep in saveRep');

  await redis.set(KEY(rep.id), rep);
  await redis.sadd(SET_ALL, rep.id);

  // Email-Index setzen
  if (rep.email) {
    await redis.set(IDX_E(rep.email), rep.id);
  }
  return rep;
}

// ---- Public API ----

// IDs aller Reps
export async function getAllRepIds() {
  await requireRedis();
  const ids = await redis.smembers(SET_ALL);
  return Array.isArray(ids) ? ids : [];
}

// Alle Reps inkl. Customers (Admin-Ansicht)
export async function getAllRepsWithCustomers() {
  await requireRedis();
  const ids = await getAllRepIds();
  if (!ids?.length) return [];

  const keys = ids.map((id) => KEY(id));
  const repsRaw = await redis.mget(...keys);
  const reps = (repsRaw || []).map(normalizeRep).filter(Boolean);

  const withCus = await Promise.all(reps.map(async (r) => {
    const list = await repCustomers(r.id);
    return { ...r, customers: list || [] };
  }));

  return withCus;
}

// Erzeugt oder aktualisiert einen Vertreter (Upsert über id ODER email)
// ⚠️ Bei Updates bleiben passHash und mustChangePw erhalten (kein Überschreiben).
export async function upsertRep({ id, firstName, lastName, email, region, active }) {
  await requireRedis();

  firstName = S(firstName);
  lastName  = S(lastName);
  email     = S(email).toLowerCase();
  region    = S(region);
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
    // Update: Email-Wechsel berücksichtigen (Index neu setzen) und Passwortfelder erhalten
    const prevEmail = S(rep.email).toLowerCase();
    const updated = normalizeRep({
      ...rep,
      firstName, lastName, email, region,
      active: activeFlag,
      // Passwort-Felder NICHT überschreiben
      passHash: rep.passHash ?? null,
      mustChangePw: (rep.mustChangePw === undefined ? false : !!rep.mustChangePw),
      updatedAt: nowIso(),
    });

    if (prevEmail && prevEmail !== email) {
      await redis.del(IDX_E(prevEmail));
    }
    const saved = await saveRep(updated);
    const customers = await repCustomers(saved.id);
    return { ...saved, customers: customers || [] };
  } else {
    // Create – ohne Passwort (kommt beim ersten Login mit Einmalpasswort)
    const newId = await nextId();
    const created = normalizeRep({
      id: newId,
      firstName, lastName, email, region,
      passHash: null,
      mustChangePw: true,           // wird erzwungen beim ersten Login
      active: activeFlag,           // Default: aktiv
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

  // Kunden-Umkehrindex bereinigen
  const customers = await repCustomers(id);
  if (customers?.length) {
    const jobs = [];
    for (const mail of customers) {
      const key = IDX_ROF(mail);
      jobs.push(redis.del(key));
    }
    await Promise.all(jobs);
  }

  // Primärdaten & Indizes löschen
  if (rep?.email) {
    await redis.del(IDX_E(S(rep.email).toLowerCase()));
  }
  await redis.del(SET_CUS(id));
  await redis.del(KEY(id));
  await redis.srem(SET_ALL, id);
}

// Kundenzuordnung setzen: customerEmail -> repId & Set pflegen
export async function assignCustomer(repId, email) {
  await requireRedis();
  repId = S(repId);
  email = S(email).toLowerCase();
  if (!repId || !email) throw new Error('missing repId or email');

  // Falls Kunde bereits einem anderen Rep zugeordnet → dort entfernen
  const prevRep = await redis.get(IDX_ROF(email));
  if (prevRep && prevRep !== repId) {
    await redis.srem(SET_CUS(prevRep), email);
  }

  await redis.sadd(SET_CUS(repId), email);
  await redis.set(IDX_ROF(email), repId);

  return await repCustomers(repId);
}

// Kundenzuordnung entfernen (nur wenn Index auf diesen Rep zeigt)
export async function unassignCustomer(repId, email) {
  await requireRedis();
  repId = S(repId);
  email = S(email).toLowerCase();
  if (!repId || !email) throw new Error('missing repId or email');

  await redis.srem(SET_CUS(repId), email);
  const cur = await redis.get(IDX_ROF(email));
  if (cur === repId) {
    await redis.del(IDX_ROF(email));
  }

  return await repCustomers(repId);
}

// Reverse-Lookup: Welcher Rep betreut die Kunden-Email?
export async function getRepOf(email) {
  await requireRedis();
  email = S(email).toLowerCase();
  if (!email) return null;
  const repId = await redis.get(IDX_ROF(email));
  if (!repId) return null;
  const rep = await loadRepById(repId);
  return rep || null;
}

// --- Passwort-Management ---

// Setzt/ändert den Passwort-Hash eines Reps und optional das Pflichtwechsel-Flag.
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

// Alias für deine /api/rep/password.js – kompatibel zu deinem bisherigen Namen
export async function updateRepPassword(repId, newHash) {
  return await setRepPassword(repId, newHash, false);
}

// --- Aktiv-Flag steuern (optional) ---
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