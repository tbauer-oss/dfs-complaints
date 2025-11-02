// api/complaint/create.js
export const config = { runtime: 'nodejs' };

import jwt from 'jsonwebtoken';
import { create } from 'xmlbuilder2';
import {
  setCors,
  noContent,
  ok,
  bad,
  methodNotAllowed,
  readJson
} from '../_lib/http.js';
import {
  complaintSave,
  userByEmail,
  nextTicket
} from '../_lib/store.js';
import { send, tpl } from '../_lib/mail.js';

const JWT_SECRET = process.env.JWT_SECRET || 'devsecret';

function auth(req) {
  const hdr = req.headers?.authorization || '';
  const tok = hdr.startsWith('Bearer ') ? hdr.slice(7) : null;
  if (!tok) return null;
  try {
    return jwt.verify(tok, JWT_SECRET);
  } catch {
    return null;
  }
}

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);
  if (req.method !== 'POST') return methodNotAllowed(res);

  const a = auth(req);
  if (!a?.sub) return bad(res, 'unauthorized', 401);

  const u = await userByEmail(a.sub);
  if (!u || u.revoked) return bad(res, 'forbidden', 403);

  const body = readJson(req);
  const payload = body?.payload || {};
  const files = Array.isArray(body?.files) ? body.files : [];

  if (!payload.segment || !payload.article || !payload.desc)
    return bad(res, 'missing required fields', 400);
  if (payload.segment === 'Zahnarzt' && !payload.batch)
    return bad(res, 'missing batch for dentist', 400);

  const ticket = await nextTicket();
  const now = new Date().toISOString();

  const complaint = {
    ticket,
    email: u.email,
    createdAt: now,
    updatedAt: now,
    status: 'Gesendet',
    decision: null,
    reportLink: null,
    payload,
    uploads: files.map(f => ({
      name: f.name,
      mime: f.mime,
      size: Math.floor((f.bytes?.length || 0) * 3 / 4),
    })),
  };

  await complaintSave(complaint);

  // ---------- Erweiterte E-Mail an DFS ----------
  const customerBlock = `
  <strong>Kunde:</strong> ${u.company}<br/>
  <strong>Kontakt:</strong> ${u.contact}<br/>
  <strong>E-Mail:</strong> ${u.email}<br/>
  <strong>Telefon:</strong> ${u.phone || '-'}<br/>
  <strong>Adresse:</strong> ${u.street}, ${u.zip} ${u.city}, ${u.country}<br/>
  `;

  const detailsBlock = `
  <strong>Artikel:</strong> ${payload.article}<br/>
  <strong>Charge:</strong> ${payload.batch || '-'}<br/>
  <strong>Menge:</strong> ${payload.qty || '-'}<br/>
  <strong>Ablaufdatum:</strong> ${payload.expiry || '-'}<br/>
  <strong>Beschreibung:</strong><br/>
  <pre>${payload.desc}</pre>
  `;

  const additionalBlock = `
  <strong>Bereich:</strong> ${payload.segment}<br/>
  <strong>Am Patienten angewendet:</strong> ${payload.applied || '-'}<br/>
  <strong>Verletzung:</strong> ${payload.injury || '-'}<br/>
  <strong>Verletzungsbeschreibung:</strong> ${payload.injuryDesc || '-'}<br/>
  <strong>Rücksendung:</strong> ${payload.returned || '-'}<br/>
  <strong>Gewünschte Bearbeitung:</strong> ${payload.handling || '-'}<br/>
  `;

  const summaryHtml = `
  <p>Neue Reklamation eingegangen:</p>
  <p><strong>Ticket:</strong> ${ticket}</p>
  <hr/>
  ${customerBlock}
  <hr/>
  ${detailsBlock}
  <hr/>
  ${additionalBlock}
  <p><em>Diese Reklamation wurde automatisch über die DFS Complaint App eingereicht.</em></p>
  `;

  // Anhänge (XML + Bilder falls vorhanden)
  const xml = create({ version: '1.0', encoding: 'UTF-8' })
    .ele('Complaint')
      .ele('Ticket').txt(ticket).up()
      .ele('Customer')
        .ele('Company').txt(u.company).up()
        .ele('Email').txt(u.email).up()
      .up()
      .ele('Data')
        .ele('Segment').txt(payload.segment).up()
        .ele('Article').txt(payload.article).up()
        .ele('Batch').txt(payload.batch || '').up()
        .ele('Description').txt(payload.desc || '').up()
      .up()
    .end({ prettyPrint: true });

  const attachments = [
    { filename: `${ticket}.xml`, content: Buffer.from(xml, 'utf8'), contentType: 'application/xml' },
    ...files.map((f, i) => ({
      filename: f.name || `image_${i + 1}.bin`,
      content: Buffer.from(f.bytes || '', 'base64'),
      contentType: f.mime || 'application/octet-stream'
    })),
  ];

  await send('complaint@dfs-diamon.de', {
    subject: `[DFS Complaint] Neue Reklamation ${ticket}`,
    html: summaryHtml,
    attachments
  });

  // Kundenbestätigung
  await send(u.email, tpl.complaintCustomer(ticket));

  return ok(res, { ticket });
}
