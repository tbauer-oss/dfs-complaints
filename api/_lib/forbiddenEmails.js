export const FORBIDDEN_EMAILS = [
  'legacy.portal@dfs-diamon.de',
  'legacy.stale@dfs-diamon.de',
  'legacy.role-user@example.com',
  'invalid.creds@dfs-diamon.de',
  'legacy.trimmed@dfs-diamon.de',
];

const FORBIDDEN_SET = new Set(FORBIDDEN_EMAILS.map((email) => String(email).trim().toLowerCase()));

export function normalizeEmail(email) {
  return String(email || '').trim().toLowerCase();
}

export function forbiddenEmailReason(email) {
  const normalized = normalizeEmail(email);
  if (!normalized) return null;

  const localPart = normalized.split('@')[0] || '';
  if (FORBIDDEN_SET.has(normalized)) return 'forbidden_email_list';
  if (normalized.startsWith('legacy.') || localPart.startsWith('legacy.')) return 'forbidden_legacy_prefix';
  if (normalized.includes('invalid')) return 'forbidden_invalid_marker';
  if (normalized.includes('example.com')) return 'forbidden_example_domain';
  return null;
}

export function isForbiddenEmail(email) {
  return Boolean(forbiddenEmailReason(email));
}

export function logSecurityEvent({ req, email, reason }) {
  const endpoint = String(req?.url || req?.originalUrl || req?.path || req?.route?.path || 'unknown');
  const ip =
    String(
      req?.headers?.['x-forwarded-for']
      || req?.headers?.['x-real-ip']
      || req?.socket?.remoteAddress
      || req?.ip
      || 'unknown',
    )
      .split(',')[0]
      .trim();

  console.warn('[security] blocked_auth_operation', {
    timestamp: new Date().toISOString(),
    ip,
    email: normalizeEmail(email),
    endpoint,
    reason: String(reason || 'forbidden_email'),
  });
}

