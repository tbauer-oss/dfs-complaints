// api/_lib/complaintsStore.js
export const config = { runtime: 'nodejs' };

import { Redis } from '@upstash/redis';

// ---- Upstash / Redis – ENV Varianten ----
const redisUrl   = process.env.REDIS_URL || process.env.UPSTASH_REDIS_REST_URL || '';
const redisToken = process.env.REDIS_TOKEN || process.env.UPSTASH_REDIS_REST_TOKEN || '';

const redis = (redisUrl && redisToken) ? new Redis({ url: redisUrl, token: redisToken }) : null;
if (!redis) console.warn('[complaintsStore] Redis not configured!');

const PFX = 'dfs:';

// ⚠️ Passe diese Keys an, falls du andere Namen verwendest
const SET_ALL_TICKETS = `${PFX}complaints:all`;               // Set aller Ticket-IDs
const KEY_COMPLAINT   = (ticket) => `${PFX}complaint:${ticket}`; // Einzel-Objekt

const S = v => (v ?? '').toString().trim();

async function requireRedis() {
  if (!redis) throw new Error('redis not configured');
}

function normalizeComplaint(obj) {
  if (!obj || typeof obj !== 'object') return null;
  // Deck die häufig genutzten Felder ab, ohne die Struktur zu verbiegen
  return {
    ticket:     S(obj.ticket),
    status:     obj.status,                 // Zahl oder String – nicht casten, nur durchreichen
    decision:   S(obj.decision || ''),      // z.B. 'accepted' | 'rejected' | ''
    createdAt:  obj.createdAt || obj.created || null,
    email:      S(obj.email || obj.customerEmail || '').toLowerCase(),
    customerEmail: S(obj.customerEmail || obj.email || '').toLowerCase(),
    payload:    obj.payload || {},
    // alles andere beibehalten
    ...obj,
  };
}

async function _mgetObjects(keys) {
  if (!keys?.length) return [];
  const raw = await redis.mget(...keys);
  return (raw || []).map(normalizeComplaint).filter(Boolean);
}

/**
 * Basishole-Logik:
 * - Holt alle Tickets aus SET_ALL_TICKETS
 * - Lädt die Objekte via MGET
 * - Filtert auf die gegebenen E-Mail-Adressen
 * - Optionaler Statusfilter
 */
export async function listComplaintsForRepEmails(emails, { status } = {}) {
  await requireRedis();
  const needles = new Set((emails || []).map(e => S(e).toLowerCase()));
  if (!needles.size) return [];

  const tickets = await redis.smembers(SET_ALL_TICKETS);
  if (!tickets?.length) return [];

  const items = await _mgetObjects(tickets.map(KEY_COMPLAINT));
  let filtered = items.filter(c => needles.has(S(c.customerEmail || c.email)));

  // ---- Statusfilter (optional) ----
  // status kann sein:
  // - 'open'  -> offene anzeigen (status != 6 UND decision != 'rejected')
  // - 'all'   -> keine Filterung
  // - '6' oder '1,2,3' -> numerische Status erlauben
  const st = S(status).toLowerCase();

  if (st && st !== 'all') {
    if (st === 'open') {
      filtered = filtered.filter(c => {
        const s = Number(c.status ?? 0);
        const d = S(c.decision).toLowerCase();
        const closed = (s === 6) || (d === 'rejected');
        return !closed;
      });
    } else if (/^\d+(,\d+)*$/.test(st)) {
      const allowed = new Set(st.split(',').map(x => Number(S(x))));
      filtered = filtered.filter(c => allowed.has(Number(c.status ?? -1)));
    }
  }

  // optional etwas limitieren/sortieren (neueste zuerst)
  filtered.sort((a, b) => String(b.createdAt || '').localeCompare(String(a.createdAt || '')));
  return filtered;
}

/**
 * Alias, den dein /api/rep/complaints.js zuerst versucht aufzurufen
 * (API ist identisch; nutzt intern listComplaintsForRepEmails)
 */
export async function getComplaintsByEmails(emails, { status } = {}) {
  return await listComplaintsForRepEmails(emails, { status });
}
