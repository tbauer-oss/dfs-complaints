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
