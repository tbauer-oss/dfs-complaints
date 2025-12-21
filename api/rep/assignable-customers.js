export const config = { runtime: 'nodejs' };

import { setCors } from '../_lib/cors.js';
import { getRepFromAuthHeader } from '../_lib/repAuth.js';
import { redisScanAll, redisGet, redisMGet } from '../_lib/upstash.js';

function S(v) { return (v ?? '').toString().trim(); }
const EMAIL_FROM_USER_KEY = (k) => k.slice('dfs:user:'.length); // "dfs:user:<email>"

export default async function handler(req, res) {
  // --- CORS immer zuerst ---
  setCors(req, res, 'Content-Type, Authorization, X-Gate');
  if (req.method === 'OPTIONS') return res.status(204).end();

  if (req.method !== 'GET') {
    return res.status(405).end(JSON.stringify({ error: 'method not allowed' }));
  }

  // --- Auth: Vertreter ermitteln ---
  let auth = null;
  try { auth = getRepFromAuthHeader(req); } catch (e) {}
  if (!auth?.repId) {
    return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));
  }
  const repId = auth.repId.toString();

  // --- Parameter ---
  const showAll = (req.query?.all || '').toString() === '1';

  try {
    // 1) Alle Kundenkeys holen
    const userKeys = await redisScanAll('dfs:user:*', 1000); // -> ["dfs:user:a@b.de", ...]
    if (!Array.isArray(userKeys) || userKeys.length === 0) {
      return res.status(200).end(JSON.stringify([]));
    }

    // 2) Für alle Emails repOf prüfen (mit und ohne Doppelpunkt)
    const emails = userKeys.map(EMAIL_FROM_USER_KEY); // ["a@b.de", ...]
    const repOfColonKeys = emails.map(e => `dfs:repOf:${e.toLowerCase()}`);
    const repOfNoColonKeys = emails.map(e => `dfs:repOf${e.toLowerCase()}`);

    const [repOfColonVals, repOfNoColonVals] = await Promise.all([
      redisMGet(repOfColonKeys),      // gleiche Reihenfolge
      redisMGet(repOfNoColonKeys),
    ]);

    // 3) Zusammenbauen & filtern
    const out = [];
    for (let i = 0; i < emails.length; i++) {
      const email = emails[i].toLowerCase();

      // Normalisiere repOf: first non-empty wins (":email" bevorzugt)
      const repOf = S(repOfColonVals?.[i]) || S(repOfNoColonVals?.[i]); // "rep_2" oder ""

      // assigned?
      const isAssigned = !!repOf;

      // Wenn nur freie Kunden gewünscht → skip zugewiesene
      if (!showAll && isAssigned) continue;

      // 4) Basisobjekt
      const item = {
        email,
        name: email,     // wird später ggf. aus dfs:user:<email> ersetzt
        company: '',     // dto.
        label: email,    // fallback (UI-freundlich)
        assigned: isAssigned,
        assignedTo: '',
        assignedToEmail: '',
        assignedToName: '',
      };

      // 5) Wenn zugewiesen → reps:<id> anreichern
      if (isAssigned) {
        item.assignedTo = repOf;
        const repJson = await redisGet(`dfs:reps:${repOf}`);
        if (repJson) {
          try {
            const repObj = JSON.parse(repJson);
            const rMail = S(repObj.email);
            const rName = [S(repObj.firstName), S(repObj.lastName)].filter(Boolean).join(' ').trim();
            item.assignedToEmail = rMail;
            item.assignedToName  = rName || rMail || repOf;
          } catch {}
        }
      }

      // 6) Kunden-Details (Name/Firma) für hübsches Label
      const userJson = await redisGet(`dfs:user:${email}`);
      if (userJson) {
        try {
          const u = JSON.parse(userJson);
          const company = S(u.companyName || u.company || u.org);
          const first   = S(u.firstName);
          const last    = S(u.lastName);
          const full    = S(`${first} ${last}`);
          const display = company || S(u.contactName || u.name || full) || email;
          item.company  = company;
          item.name     = display;
          item.label    = company || `${display} • ${email}`;
        } catch {}
      }

      out.push(item);
    }

    // 7) Sortierung: zuerst frei, dann Name/Company
    out.sort((a, b) => {
      if (a.assigned !== b.assigned) return a.assigned ? 1 : -1;
      return a.label.toLowerCase().localeCompare(b.label.toLowerCase());
    });

    return res.status(200).end(JSON.stringify(out));
  } catch (e) {
    console.error('[rep/assignable-customers] error:', e);
    // Stabil bleiben
    return res.status(200).end(JSON.stringify([]));
  }
}
