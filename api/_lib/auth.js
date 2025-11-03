// api/_lib/auth.js
export const ADMIN_SECRET = process.env.ADMIN_SECRET || '';

export function secureEquals(a = '', b = '') {
  const aa = Buffer.from(String(a));
  const bb = Buffer.from(String(b));
  if (aa.length !== bb.length) return false;
  let out = 0;
  for (let i = 0; i < aa.length; i++) out |= aa[i] ^ bb[i];
  return out === 0;
}

export function isAdmin(req, { debug = false } = {}) {
  const hdr = String(req.headers?.['x-admin-secret'] ?? '');
  const ok  = !!ADMIN_SECRET && !!hdr && secureEquals(hdr, ADMIN_SECRET);
  if (!ok && debug) {
    console.warn('admin unauthorized', {
      gotLen: hdr.length,
      envLen: ADMIN_SECRET.length,
      hasEnv: ADMIN_SECRET ? true : false,
    });
  }
  return ok;
}
