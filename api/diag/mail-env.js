// /api/diag/mail-env.js  (ersetzen)
export const config = { runtime: 'nodejs' };
export default async function handler(_req, res){
  const p = process.env.SMTP_PASS || '';
  const mask = (s) => s ? s.slice(0,2)+'***'+s.slice(-2) : null;
  res.setHeader('Content-Type','application/json');
  res.end(JSON.stringify({
    host: process.env.SMTP_HOST,
    port: process.env.SMTP_PORT,
    secure: process.env.SMTP_SECURE,
    user: process.env.SMTP_USER,
    passMasked: p ? mask(p) : '(missing)',
    passLen: p.length,
    from: process.env.MAIL_FROM,
    env: process.env.VERCEL_ENV || process.env.NODE_ENV
  }));
}
