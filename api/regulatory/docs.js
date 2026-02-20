export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../_lib/http.js';
import { listLegalDocuments } from '../_lib/regulatory/db.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);
  const docs = await listLegalDocuments();
  return ok(res, { ok: true, docs });
}
