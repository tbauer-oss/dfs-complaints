// api/admin/translate.js
export const config = { runtime: 'nodejs' };

import { setCors, handlePreflight, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { normalizeLangValue } from '../_lib/store.js';
import { translateTexts, translationProviderReady } from '../_lib/translate.js';

function requireAdmin(req, res) {
  const sec = (req.headers?.['x-admin-secret'] || '').toString().trim();
  const expected = (process.env.ADMIN_SECRET || '').toString().trim();
  if (!sec || !expected || sec !== expected) {
    bad(res, 'unauthorized', 401);
    return false;
  }
  return true;
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  if (!requireAdmin(req, res)) return;

  if (req.method !== 'POST') {
    return methodNotAllowed(res);
  }

  try {
    if (!translationProviderReady()) {
      return bad(res, 'automatic translation not configured', 503);
    }

    const body = readJson(req) || {};
    const sourceLang = normalizeLangValue(body.sourceLang) || 'de';
    const targets = Array.isArray(body.targets) ? body.targets : [];
    const textByKey = {};

    for (const key of ['question', 'answer']) {
      const raw = (body[key] ?? '').toString();
      if (raw.trim()) textByKey[key] = raw;
    }

    if (Object.keys(textByKey).length === 0) {
      return bad(res, 'question or answer required', 400);
    }

    const result = await translateTexts({ textByKey, sourceLang, targetLangs: targets });
    return ok(res, result);
  } catch (e) {
    const msg = e?.message || 'translation failed';
    return bad(res, msg, 400);
  }
}

