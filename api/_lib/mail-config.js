// /api/_lib/mail-config.js
// Zentrale Auflösung der SMTP-/Mail-Umgebungsvariablen mit Fallbacks

function clean(value) {
  return typeof value === 'string' ? value.trim() : '';
}

export function resolveMailConfig(env = process.env) {
  const host =
    clean(env.SMTP_HOST) ||
    clean(env.MAIL_HOST) ||
    clean(env.SMTP_SERVER) ||
    clean(env.MAIL_SERVER);

  const portRaw =
    clean(env.SMTP_PORT) ||
    clean(env.MAIL_PORT) ||
    clean(env.SMTP_SERVER_PORT) ||
    clean(env.MAIL_SERVER_PORT);
  const port = Number(portRaw) || 587;

  const user =
    clean(env.SMTP_USER) ||
    clean(env.SMTP_LOGIN) ||
    clean(env.SMTP_EMAIL) ||
    clean(env.MAIL_USER) ||
    clean(env.MAIL_LOGIN) ||
    clean(env.MAIL_EMAIL);

  const pass =
    clean(env.SMTP_PASS) ||
    clean(env.SMTP_PASSWORD) ||
    clean(env.MAIL_PASS) ||
    clean(env.MAIL_PASSWORD);
  const from = clean(env.SMTP_FROM) || clean(env.MAIL_FROM) || user;
  const replyTo = clean(env.MAIL_REPLY_TO) || clean(env.SMTP_REPLY_TO);
  const qm = clean(env.MAIL_QM);

  return {
    host: host || null,
    port,
    user: user || null,
    pass: pass || null,
    from: from || null,
    replyTo: replyTo || null,
    qm: qm || null,
  };
}

export function mailConfigOk(cfg = resolveMailConfig()) {
  const missing = [];
  if (!cfg.host) missing.push('SMTP_HOST');
  if (!cfg.user) missing.push('SMTP_USER');
  if (!cfg.pass) missing.push('SMTP_PASS');
  return { ok: missing.length === 0, missing };
}
