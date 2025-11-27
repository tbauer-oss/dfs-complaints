// api/admin/downloads.js
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson, noContent } from '../_lib/http.js';
import { downloadsList, downloadsUpsert, downloadsDelete } from '../_lib/store.js';
import { processIncomingFiles, normalizeProvidedUploads } from '../_lib/uploads.js';

const ADMIN_SECRET = process.env.ADMIN_SECRET || '';

function requireAdmin(req, res) {
  const hdr = (req.headers?.['x-admin-secret'] || '').toString().trim();
  if (!ADMIN_SECRET || hdr !== ADMIN_SECRET) {
    bad(res, 'unauthorized', 401);
    return false;
  }
  return true;
}

async function parseUpload(body) {
  const provided = normalizeProvidedUploads(body?.uploads || body?.files || []);
  if (provided.length) return provided[0];
  const files = Array.isArray(body?.files) ? body.files : body?.file ? [body.file] : [];
  if (!files.length) return null;
  const processed = await processIncomingFiles(files, { allowPreviewFallback: true, maxTotalBytes: 25 * 1024 * 1024 });
  return processed.uploads[0] || null;
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  if (!requireAdmin(req, res)) return;

  try {
    if (req.method === 'GET') {
      const items = await downloadsList({ includeInactive: true });
      return ok(res, { items });
    }

    if (req.method === 'POST' || req.method === 'PUT') {
      const body = readJson(req) || {};
      const upload = await parseUpload(body);
      const payload = {
        id: body.id,
        title: body.title,
        description: body.description,
        category: body.category,
        badge: body.badge,
        active: body.active,
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
      const saved = await downloadsUpsert(payload);
      return ok(res, saved);
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
