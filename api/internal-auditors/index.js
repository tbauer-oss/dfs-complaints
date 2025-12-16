import { applyInternalCors, ensureActor, listAuditors, createAuditor } from '../internal-audits/_utils.js';

export default async function handler(req, res) {
  if (applyInternalCors(req, res)) return;

  if (req.method === 'GET') {
    const auditors = await listAuditors();
    res.statusCode = 200;
    res.end(JSON.stringify({ auditors }));
    return;
  }

  if (req.method === 'POST') {
    const actor = await ensureActor(req, res, { write: true });
    if (!actor) return;
    let payload = req.body || {};
    if (typeof payload === 'string') {
      try {
        payload = JSON.parse(payload);
      } catch (err) {
        res.statusCode = 400;
        res.end(JSON.stringify({ error: 'invalid json body' }));
        return;
      }
    }
    const auditor = await createAuditor(payload, { method: req.method });
    res.statusCode = 200;
    res.end(JSON.stringify({ auditor }));
    return;
  }

  res.statusCode = 405;
  res.end(JSON.stringify({ error: 'method not allowed' }));
}
