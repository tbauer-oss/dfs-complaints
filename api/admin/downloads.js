// api/admin/downloads.js
export const config = {
  runtime: 'nodejs',
  api: {
    // Wir lesen den Body selbst (siehe complaints), damit große Uploads sicher verarbeitet werden.
    bodyParser: false,
  },
};

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson, readJsonBody, noContent } from '../_lib/http.js';
import { downloadsList, downloadsUpsert, downloadsDelete } from '../_lib/store.js';
import { processIncomingFiles, normalizeProvidedUploads } from '../_lib/uploads.js';
import { requirePortalAccess } from './_guard.js';

async function parseUpload(body) {
  const provided = normalizeProvidedUploads(body?.uploads || body?.files || []);
  const providedWithLink = provided.find((p) => p?.downloadUrl || p?.url);
  if (providedWithLink) return { ...providedWithLink, downloadUrl: providedWithLink.downloadUrl || providedWithLink.url };

  const files = Array.isArray(body?.files)
    ? body.files
    : body?.file
      ? [body.file]
      : [];
  if (!files.length) return null;

  const processed = await processIncomingFiles(files, {
    // identische Fallbacks wie bei Reklamations-Uploads
    allowPreviewFallback: true,
    allowDataUrlFallback: true,
    maxTotalBytes: 25 * 1024 * 1024,
  });
  const upload = processed.uploads[0] || null;
  if (!upload) return null;
  return { ...upload, downloadUrl: upload.downloadUrl || upload.url };
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { write: req.method !== 'GET', tile: 'downloads' });
  if (!actor) return;

  try {
    console.log('[admin/downloads] enter', { method: req.method, query: req.query });
    if (req.method === 'GET') {
      const items = await downloadsList({ includeInactive: true });
      return ok(res, { items });
    }

    if (req.method === 'POST' || req.method === 'PUT') {
      let body;
      try {
        body = await readJsonBody(req);
      } catch (err) {
        const code = err?.statusCode || (err?.message === 'body too large' ? 413 : 400);
        return bad(res, err?.message || 'invalid body', code);
      }

      console.log('[admin/downloads] body', JSON.stringify({
        keys: body ? Object.keys(body) : [],
        hasFiles: Boolean(body?.files),
        hasUploads: Boolean(body?.uploads),
      }));

      let upload = null;
      try {
        upload = await parseUpload(body);
      } catch (err) {
        const msg = err?.message === 'files too large'
          ? 'files too large'
          : err?.message === 'invalid file encoding'
            ? 'invalid file encoding'
            : 'file upload failed';
        return bad(res, msg, 400);
      }

      const existing = body?.id
        ? (await downloadsList({ includeInactive: true })).find((d) => d.id === body.id)
        : null;

      if (!body?.title || !body.title.toString().trim()) {
        return bad(res, 'title required', 400);
      }

      if (!upload && !existing?.downloadUrl) {
        return bad(res, 'file required', 400);
      }

      const payload = {
        id: body.id,
        title: body.title,
        description: body.description,
        category: body.category,
        badge: body.badge,
        language: body.language,
        active: body.active,
        allowedRepresentatives: Array.isArray(body.allowedRepresentatives)
          ? body.allowedRepresentatives
          : body.allowedRepresentatives === null
            ? []
            : undefined,
        ...(upload
          ? {
              fileName: upload.name,
              mime: upload.mime,
              size: upload.size,
              downloadUrl: upload.downloadUrl || upload.url,
              uploadedAt: upload.uploadedAt,
            }
          : {}),
      };
      try {
        const saved = await downloadsUpsert(payload);
        return ok(res, saved);
      } catch (err) {
        console.error('[admin/downloads] payload invalid', err);
        const msg = err?.message || 'invalid download payload';
        return bad(res, msg, 400);
      }
    }

    if (req.method === 'DELETE') {
      const body = readJson(req) || {};
      const id = (body.id ?? req.query?.id ?? '').toString().trim();
      if (!id) return bad(res, 'id required', 400);
      await downloadsDelete(id);
      return noContent(res);
    }

    return methodNotAllowed(res);
  } catch (e) {
    console.error('[admin/downloads] error', e);
    return bad(res, e?.message || 'internal error', 500);
  }
}
