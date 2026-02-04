import {
  applyInternalCors,
  ensureActor,
  listAuditEvidence,
  addAuditEvidence,
  deleteAuditEvidence,
} from '../../internal-audits/_utils.js';

export default async function handler(req, res) {
  if (applyInternalCors(req, res)) return;

  const { id } = req.query;
  if (!id) {
    res.statusCode = 400;
    res.end(JSON.stringify({ error: 'missing audit id' }));
    return;
  }

  if (req.method === 'GET') {
    const evidence = await listAuditEvidence(id);
    res.statusCode = 200;
    res.end(JSON.stringify({ evidence }));
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
    const files = payload.files || payload.uploads || [];
    const evidence = await addAuditEvidence(id, files, { method: req.method });
    if (!evidence) {
      res.statusCode = 404;
      res.end(JSON.stringify({ error: 'audit not found' }));
      return;
    }
    res.statusCode = 200;
    res.end(JSON.stringify({ evidence }));
    return;
  }

  if (req.method === 'DELETE') {
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
    const evidenceId = payload.id || payload.evidenceId;
    if (!evidenceId) {
      res.statusCode = 400;
      res.end(JSON.stringify({ error: 'missing evidence id' }));
      return;
    }
    const evidence = await deleteAuditEvidence(id, evidenceId, { method: req.method });
    res.statusCode = 200;
    res.end(JSON.stringify({ evidence }));
    return;
  }

  res.statusCode = 405;
  res.end(JSON.stringify({ error: 'method not allowed' }));
}
