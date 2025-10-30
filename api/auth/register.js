export const config = { runtime: 'nodejs' };

import bcrypt from 'bcryptjs';

// --- identischer CORS-Block wie in deiner Testdatei ---
const PROD_FE  = 'https://dfs-complaints-web.vercel.app';
const PREVIEW  = /^https:\/\/dfs-complaints-web-[a-z0-9-]+(?:-[a-z0-9-]+)?\.vercel\.app$/i;
function setCors(req, res) {
  const origin = req.headers?.origin || '';
  const allow = origin && (origin === PROD_FE || PREVIEW.test(origin)) ? origin : PROD_FE;
  res.setHeader('Access-Control-Allow-Origin', allow);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Admin-Secret');
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
}
function validEmail(s){ return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(s||'')); }

export default async function handler(req, res){
  setCors(req, res);
  if (req.method === 'OPTIONS') { res.statusCode = 204; return res.end(); }
  if (req.method !== 'POST')    { res.statusCode = 405; return res.end(JSON.stringify({ error: 'method not allowed' })); }

  try {
    const b = typeof req.body === 'object' ? req.body : JSON.parse(req.body ?? '{}');
    const required = ['email','password','password2','company','contact','street','zip','city','country','privacy'];
    for (const k of required) if (!b[k]) { res.statusCode=400; return res.end(JSON.stringify({ error:`missing ${k}` })); }
    if (!validEmail(b.email))            { res.statusCode=400; return res.end(JSON.stringify({ error:'invalid email' })); }
    if (b.password !== b.password2)      { res.statusCode=400; return res.end(JSON.stringify({ error:'password mismatch' })); }

    // ⚠️ Store erst JETZT laden (verhindert Preflight-Crash)
    const { pendingByEmail, pendingSave } = await import('../_lib/store.js');

    if (await pendingByEmail(b.email))   { res.statusCode=409; return res.end(JSON.stringify({ error:'already pending' })); }

    const hash = await bcrypt.hash(b.password, 10);
    const pending = {
      email: String(b.email).toLowerCase(),
      passhash: hash,
      company: b.company, contact: b.contact,
      street: b.street, zip: b.zip, city: b.city, country: b.country,
      phone: b.phone || '', createdAt: Date.now(), status: 'pending'
    };
    await pendingSave(pending);

    // Antwort zuerst
    res.statusCode = 200;
    res.end(JSON.stringify({ ok: true }));

    // Mails NACHGELAGERT laden & senden (falls Mail-Setup fehlt, crasht es nicht den Request)
    import('../_lib/mail.js')
      .then(({ send, notifyQM, tpl }) => Promise.allSettled([
        send(pending.email, tpl.afterRegisterToCustomer(pending.contact || pending.company)),
        notifyQM(tpl.afterRegisterToQM(pending.email)),
      ]))
      .catch(err => console.error('mail-load/send failed:', err));

  } catch (err) {
    console.error('register.js error:', err);
    res.statusCode = 500;
    res.end(JSON.stringify({ error: 'internal error' }));
  }
}
