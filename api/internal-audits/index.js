import { applyInternalCors, ensureActor, listAudits, createAudit } from './_utils.js';

export default async function handler(req, res) {
  if (applyInternalCors(req, res)) return;

  if (req.method === 'GET') {
    const audits = await listAudits();
    res.statusCode = 200;
    res.end(JSON.stringify({ audits }));
    return;
  }

  if (req.method === 'POST') {
    const actor = await ensureActor(req, res, { write: true });
    if (!actor) return;
    const payload = req.body || {};
    const audit = await createAudit({ ...payload, actor }, { method: req.method });
    res.statusCode = 200;
    res.end(JSON.stringify({ audit }));
    return;
  }

  res.statusCode = 405;
  res.end(JSON.stringify({ error: 'method not allowed' }));
}
