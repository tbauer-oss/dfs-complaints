import { applyInternalCors, listAuditPrograms } from '../internal-audits/_utils.js';

export default async function handler(req, res) {
  if (applyInternalCors(req, res)) return;

  if (req.method === 'GET') {
    const programs = await listAuditPrograms();
    res.statusCode = 200;
    res.end(JSON.stringify({ programs }));
    return;
  }

  res.statusCode = 405;
  res.end(JSON.stringify({ error: 'method not allowed' }));
}
