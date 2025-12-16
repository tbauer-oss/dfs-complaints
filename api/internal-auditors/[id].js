import { applyInternalCors, ensureActor, deleteAuditor } from '../internal-audits/_utils.js';

export default async function handler(req, res) {
  if (applyInternalCors(req, res)) return;

  const { id } = req.query || {};
  if (!id) {
    res.statusCode = 400;
    res.end(JSON.stringify({ error: 'id missing' }));
    return;
  }

  if (req.method === 'DELETE') {
    const actor = await ensureActor(req, res, { write: true });
    if (!actor) return;
    await deleteAuditor(id, { method: req.method });
    res.statusCode = 204;
    res.end();
    return;
  }

  res.statusCode = 405;
  res.end(JSON.stringify({ error: 'method not allowed' }));
}
