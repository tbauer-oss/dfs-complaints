export const config = { runtime: 'nodejs' };

import jwt from 'jsonwebtoken';
import multer from 'multer';
import { create } from 'xmlbuilder2';
import { setCors, noContent, ok, bad, methodNotAllowed } from '../_lib/http.js';
import { complaintSave, userByEmail, nextTicket } from '../_lib/store.js';
import { send, tpl } from '../_lib/mail.js';

const JWT_SECRET = process.env.JWT_SECRET || 'devsecret';
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 8 * 1024 * 1024, files: 10 } }); // Single file limit; sum prüfen unten

function auth(req){
  const hdr = req.headers?.authorization || '';
  const tok = hdr.startsWith('Bearer ') ? hdr.slice(7) : null;
  if (!tok) return null;
  try { return jwt.verify(tok, JWT_SECRET); } catch { return null; }
}

function runMulter(req,res){
  return new Promise((resolve, reject)=>{
    upload.array('images')(req, res, (err)=> err ? reject(err) : resolve());
  });
}

export default async function handler(req, res){
  setCors(req,res);
  if (req.method === 'OPTIONS') return noContent(res);
  if (req.method !== 'POST')    return methodNotAllowed(res);

  const a = auth(req);
  if (!a?.sub) return bad(res,'unauthorized',401);
  const u = await userByEmail(a.sub);
  if (!u || u.revoked) return bad(res,'forbidden',403);

  await runMulter(req,res);

  const body = JSON.parse(req.body?.fields || req.body || '{}');

  const required = ['segment','article','desc','privacy','returned','handling'];
  for (const k of required) if (!body[k]) return bad(res, `missing ${k}`);

  if (body.segment === 'Zahnarzt'){
    if (!body.applied || typeof body.applied !== 'string') return bad(res,'missing applied (Ja/Nein)');
    if (!body.injury || typeof body.injury !== 'string') return bad(res,'missing injury (Ja/Nein)');
    if (body.applied === 'Ja' && body.injury === 'Ja' && !body.injuryDesc) return bad(res,'missing injuryDesc');
    if (!body.batch) return bad(res,'missing batch (Charge)');
  }

  // Summe Bilder prüfen (≤ 8 MB)
  const files = req.files || [];
  const totalBytes = files.reduce((s,f)=>s + (f?.buffer?.length||0), 0);
  if (totalBytes > 8 * 1024 * 1024) return bad(res,'images too large (max 8MB total)');

  const ticket = await nextTicket();
  const now = new Date().toISOString();

  const payload = {
    ticket, createdAt: now, email: u.email,
    customer: { company: u.company, contact: u.contact, street: u.street, zip: u.zip, city: u.city, country: u.country, phone: u.phone||'' },
    data: {
      segment: body.segment, article: body.article, batch: body.batch||'',
      qty: body.qty||'', expiry: body.expiry||'',
      desc: body.desc,
      applied: body.applied||'', injury: body.injury||'', injuryDesc: body.injuryDesc||'',
      returned: body.returned, handling: body.handling
    },
    status: 'Gesendet'
  };

  // XML
  const xml = create({ version:'1.0', encoding:'UTF-8' })
    .ele('Complaint')
      .ele('Ticket').txt(ticket).up()
      .ele('CreatedAt').txt(now).up()
      .ele('Customer')
        .ele('Company').txt(u.company).up()
        .ele('Contact').txt(u.contact).up()
        .ele('Email').txt(u.email).up()
        .ele('Street').txt(u.street).up()
        .ele('ZIP').txt(u.zip).up()
        .ele('City').txt(u.city).up()
        .ele('Country').txt(u.country).up()
        .ele('Phone').txt(u.phone||'').up()
      .up()
      .ele('Data')
        .ele('Segment').txt(payload.data.segment).up()
        .ele('Article').txt(payload.data.article).up()
        .ele('Batch').txt(payload.data.batch).up()
        .ele('Quantity').txt(String(payload.data.qty||'')).up()
        .ele('Expiry').txt(String(payload.data.expiry||'')).up()
        .ele('Description').txt(payload.data.desc).up()
        .ele('Applied').txt(String(payload.data.applied||'')).up()
        .ele('Injury').txt(String(payload.data.injury||'')).up()
        .ele('InjuryDesc').txt(String(payload.data.injuryDesc||'')).up()
        .ele('Returned').txt(payload.data.returned).up()
        .ele('Handling').txt(payload.data.handling).up()
      .up()
    .up()
    .end({ prettyPrint: true });

  // E-Mail
  const attachments = [
    { filename: `${ticket}.xml`, content: Buffer.from(xml, 'utf8'), contentType: 'application/xml' },
    ...files.map((f,i)=>({ filename: f.originalname || `image_${i+1}.bin`, content: f.buffer, contentType: f.mimetype || 'application/octet-stream' }))
  ];
  const summary =
`Kunde: ${u.company} (${u.email})
Artikel: ${payload.data.article}
Bereich: ${payload.data.segment}
Charge: ${payload.data.batch}
Beschreibung: ${payload.data.desc}`;

  await send('complaint@dfs-diamon.de', tpl.complaintDFS(ticket, summary), attachments);
  await send(u.email, tpl.complaintCustomer(ticket)); // ohne Bilder

  await complaintSave(payload);
  return ok(res, { ticket });
}
