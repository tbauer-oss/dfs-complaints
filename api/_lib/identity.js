export function normalizeEmail(email) {
  const raw = String(email ?? '').trim();
  if (!raw) return '';
  const normalized = typeof raw.normalize === 'function' ? raw.normalize('NFC') : raw;
  return normalized.toLowerCase();
}
