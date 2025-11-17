export const config = { runtime: 'nodejs' };

import jwt from 'jsonwebtoken';
import { handlePreflight, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { hashGateCode } from '../_lib/gate.js';
import { gateStoreGet, gateStoreDelete } from '../_lib/store.js';

const JWT_SECRET = process.env.JWT_SECRET || '';
const isPreview = process.env.VERCEL_ENV !== 'production';
const GATE_JWT_TTL = Number(process.env.GATE_JWT_TTL || 15 * 60); // seconds
const validEmail = (value) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(value || ''));

function normalizeEmail(value) {
  return String(value || '').trim().toLowerCase();
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  if (req.method !== 'POST') return methodNotAllowed(res);
  if (!JWT_SECRET) return bad(res, 'server misconfigured', 500);

  try {
    const body = readJson(req);
    const email = normalizeEmail(body.email);
    const code = String(body.code || body.pass || '').trim();

    if (!email) return bad(res, 'missing email', 400);
    if (!validEmail(email)) return bad(res, 'invalid email', 400);
    if (!code) return bad(res, 'missing code', 400);

    const stored = await gateStoreGet(email);
    if (!stored || !stored.codeHash) return bad(res, 'invalid gate code', 400);
    if (stored.used) {
      await gateStoreDelete(email);
      return bad(res, 'gate code already used', 410);
    }

    const providedHash = hashGateCode(code);
    if (!providedHash || providedHash !== stored.codeHash) {
      return bad(res, 'invalid gate code', 400);
    }

    await gateStoreDelete(email);

    const payload = { sub: email, type: 'gate' };
    const ttlSeconds = Number.isFinite(GATE_JWT_TTL) && GATE_JWT_TTL > 0
      ? Math.round(GATE_JWT_TTL)
      : null;
    const token = jwt.sign(payload, JWT_SECRET, ttlSeconds ? { expiresIn: ttlSeconds } : undefined);

    return ok(res, {
      ok: true,
      token,
      type: 'gate',
      email,
      expiresIn: ttlSeconds || null,
    });
  } catch (err) {
    console.error('gate-verify fatal:', err);
    const msg = isPreview ? err?.message || String(err) : 'internal error';
    return bad(res, msg, 500);
  }
}
