// api/support.js
export const config = { runtime: 'nodejs' };

import { setCors, ok, bad, noContent, methodNotAllowed } from './_lib/http.js';
import { getAuthUser } from './_lib/auth.js';
import { getRepOf } from './_lib/repsStore.js';
import { send, tpl } from './_lib/mail.js';

const QM_MAIL = process.env.MAIL_QM || 'complaint@dfs-diamon.de';

const LANGS = new Set(['de', 'en', 'fr', 'it', 'es']);
function normLang(x) {
  const lc = String(x || '').toLowerCase();
  const two = lc.split(/[-_]/)[0];
  return LANGS.has(two) ? two : 'de';
}

function asString(v) {
  return typeof v === 'string' ? v.trim() : '';
}

const CATS = new Set(['general','complaint','technical','account','privacy','feedback','improve','other']);

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return noContent(res);
  if (req.method !== 'POST') return methodNotAllowed(res);

  const user = getAuthUser(req);
  if (!user) return bad(res, 'unauthorized', 401);

  const body = typeof req.body === 'object' ? req.body : JSON.parse(req.body ?? '{}');
  const cat = (body?.category || 'other').toString().toLowerCase();
  const text = (body?.message || '').toString();
  const consent = !!body?.consent;

  if (!CATS.has(cat)) return bad(res, 'invalid category', 400);
  if (!text.trim()) return bad(res, 'empty message', 400);
  if (!consent) return bad(res, 'consent required', 400);

  const lang = normLang(user?.lang || req.headers['accept-language']);

  let rep = null;
  try {
    rep = await getRepOf(user.email);
  } catch (err) {
    console.warn('[support] failed to load rep', err?.message || err);
  }

  const repEmail = asString(rep?.email);
  const hasRep = repEmail.includes('@');
  const target = hasRep ? repEmail : QM_MAIL;
  const contactName = asString(user?.contact || user?.contactName || user?.name);
  const company = asString(user?.company || user?.customer || user?.customerName);
  const subject = `[DFS Support] ${cat} von ${user.email}`;

  const lines = [
    'Kontakt über das DFS Kundenportal – Support',
    '',
    `Kategorie: ${cat}`,
    `Kunden-E-Mail: ${user.email}`,
  ];
  if (company) lines.push(`Kunde: ${company}`);
  if (contactName) lines.push(`Kontaktperson: ${contactName}`);
  lines.push('');
  lines.push('--- Nachricht ---');
  lines.push('');
  lines.push(text);

  await send(target, {
    subject,
    text: lines.join('\n'),
    lang: 'de',
  });

  if (user?.email) {
    try {
      const confirmation = tpl.messageConfirmation(
        {
          name: contactName,
          subject,
          message: text,
          channel: hasRep ? 'rep' : 'support',
        },
        lang,
      );

      await send(user.email, {
        ...confirmation,
        lang,
      });
    } catch (err) {
      console.error('support confirmation mail failed', err);
    }
  }

  return ok(res, { ok: true });
}
