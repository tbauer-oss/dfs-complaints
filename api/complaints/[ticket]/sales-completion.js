// api/complaints/[ticket]/sales-completion.js
export const config = { runtime: 'nodejs' };

import {
  bad,
  noContent,
  ok,
  readJson,
  setCors,
  methodNotAllowed,
} from '../../_lib/http.js';
import { portalUserFromRequest, normalizeRole, PORTAL_ROLES } from '../../_lib/portalAuth.js';
import { complaintGet, complaintUpdate, Status } from '../../_lib/store.js';

function normalizeHandling(complaint) {
  const p = complaint?.payload || {};
  const raw = p.handling ?? p.Wunsch ?? '';
  return raw?.toString().trim().toLowerCase() || '';
}

function trim(v) {
  const s = (v ?? '').toString().trim();
  return s.length > 0 ? s : '';
}

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);
  if (req.method !== 'POST') return methodNotAllowed(res);

  const { ticket } = req.query || {};
  if (!ticket) return bad(res, 'missing ticket', 400);

  const actor = await portalUserFromRequest(req, { allowSecretFallback: false });
  if (!actor) return bad(res, 'unauthorized', 401);
  const role = normalizeRole(actor.role);
  if (role !== PORTAL_ROLES.user || actor.isSales !== true) {
    return bad(res, 'Keine Berechtigung für Sales-Abschluss.', 403);
  }

  const complaint = await complaintGet(ticket);
  if (!complaint) return bad(res, 'not found', 404);
  if (Number(complaint.status) !== Status.CLOSED) {
    return bad(res, 'Sales-Bearbeitung nur für abgeschlossene Reklamationen möglich.', 400);
  }
  // Sales users may update already completed sales data (e.g. order/invoice numbers)
  // to correct mistakes. Keep validation below intact but allow re-submission.

  const body = readJson(req) || {};
  const handling = normalizeHandling(complaint);
  const wantsReplacement = handling === 'ersatz';
  const wantsCredit = handling === 'gutschrift';

  const orderNumber = trim(body.orderNumber || body.order_number || body.auftrag);
  const invoiceNumber = trim(body.invoiceNumber || body.invoice_number || body.rechnung);
  const salesAgentCode = trim(body.salesAgentCode || body.agent || body.sales || body.sachbearbeiter);

  if (wantsReplacement && !orderNumber) {
    return bad(res, 'Bitte Auftragsnummer eingeben (Ersatzlieferung).', 400);
  }
  if (wantsCredit && !invoiceNumber) {
    return bad(res, 'Bitte Rechnungsnummer eingeben (Gutschrift).', 400);
  }
  if (!salesAgentCode || salesAgentCode.length < 2 || salesAgentCode.length > 5) {
    return bad(res, 'Bitte Sachbearbeiter-Kürzel eingeben.', 400);
  }

  const patch = {
    orderNumber: wantsReplacement ? orderNumber : null,
    invoiceNumber: wantsCredit ? invoiceNumber : null,
    salesAgentCode,
    salesCompleted: true,
    salesCompletedAt: Date.now(),
    salesCompletedBy: actor.email,
  };

  const updated = await complaintUpdate(ticket, patch);
  return ok(res, { ok: true, complaint: updated });
}
