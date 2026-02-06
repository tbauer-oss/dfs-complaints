import { applyInternalCors, ensureActor, setProgramArchived } from '../internal-audits/_utils.js';

export default async function handler(req, res) {
  if (applyInternalCors(req, res)) return;

  if (req.method === 'PATCH') {
    const actor = await ensureActor(req, res, { write: true });
    if (!actor) return;
    const body = req.body || {};
    const archived = body.archived === true;
    const updated = await setProgramArchived(req.query?.year, archived, { method: req.method });
    if (!updated) {
      res.statusCode = 404;
      res.end(JSON.stringify({ error: 'program not found' }));
      return;
    }
    res.statusCode = 200;
    res.end(JSON.stringify({ program: updated }));
    return;
  }

  res.statusCode = 405;
  res.end(JSON.stringify({ error: 'method not allowed' }));
}
