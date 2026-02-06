import jwt from 'jsonwebtoken';
import { hashGateCode } from './gate.js';
import { gateStoreGet, gateStoreDelete } from './store.js';

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const GATE_JWT_TTL = Number(process.env.GATE_JWT_TTL || 15 * 60);
const JWT_SECRET = process.env.JWT_SECRET || '';

export class GateError extends Error {
  constructor(code, message, statusCode = 400) {
    super(message);
    this.code = code;
    this.statusCode = statusCode;
  }
}

export function normalizeGateEmail(value) {
  return String(value || '').trim().toLowerCase();
}

export function isValidGateEmail(value) {
  return EMAIL_REGEX.test(normalizeGateEmail(value));
}

export async function consumeGateCodeOnce(emailInput, codeInput) {
  const email = normalizeGateEmail(emailInput);
  if (!email) throw new GateError('missing_email', 'missing email', 400);
  if (!isValidGateEmail(email)) throw new GateError('invalid_email', 'invalid email', 400);

  const code = String(codeInput || '').trim();
  if (!code) throw new GateError('missing_code', 'missing gate code', 400);

  const stored = await gateStoreGet(email);
  if (!stored || !stored.codeHash) {
    throw new GateError('invalid_code', 'invalid gate code', 400);
  }

  if (stored.used) {
    await gateStoreDelete(email).catch(() => {});
    throw new GateError('code_used', 'gate code already used', 410);
  }

  const providedHash = hashGateCode(code);
  if (!providedHash || providedHash !== stored.codeHash) {
    throw new GateError('invalid_code', 'invalid gate code', 400);
  }

  await gateStoreDelete(email).catch(() => {});

  return {
    email,
    meta: stored.meta || null,
    createdAt: stored.createdAt || null,
  };
}

export function issueGateToken(emailInput) {
  const email = normalizeGateEmail(emailInput);
  if (!email) throw new GateError('invalid_email', 'invalid email', 400);
  if (!isValidGateEmail(email)) throw new GateError('invalid_email', 'invalid email', 400);
  if (!JWT_SECRET) throw new GateError('server_misconfigured', 'server misconfigured', 500);

  const payload = { sub: email, type: 'gate' };
  const ttlSeconds = Number.isFinite(GATE_JWT_TTL) && GATE_JWT_TTL > 0
    ? Math.round(GATE_JWT_TTL)
    : null;

  const token = jwt.sign(payload, JWT_SECRET, ttlSeconds ? { expiresIn: ttlSeconds } : undefined);
  return { token, payload, expiresIn: ttlSeconds || null };
}
