// /api/rep/early-warning.js
export const config = { runtime: 'nodejs' };

import { setCors } from '../_lib/cors.js';
import { getRepFromAuthHeader } from '../_lib/repAuth.js';
import { repCustomers } from '../_lib/repsStore.js';
import { complaintsForRepEmails } from '../_lib/store.js';
import { buildEarlyWarnings } from '../_lib/earlyWarning.js';
import { getProductIndex } from '../_lib/products.js';

export default async function handler(req, res) {
  setCors(req, res, 'Content-Type, Authorization, X-Gate');
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'GET') {
    return res.status(405).end(JSON.stringify({ error: 'method not allowed' }));
  }

  const auth = getRepFromAuthHeader(req);
  if (!auth) {
    return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));
  }

  try {
    const emails = await repCustomers(auth.repId);
    if (!Array.isArray(emails) || emails.length === 0) {
      return res.status(200).end(JSON.stringify({ items: [] }));
    }

    const [complaints, productIndex] = await Promise.all([
      complaintsForRepEmails(emails),
      getProductIndex(),
    ]);

    const warnings = await buildEarlyWarnings(complaints, { productIndex });
    return res.status(200).end(JSON.stringify(warnings));
  } catch (e) {
    console.error('[rep/early-warning] failed', e);
    return res.status(200).end(JSON.stringify({ items: [] }));
  }
}

