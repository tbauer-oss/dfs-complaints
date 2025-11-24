// api/admin/mailcenter.js – Admin-Mailcenter Logs & Retry (stub)
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed } from '../_lib/http.js';

const ADMIN_SECRET = process.env.ADMIN_SECRET || '';
const isAdmin = (req) => ADMIN_SECRET && req.headers?.['x-admin-secret'] === ADMIN_SECRET;

function makeEmptyPayload() {
  return {
    items: [],
    stats: { total: 0, sent: 0, failed: 0, queued: 0 },
  };
}

export default async function handler(req, res) {
  setCors(req, res);
  if (handlePreflight(req, res)) return;

  if (!isAdmin(req)) {
    return bad(res, 'unauthorized', 401);
  }

  if (req.method === 'GET') {
    return ok(res, makeEmptyPayload());
  }

  if (req.method === 'POST') {
    // Resend-Stub: best-effort ACK mit minimalen Feldern
    const body = req.body || {};
    const id = (body.id || '').toString();
    return ok(res, {
      id,
      status: 'queued',
      category: 'mailcenter',
      subject: 'Resend angefordert',
      to: '',
      attempts: 0,
      createdAt: Date.now(),
      lastTriedAt: Date.now(),
      meta: { note: 'Mailcenter-Backend noch nicht angebunden' },
    });
  }

  return methodNotAllowed(res);
}
