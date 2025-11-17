// api/admin/complaints.js
export const config = { runtime: 'nodejs' };

import {
  setCors,
  ok,
  bad,
  noContent,
  methodNotAllowed,
  readJson,
} from '../_lib/http.js';

// -------- Admin-Auth ----------
const ADMIN_SECRET = process.env.ADMIN_SECRET || '';
const isAdmin = (req) => ADMIN_SECRET && req.headers?.['x-admin-secret'] === ADMIN_SECRET;

// -------- Status-Mapping ----------
const STATUS_LABEL = {
  1: 'Eingegangen',
  2: 'In Bearbeitung',
  3: 'Rückfrage erforderlich',
  4: 'In Nacharbeit',
  5: 'Abgeschlossen',
};
const STATUS_CODE = Object.fromEntries(Object.entries(STATUS_LABEL).map(([k, v]) => [v, Number(k)]));

const STATUS_I18N = {
  de: {
    1: 'Eingegangen',
    2: 'In Bearbeitung',
    3: 'Rückfrage erforderlich',
    4: 'In Nacharbeit',
    5: 'Abgeschlossen',
  },
  en: {
    1: 'Received',
    2: 'In progress',
    3: 'Needs info',
    4: 'Rework',
    5: 'Closed',
  },
  fr: {
    1: 'Reçu',
    2: 'En cours',
    3: 'Informations requises',
    4: 'Reprise',
    5: 'Clôturé',
  },
  it: {
    1: 'Ricevuto',
    2: 'In lavorazione',
    3: 'Informazioni necessarie',
    4: 'Revisione',
    5: 'Chiuso',
  },
  es: {
    1: 'Recibido',
    2: 'En curso',
    3: 'Se requiere información',
    4: 'Revisión',
    5: 'Cerrado',
  },
};

const PUSH_TEXT = {
  de: {
    title: 'Status Ihrer Reklamation',
    body: (ticket, status) => `Der Status Ihrer Reklamation ${ticket} hat sich geändert: ${status}.`,
  },
  en: {
    title: 'Complaint status updated',
    body: (ticket, status) => `The status of your complaint ${ticket} has changed to ${status}.`,
  },
  fr: {
    title: 'Statut de réclamation mis à jour',
    body: (ticket, status) => `Le statut de votre réclamation ${ticket} a changé : ${status}.`,
  },
  it: {
    title: 'Aggiornamento stato reclamo',
    body: (ticket, status) => `Lo stato del reclamo ${ticket} è cambiato in: ${status}.`,
  },
  es: {
    title: 'Estado de reclamación actualizado',
    body: (ticket, status) => `El estado de su reclamación ${ticket} ha cambiado a: ${status}.`,
  },
};

const SUPPORTED_LANGS = new Set(['de', 'en', 'fr', 'it', 'es']);

function resolveLang(input) {
  const raw = (input || '').toString().trim().toLowerCase();
  if (SUPPORTED_LANGS.has(raw)) return raw;
  const two = raw.split(/[-_]/)[0];
  return SUPPORTED_LANGS.has(two) ? two : 'de';
}

function buildPushMessage(lang, ticket, status) {
  const l = resolveLang(lang);
  const texts = PUSH_TEXT[l] || PUSH_TEXT.de;
  const labels = STATUS_I18N[l] || STATUS_I18N.de;
  const statusLabel = labels[status] || labels[1];
  return {
    title: texts.title,
    body: texts.body(ticket, statusLabel),
    statusLabel,
  };
}

function parseStatus(input) {
  if (input == null) return null;
  if (typeof input === 'number') return (input >= 1 && input <= 5) ? input : null;
  if (typeof input === 'string') {
    const s = input.trim();
    if (/^\d+$/.test(s)) {
      const n = Number(s);
      return (n >= 1 && n <= 5) ? n : null;
    }
    return STATUS_CODE[s] ?? null;
  }
  return null;
}

// -------- Helpers ----------
const normEmail = (v = '') => v.toString().trim().toLowerCase();
const sortDescByDate = (a, b) => {
  const ta = a?.updatedAt ?? a?.createdAt ?? 0;
  const tb = b?.updatedAt ?? b?.createdAt ?? 0;
  return (tb || 0) - (ta || 0);
};
const decorateForAdmin = (c) => ({ ...c, statusLabel: STATUS_LABEL[c.status] || STATUS_LABEL[1] });

