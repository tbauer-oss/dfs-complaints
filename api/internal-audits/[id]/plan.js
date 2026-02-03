import { applyInternalCors, ensureActor, getAudit, getAuditPlan, saveAuditPlan } from '../_utils.js';

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
    const plan = await getAuditPlan(id);
    if (!plan) {
      res.statusCode = 404;
      res.end(JSON.stringify({ error: 'plan not found' }));
      return;
    }
    res.statusCode = 200;
    res.end(JSON.stringify({ plan }));
    return;
  }

  if (req.method === 'PUT') {
    const actor = await ensureActor(req, res, { write: true });
    if (!actor) return;
    const audit = await getAudit(id);
    if (!audit) {
      res.statusCode = 404;
      res.end(JSON.stringify({ error: 'not found' }));
      return;
    }
    const entries = req.body?.planEntries || req.body?.plan || [];
    const saved = await saveAuditPlan(id, entries, { method: req.method, actor });
    if (!saved) {
      res.statusCode = 404;
      res.end(JSON.stringify({ error: 'not found' }));
      return;
    }
    res.statusCode = 200;
    res.end(JSON.stringify({ planEntries: saved }));
    return;
  }

  res.statusCode = 405;
  res.end(JSON.stringify({ error: 'method not allowed' }));
}
