import crypto from 'crypto';

export function isStrongPassword(pw) {
  const s = String(pw || '');
  if (s.length < 8) return false;
  const hasLetter = /[A-Za-z]/.test(s);
  const hasNumber = /[0-9]/.test(s);
  const hasSpecial = /[^A-Za-z0-9]/.test(s);
  return hasLetter && hasNumber && hasSpecial;
}

export function assertStrongPassword(pw) {
  if (!isStrongPassword(pw)) {
    throw new Error('password requirements not met');
  }
}

export function generateStrongPassword(length = 8) {
  const len = Math.max(8, Number(length) || 8);
  const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  const numbers = '23456789';
  const specials = '!#$%&*+-?@';
  const all = `${letters}${numbers}${specials}`;

  for (let attempt = 0; attempt < 100; attempt += 1) {
    const bytes = crypto.randomBytes(len);
    let pw = '';
    for (let i = 0; i < len; i += 1) {
      const idx = bytes[i] % all.length;
      pw += all[idx];
    }
    if (isStrongPassword(pw)) return pw;
  }

  // Fallback: deterministic mix, should never happen but keeps function total.
  const fallback = `${letters[0]}${letters[1]}${numbers[0]}${numbers[1]}${specials[0]}${specials[1]}Aa1!`;
  return fallback.slice(0, len);
}
