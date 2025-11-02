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

// --- JWT prüfen ---
function auth(req) {
  const hdr = req.headers?.authorization || '';
  const tok = hdr.startsWith('Bearer ') ? hdr.slice(7) : null;
  if (!tok) return null;
  try { return jwt.verify(tok, JWT_SECRET); } catch { return null; }
}

export default async function handler(req, res) {
  // CORS immer zuerst
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);
  if (req.method !== 'POST')    return methodNotAllowed(res);

  // Auth
  const a = auth(req);
  if (!a?.sub) return bad(res, 'unauthorized', 401);

  const u = await userByEmail(a.sub);
  if (!u || u.revoked) return bad(res, 'forbidden', 403);

  // Body (JSON + Base64-Dateien)
  const b = readJson(req);
  const payload = b?.payload || {};
  const files = Array.isArray(b?.files) ? b.files : [];

  // Pflichtfelder
  if (!payload.segment || !payload.article || !payload.desc)
    return bad(res, 'missing required fields', 400);
  if (payload.segment === 'Zahnarzt' && !payload.batch)
    return bad(res, 'missing batch for dentist', 400);

  // Ticket
  const ticket = await nextTicket();
  const nowIso = new Date().toISOString();
  const nowMs  = Date.now();

  const complaint = {
    ticket,
    email: u.email,
    createdAt: nowMs,
    updatedAt: nowMs,
    status: 1,              // SENT
    decision: null,
    reportLink: null,
    payload,
    uploads: files.map(f => ({
      name: f?.name || '',
      mime: f?.mime || 'application/octet-stream',
      size: Math.floor(((f?.bytes || '').length) * 3 / 4) || 0, // grobe Größe aus Base64
    })),
  };

  await complaintSave(complaint);

  // DFS-Mail (erweitert)
  const htmlDFS = `
    <p><strong>Neue Reklamation</strong></p>
    <p><strong>Ticket:</strong> ${ticket}</p>
    <hr/>
    <p>
      <strong>Kunde:</strong> ${u.company}<br/>
      <strong>Kontakt:</strong> ${u.contact}<br/>
      <strong>E-Mail:</strong> ${u.email}<br/>
      <strong>Telefon:</strong> ${u.phone || '-'}<br/>
      <strong>Adresse:</strong> ${u.street}, ${u.zip} ${u.city}, ${u.country}
    </p>
    <hr/>
    <p>
      <strong>Artikel:</strong> ${payload.article}<br/>
      <strong>Charge:</strong> ${payload.batch || '-'}<br/>
      <strong>Menge:</strong> ${payload.qty || '-'}<br/>
      <strong>Ablaufdatum:</strong> ${payload.expiry || '-'}
    </p>
    <p><strong>Beschreibung:</strong><br/><pre>${payload.desc}</pre></p>
    <hr/>
    <p>
      <strong>Bereich:</strong> ${payload.segment}<br/>
      <strong>Am Patienten angewendet:</strong> ${payload.applied || '-'}<br/>
      <strong>Verletzung:</strong> ${payload.injury || '-'}<br/>
      <strong>Verletzungsbeschreibung:</strong> ${payload.injuryDesc || '-'}<br/>
      <strong>Rücksendung:</strong> ${payload.returned || '-'}<br/>
      <strong>Gewünschte Bearbeitung:</strong> ${payload.handling || '-'}
    </p>
  `;

  // XML (klein, lesbar)
  const xml = create({ version: '1.0', encoding: 'UTF-8' })
    .ele('Complaint')
      .ele('Ticket').txt(ticket).up()
      .ele('CreatedAt').txt(nowIso).up()
      .ele('Customer')
        .ele('Company').txt(u.company).up()
        .ele('Contact').txt(u.contact || '').up()
        .ele('Email').txt(u.email).up()
        .ele('Street').txt(u.street || '').up()
        .ele('ZIP').txt(u.zip || '').up()
        .ele('City').txt(u.city || '').up()
        .ele('Country').txt(u.country || '').up()
        .ele('Phone').txt(u.phone || '').up()
      .up()
      .ele('Data')
        .ele('Segment').txt(payload.segment).up()
        .ele('Article').txt(payload.article).up()
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
    ...files.map((f,i) => ({
      filename: f?.name || `image_${i+1}.bin`,
      content: Buffer.from(f?.bytes || '', 'base64'),
      contentType: f?.mime || 'application/octet-stream'
    })),
  ];

  await send('complaint@dfs-diamon.de', {
    subject: `[DFS Complaint] Neue Reklamation ${ticket}`,
    html: htmlDFS,
    attachments
  });

  // Kunden-Bestätigung (ohne Bilder)
  await send(u.email, tpl.complaintCustomer(ticket));

  return ok(res, { ticket });
}
