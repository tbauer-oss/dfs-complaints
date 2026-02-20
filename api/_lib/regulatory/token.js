import crypto from 'node:crypto';

const SECRET = String(process.env.REGULATORY_SYNC_TOKEN_SECRET || '').trim();

function b64(input) {
  return Buffer.from(input).toString('base64url');
}

export function signSyncToken(payload) {
  if (!SECRET) throw new Error('REGULATORY_SYNC_TOKEN_SECRET missing');
  const body = b64(JSON.stringify(payload));
  const sig = crypto.createHmac('sha256', SECRET).update(body).digest('base64url');
  return `${body}.${sig}`;
}

export function verifySyncToken(token) {
  if (!SECRET) throw new Error('REGULATORY_SYNC_TOKEN_SECRET missing');
  const [body, sig] = String(token || '').split('.');
  if (!body || !sig) throw new Error('invalid sync token');
  const expected = crypto.createHmac('sha256', SECRET).update(body).digest('base64url');
  if (expected !== sig) throw new Error('invalid sync token signature');
  const payload = JSON.parse(Buffer.from(body, 'base64url').toString('utf8'));
  if (!payload?.exp || Date.now() > Number(payload.exp)) throw new Error('sync token expired');
  return payload;
}
