import { applyInternalCors, ensureActor, getAudit, updateAudit, deleteAudit } from './_utils.js';

export default async function handler(req, res) {
  applyInternalCors(req, res);
  if (req.method === 'OPTIONS') return res.status(204).end();

  const { id } = req.query || {};
  if (!id) {
    res.statusCode = 400;
    res.end(JSON.stringify({ error: 'id missing' }));
    return;
  }

  if (req.method === 'GET') {
    const audit = await getAudit(id);
    if (!audit) {
      res.statusCode = 404;
      res.end(JSON.stringify({ error: 'not found' }));
      return;
    }
    res.statusCode = 200;
    res.end(JSON.stringify({ audit }));
    return;
  }

  if (req.method === 'PATCH') {
    const actor = await ensureActor(req, res, { write: true });
    if (!actor) return;
    const patch = req.body || {};
    const updated = await updateAudit(id, { ...patch, updatedBy: actor.email }, { method: req.method });
    if (!updated) {
      res.statusCode = 404;
      res.end(JSON.stringify({ error: 'not found' }));
      return;
    }
    res.statusCode = 200;
    res.end(JSON.stringify({ audit: updated }));
    return;
  }

  if (req.method === 'DELETE') {
    const actor = await ensureActor(req, res, { write: true });
    if (!actor) return;
    await deleteAudit(id, { method: req.method });
    res.statusCode = 204;
    res.end();
    return;
  }

  res.statusCode = 405;
  res.end(JSON.stringify({ error: 'method not allowed' }));
}
