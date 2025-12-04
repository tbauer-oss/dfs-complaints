// api/admin/translate.js
export const config = { runtime: 'nodejs' };

import { setCors, handlePreflight, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { translateTexts } from '../_lib/translate.js';
import { normalizeLangValue } from '../_lib/store.js';
import { requirePortalAccess } from './_guard.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { write: true });
  if (!actor) return;
  
  if (req.method !== 'POST') {
    return methodNotAllowed(res);
  }

  try {
    const body = readJson(req) || {};
    const sourceLang = normalizeLangValue(body.sourceLang) || null; // let DeepL auto-detect when missing
    const targets = Array.isArray(body.targets)
      ? body.targets.map((t) => normalizeLangValue(t)).filter(Boolean)
      : [];
    const textByKey = {};

    for (const key of ['question', 'answer', 'title', 'description']) {
      const raw = (body[key] ?? '').toString();
      if (raw.trim()) textByKey[key] = raw;
    }

    if (Object.keys(textByKey).length === 0) {
      return bad(res, 'question, answer, title or description required', 400);
    }

    const result = await translateTexts({
      textByKey,
      sourceLang,
      targetLangs: targets.length > 0 ? targets : ['de'],
    });
    return ok(res, result);
  } catch (e) {
    const msg = e?.message || 'translation failed';
    return bad(res, msg, 400);
  }
}