// =======================================================
// Handler
// =======================================================
export default async function handler(req, res) {
  // 1) CORS IMMER zuerst
  setCors(req, res);

  // 2) Preflight IMMER minimal beantworten (keine weiteren Imports!)
  if (req.method === 'OPTIONS') return noContent(res);

  // 3) Admin-Auth prüfen (immer noch ohne schwere Imports)
  if (!isAdmin(req)) return bad(res, 'admin unauthorized', 401);

  // 4) Schwere Imports NACH Preflight/Admin laden (verhindert 500 bei OPTIONS)
  const {
    complaintsAll,
    complaintsOpen,
    complaintsByEmail,
    complaintByTicket,
    complaintSave,
    complaintDelete,
    userByEmail,
    pushTokensForEmail,
    pushTokenRemove,
    repPushTokens,
    repPushTokenRemove,
    adminPushTokens,
    adminPushTokenRemove,
    Status,
  } = await import('../_lib/store.js');
  const { sendPushNotification } = await import('../_lib/push.js');
  let getRepOf = null;
  try {
    ({ getRepOf } = await import('../_lib/repsStore.js'));
  } catch {
    getRepOf = null;
  }
  
  try {
    // ----------------------------
    // GET
    // ----------------------------
    if (req.method === 'GET') {
      const q = req.query || {};
      const email   = normEmail(q.email || '');
      const ticket  = (q.ticket || '').toString().trim();
      const open    = (q.open || '').toString().trim();
      const details = (q.details || '').toString().trim();

      if (ticket) {
        const c = await complaintByTicket(ticket);
        if (!c) return bad(res, 'not found', 404);
        return ok(res, decorateForAdmin(c));
      }

      if (email) {
        const list = await complaintsByEmail(email);
        list.sort(sortDescByDate);
        return ok(res, details === '1' ? list.map(decorateForAdmin) : list.map((c) => c.ticket));
      }

      if (open === '1') {
        const list = await complaintsOpen();
        return ok(res, list.map(decorateForAdmin));
      }

      const all = await complaintsAll();
      const out = (Array.isArray(all) ? all : []).sort(sortDescByDate).map(decorateForAdmin);
      return ok(res, out);
    }

    // ----------------------------
    // POST / PATCH – Status / Decision / Report
    // ----------------------------
    if (req.method === 'POST' || req.method === 'PATCH') {
      let body = readJson(req);
      if (typeof body === 'string') { try { body = JSON.parse(body); } catch {} }
      if (typeof body === 'string') body = { ticket: body };
      if (!body || typeof body !== 'object') body = {};

      const ticket      = (body?.ticket || '').toString().trim();
      const statusIn    = body?.status; // 1..6 | "1".."6" | Label
      const hasDecision = Object.prototype.hasOwnProperty.call(body, 'decision');
      const rawDecision = hasDecision ? body.decision : undefined; // 'accepted' | 'rejected' | "" | null | undefined
      const reportLink  = body?.reportLink; // string | "" | null | undefined
      const hasInternal = Object.prototype.hasOwnProperty.call(body, 'internalNo');
      const rawInternal = hasInternal ? body.internalNo : undefined;
      const hasNotes    = Object.prototype.hasOwnProperty.call(body, 'notes');
      const rawNotes    = hasNotes ? body.notes : undefined;

      if (!ticket) return bad(res, 'missing ticket', 400);

      const c = await complaintByTicket(ticket);
      if (!c) return bad(res, 'not found', 404);

      const prevStatus = Number(c.status ?? 1);
      let statusChanged = false;

      // Status (optional)
      if (statusIn !== undefined) {
        const code = parseStatus(statusIn);
        if (code == null) return bad(res, 'invalid status', 400);
        if (code !== c.status) {
          c.status = code;
          statusChanged = true;
        }
      }

      // Decision (optional, separat, "" => null)
      if (hasDecision) {
        const decision = (rawDecision === '') ? null : rawDecision;
        if (decision !== null && decision !== 'accepted' && decision !== 'rejected') {
          return bad(res, 'invalid decision', 400);
        }
        c.decision = decision;

        // Business-Logik: 'rejected' => schließen + Status "Entscheidung"
        if (c.decision === 'rejected') {
          c.closed = true;
          c.closedAt = Date.now();
          if (c.status !== Status.CLOSED) {
            c.status = Status.CLOSED;
            statusChanged = true;
          }
        }
      }

      // Report-Link (optional; "" => löschen)
      if (reportLink !== undefined) {
        const v = (reportLink ?? '').toString().trim();
        if (v) c.reportLink = v;
        else delete c.reportLink;
      }

      // Interne Nummer (optional; "" => löschen)
      if (hasInternal) {
        const v = (rawInternal ?? '').toString().trim();
        if (v) c.internalNo = v;
        else delete c.internalNo;
      }

      // Admin-Notizen (optional; "" => löschen)
      if (hasNotes) {
        const v = (rawNotes ?? '').toString();
        if (v.trim()) c.adminNotes = v;
        else delete c.adminNotes;
      }

      c.updatedAt = Date.now();
      if (!statusChanged && prevStatus !== c.status) statusChanged = true;
      if (statusChanged) c.statusUpdatedAt = Date.now();

      // robust persistieren
      try { await complaintSave(ticket, c); }
      catch { await complaintSave({ ...c }); }

      if (statusChanged) {
        try {
          const tokenMeta = new Map();
          const addTokens = (list, type, id, fallbackLang) => {
            const arr = Array.isArray(list) ? list : [];
            for (const entry of arr) {
              const tok = (entry?.token || '').toString().trim();
              if (!tok) continue;
              const lang = resolveLang(entry?.lang || fallbackLang || '');
              if (!tokenMeta.has(tok)) {
                tokenMeta.set(tok, { lang, targets: [] });
              }
              const meta = tokenMeta.get(tok);
              if (!meta.lang) meta.lang = lang;
              if (!meta.targets.some(t => t.type === type && t.id === id)) {
                meta.targets.push({ type, id });
              }
            }
          };

          const email = normEmail(c.email || '');
          const user = email ? await userByEmail(email) : null;
          if (email) {
            const customerTokens = await pushTokensForEmail(email);
            addTokens(customerTokens, 'customer', email, user?.lang || '');
          }

          let repInfo = null;
          if (email && typeof getRepOf === 'function') {
            try { repInfo = await getRepOf(email); }
            catch (err) { console.warn('push rep lookup failed', err?.message || err); }
          }
          if (repInfo?.id) {
            const repTokensList = await repPushTokens(repInfo.id);
            addTokens(repTokensList, 'rep', String(repInfo.id), '');
          }

          const adminTokensList = await adminPushTokens();
          addTokens(adminTokensList, 'admin', 'admin', '');

          if (tokenMeta.size > 0) {
            const tokensByLang = new Map();
            for (const [token, meta] of tokenMeta.entries()) {
              const lang = meta.lang || 'de';
              if (!tokensByLang.has(lang)) tokensByLang.set(lang, []);
              tokensByLang.get(lang).push({ token, meta });
            }

            const invalidTokens = new Set();
            for (const [lang, entries] of tokensByLang.entries()) {
              const tokens = entries.map(e => e.token);
              if (tokens.length === 0) continue;
              const audiences = Array.from(new Set(entries.flatMap(e => e.meta.targets.map(t => t.type)))).sort().join(',');
              const pushMsg = buildPushMessage(lang, c.ticket, c.status);
              const dataPayload = {
                type: 'complaint-status',
                ticket: c.ticket,
                status: String(c.status ?? ''),
                statusLabel: pushMsg.statusLabel,
                lang,
              };
              if (audiences) dataPayload.audiences = audiences;
              if (email) dataPayload.customerEmail = email;
              if (repInfo?.id) dataPayload.repId = String(repInfo.id);

              const result = await sendPushNotification({
                tokens,
                title: pushMsg.title,
                body: pushMsg.body,
                data: dataPayload,
              });

              if (Array.isArray(result?.invalidTokens) && result.invalidTokens.length > 0) {
                result.invalidTokens.forEach(t => invalidTokens.add(t));
              }
            }

            if (invalidTokens.size > 0) {
              for (const bad of invalidTokens) {
                const meta = tokenMeta.get(bad);
                if (!meta) continue;
                for (const target of meta.targets) {
                  try {
                    if (target.type === 'customer' && target.id) {
                      await pushTokenRemove(target.id, bad);
                    } else if (target.type === 'rep' && target.id) {
                      await repPushTokenRemove(target.id, bad);
                    } else if (target.type === 'admin') {
                      await adminPushTokenRemove(bad);
                    }
                  } catch (err) {
                    console.error('push token cleanup failed', err);
                  }
                }
              }
            }
          }
        } catch (pushErr) {
          console.error('admin/complaints push notify failed:', pushErr);
        }
      }
      
      return ok(res, {
        ticket: c.ticket,
        status: c.status,
        statusLabel: STATUS_LABEL[c.status] || STATUS_LABEL[1],
        decision: c.decision ?? null,
        reportLink: c.reportLink ?? null,
        internalNo: c.internalNo ?? null,
        adminNotes: c.adminNotes ?? null,
        updatedAt: c.updatedAt,
      });
    }

    // ----------------------------
    // DELETE
    // ----------------------------
    if (req.method === 'DELETE') {
      let ticket = (req.query?.ticket || '').toString().trim();
      if (!ticket && req.body) {
        try {
          const b = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : req.body;
          ticket = (b?.ticket || '').toString().trim();
        } catch {}
      }
      if (!ticket) return bad(res, 'missing ticket', 400);

      const c = await complaintByTicket(ticket);
      if (!c) return bad(res, 'not found', 404);

      await complaintDelete(ticket);
      return noContent(res);
    }

    return methodNotAllowed(res);
  } catch (e) {
    console.error('admin/complaints error:', e);
    return bad(res, e?.message || 'server error', 500);
  }
}
