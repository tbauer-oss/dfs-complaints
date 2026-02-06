import crypto from 'crypto';

const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const CODE_LENGTH = 8;

function pickChar() {
  const idx = crypto.randomInt(0, ALPHABET.length);
  return ALPHABET[idx];
}

export function randomGateCode() {
  let code = '';
  while (code.length < CODE_LENGTH) {
    code += pickChar();
  }
  return `${code.slice(0, 4)}-${code.slice(4, 8)}`;
}

export function normalizeGateCode(input) {
  return String(input || '')
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, '')
    .slice(0, CODE_LENGTH);
}

export function hashGateCode(input) {
  const normalized = normalizeGateCode(input);
  if (!normalized) return null;
  return crypto.createHash('sha256').update(normalized).digest('hex');
}
