// api/complaint/create.js
export const config = {
  runtime: 'nodejs',
  api: {
    // Eigene Parser-Logik, damit wir CORS-Header auch bei großen Bodies setzen können
    bodyParser: false,
  },
};

const BODY_LIMIT_BYTES = Number(process.env.API_BODY_LIMIT_BYTES || 64 * 1024 * 1024);

import jwt from 'jsonwebtoken';
import { setCors, noContent, ok, bad, methodNotAllowed, readJsonBody } from '../_lib/http.js';
import { complaintSave, userByEmail, nextTicket } from '../_lib/store.js';
import {
  blobUploadsEnabled,
  normalizeProvidedUploads,
  processIncomingFiles,
} from '../_lib/uploads.js';
import { loadAppMeta } from '../_lib/appMeta.js';

const JWT_SECRET = process.env.JWT_SECRET || 'devsecret';

function auth(req) {
  const hdr = req.headers?.authorization || '';
  const tok = hdr.startsWith('Bearer ') ? hdr.slice(7) : null;
  if (!tok) return null;
  try { return jwt.verify(tok, JWT_SECRET); } catch { return null; }
}

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);
  if (req.method !== 'POST')    return methodNotAllowed(res);

  try {
    console.log('[create] enter');

    // --- Auth & User ---
    const a = auth(req);
    if (!a?.sub) return bad(res, 'unauthorized', 401);
    const u = await userByEmail(a.sub);
    if (!u || u.revoked) return bad(res, 'forbidden', 403);

    // --- Body & Validierung ---
    let b;
    try {
      b = await readJsonBody(req, { limitBytes: BODY_LIMIT_BYTES });
    } catch (bodyErr) {
      const code = bodyErr?.statusCode || (bodyErr?.message === 'body too large' ? 413 : 400);
      const msg = bodyErr?.message || 'invalid body';
      return bad(res, msg, code);
    }
    const payload = b?.payload || {};
    const files   = Array.isArray(b?.files) ? b.files : [];
    const providedUploads = normalizeProvidedUploads(b?.uploads);

    if (!payload.article || !payload.desc) {
      return bad(res, 'required fields missing', 400);
    }
    if (payload.segment === 'Zahnarzt' && !payload.batch) {
      return bad(res, 'batch required for dentist', 400);
    }

    // --- Ticket erst erzeugen, wenn Uploads valide sind ---
    let ticketPromise;
    const ensureTicket = () => {
      ticketPromise = ticketPromise || nextTicket();
      return ticketPromise;
    };

    const nowMs  = Date.now();
    let meta = null;
    try { meta = await loadAppMeta(); } catch (e) { console.warn('[create] meta load failed', e?.message || e); }

    let processedFiles;
    try {
      processedFiles = await processIncomingFiles(files, {
        ticket: ensureTicket,
        includeMailAttachments: true,
        allowPreviewFallback: !blobUploadsEnabled,
      });
    } catch (err) {
      const msg = err?.message === 'files too large'
        ? 'files too large'
        : err?.message === 'invalid file encoding'
          ? 'invalid file encoding'
          : 'file upload failed';
      return bad(res, msg, 400);
    }

    const ticket = await ensureTicket();
    const uploads = [...providedUploads, ...processedFiles.uploads];

    const complaint = {
      ticket,
      email: u.email,
      createdAt: nowMs,
      updatedAt: nowMs,
      ...(meta?.testMode ? { testMode: true } : {}),
      status: 1,
      decision: null,
      reportLink: null,
      reportLinks: {},
      internalReportLinks: {},
      externalReportLinks: {},
      qmCustomerSummary: null,
      qmCustomerSummaryTranslations: {},
      internalDepartments: [],
      internalEvaluationText_de: null,
      internalEvaluationCause: null,
      internalEvaluationTranslations: {},
      internalEvaluationNewForAdmin: false,
      isGoodwill: false,
      payload,
      uploads,
      history: [
        {
          at: nowMs,
          actor: 'customer',
          type: 'created',
          message: 'Reklamation eingereicht',
          data: { email: u.email },
        },
      ],
    };

    console.log('[create] before save', { email: u.email, segment: payload.segment, article: payload.article });
    await complaintSave(complaint);

    // --- Try Mail & XML (best effort) ---
    try {
      console.log('[create] before mail/xml', { files: processedFiles.uploads.length });

      // dynamische Imports erst NACH save
      const [{ create }, { send, tpl }] = await Promise.all([
        import('xmlbuilder2'),
        import('../_lib/mail.js'),
      ]);

      const nowIso = new Date(nowMs).toISOString();
      const xml = create({ version: '1.0', encoding: 'UTF-8' })
        .ele('Complaint')
          .ele('Ticket').txt(ticket).up()
          .ele('CreatedAt').txt(nowIso).up()
          .ele('Customer')
            .ele('Company').txt(u.company || '').up()
            .ele('Contact').txt(u.contact || '').up()
            .ele('Email').txt(u.email || '').up()
            .ele('Street').txt(u.street || '').up()
            .ele('ZIP').txt(u.zip || '').up()
            .ele('City').txt(u.city || '').up()
            .ele('Country').txt(u.country || '').up()
            .ele('Phone').txt(u.phone || '').up()
          .up()
          .ele('Data')
            .ele('Segment').txt(payload.segment || '').up()
            .ele('Article').txt(payload.article || '').up()
            .ele('Batch').txt(payload.batch || '').up()
            .ele('Quantity').txt(String(payload.qty || '')).up()
            .ele('Expiry').txt(String(payload.expiry || '')).up()
            .ele('Description').txt(payload.desc || '').up()
            .ele('Applied').txt(String(payload.applied || '')).up()
            .ele('Injury').txt(String(payload.injury || '')).up()
            .ele('InjuryDesc').txt(String(payload.injuryDesc || '')).up()
            .ele('Returned').txt(String(payload.returned || '')).up()
            .ele('Handling').txt(String(payload.handling || '')).up()
          .up()
        .end({ prettyPrint: true });

      const attachments = [
        { filename: `${ticket}.xml`, content: Buffer.from(xml, 'utf8'), contentType: 'application/xml' },
        ...processedFiles.attachments,
      ];

      const htmlDFS = `
        <p><strong>Neue Reklamation</strong></p>
        <p><strong>Ticket:</strong> ${ticket}</p>
        <hr/>
        <p><strong>Kunde:</strong> ${u.company}<br/>
           <strong>Kontakt:</strong> ${u.contact || '-'}<br/>
           <strong>E-Mail:</strong> ${u.email}<br/>
           <strong>Telefon:</strong> ${u.phone || '-'}<br/>
           <strong>Adresse:</strong> ${u.street || ''}, ${u.zip || ''} ${u.city || ''}, ${u.country || ''}</p>
        <hr/>
        <p><strong>Artikel:</strong> ${payload.article}<br/>
           <strong>Charge:</strong> ${payload.batch || '-'}<br/>
           <strong>Menge:</strong> ${payload.qty || '-'}<br/>
           <strong>Ablaufdatum:</strong> ${payload.expiry || '-'}</p>
        <p><strong>Beschreibung:</strong><br/><pre>${payload.desc}</pre></p>
        <hr/>
        <p><strong>Bereich:</strong> ${payload.segment}<br/>
           <strong>Am Patienten angewendet:</strong> ${payload.applied || '-'}<br/>
           <strong>Verletzung:</strong> ${payload.injury || '-'}<br/>
           <strong>Verletzungsbeschreibung:</strong> ${payload.injuryDesc || '-'}<br/>
           <strong>Rücksendung:</strong> ${payload.returned || '-'}<br/>
           <strong>Gewünschte Bearbeitung:</strong> ${payload.handling || '-'}</p>
      `;

      await send('complaint@dfs-diamon.de', { subject: `[DFS Complaint] Neue Reklamation ${ticket}`, text: htmlDFS, lang: 'de' }, attachments);
      await send(u.email, tpl.complaintCustomer(ticket));

      console.log('[create] mail/xml sent');
    } catch (mailErr) {
      // WICHTIG: Mail-/XML-Fehler NICHT die Response abbrechen lassen
      console.error('[create] mail/xml failed:', mailErr?.message || mailErr);
    }

    // --- Immer Erfolg zurückgeben (Ticket ist gespeichert) ---
    return ok(res, { ticket });
  } catch (e) {
    console.error('[create] ERROR', e?.message || e);
    return bad(res, e?.message || 'server error', 500);
  }
}
