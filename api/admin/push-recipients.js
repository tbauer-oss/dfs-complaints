// api/admin/push-recipients.js
export const config = { runtime: 'nodejs' };

import {
  setCors,
  handlePreflight,
  ok,
  bad,
  methodNotAllowed,
} from '../_lib/http.js';
import { usersList } from '../_lib/store.js';
import { getAllRepIds, loadRepById } from '../_lib/repsStore.js';
import { requirePortalAccess } from './_guard.js';

const MAX_LIMIT = 200;

function normalizeQuery(value) {
  const raw = (value || '').toString().trim().toLowerCase();
  return raw.length ? raw : '';
}

function pickFirst(...values) {
  for (const value of values) {
    const text = (value ?? '').toString().trim();
    if (text) return text;
  }
  return '';
}

function matchesQuery(query, ...fields) {
  if (!query) return true;
  return fields.some((field) => (field || '').toString().toLowerCase().includes(query));
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { write: true, tile: 'push' });
  if (!actor) return;

  if (req.method !== 'GET') {
    return methodNotAllowed(res);
  }

  const type = (req.query?.type || '').toString().trim().toLowerCase();
  const query = normalizeQuery(req.query?.query);
  const limit = Math.min(
    MAX_LIMIT,
    Math.max(1, Number.parseInt(req.query?.limit ?? `${MAX_LIMIT}`, 10) || MAX_LIMIT),
  );

  if (type !== 'customer' && type !== 'rep') {
    return bad(res, 'type invalid', 400);
  }

  try {
    const items = [];

    if (type === 'customer') {
      const users = await usersList();
      for (const user of users) {
        const email = (user?.email || '').toString().trim().toLowerCase();
        if (!email) continue;
        const displayName = pickFirst(
          user?.displayName,
          user?.name,
          user?.fullName,
          user?.contactName,
          user?.contactPerson,
          user?.contact,
          user?.company,
          email,
        );
        const company = pickFirst(user?.company, user?.firma, user?.practice, user?.business);
        if (!matchesQuery(query, displayName, email, company)) continue;
        items.push({
          id: email,
          displayName,
          email,
          company,
        });
        if (items.length >= limit) break;
      }
    } else {
      const ids = await getAllRepIds();
      for (const id of ids) {
        const rep = await loadRepById(id).catch(() => null);
        if (!rep) continue;
        const email = (rep.email || '').toString().trim().toLowerCase();
        const displayName = pickFirst(
          [rep.firstName, rep.lastName].filter(Boolean).join(' ').trim(),
          rep.name,
          rep.fullName,
          rep.displayName,
          email,
          rep.id,
        );
        const company = pickFirst(rep.company, rep.region);
        if (!matchesQuery(query, displayName, email, company)) continue;
        items.push({
          id: rep.id,
          displayName,
          email,
          company,
        });
        if (items.length >= limit) break;
      }
    }

    return ok(res, { items });
  } catch (err) {
    console.error('[admin/push-recipients] error', err);
    return bad(res, 'internal error', 500);
  }
}
