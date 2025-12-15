// api/faq.js
export const config = { runtime: 'nodejs' };

import { setCors, handlePreflight, ok, bad, methodNotAllowed } from './_lib/http.js';
import { faqList, FAQ_AUDIENCE_CODES } from './_lib/store.js';
import { getAuthUser } from './_lib/auth.js';
import { getRepFromAuthHeader } from './_lib/repAuth.js';

function resolveAudience(req) {
  const rep = getRepFromAuthHeader(req);
  if (rep) return 'rep';

  const requested = (req.query?.audience || '').toString().trim().toLowerCase();
  if (FAQ_AUDIENCE_CODES.includes(requested) && requested === 'customer') return 'customer';

  const customer = getAuthUser(req);
  if (customer) return 'customer';

  return 'customer';
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  res.setHeader('Cache-Control', 'no-store');

  if (req.method !== 'GET') {
    return methodNotAllowed(res);
  }

  try {
    const audience = resolveAudience(req);
    const data = await faqList({ audience, includeInactive: false });
    return ok(res, { ...data, audience });
  } catch (e) {
    console.error('faq endpoint failed', e);
    return bad(res, 'internal error', 500);
  }
}
