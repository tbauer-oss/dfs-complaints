import { del, put } from '@vercel/blob';
import { randomUUID } from 'node:crypto';

const MAX_PREVIEW_CHARS = 200000;
const DEFAULT_MAX_TOTAL_BYTES = Number(process.env.MAX_UPLOAD_BYTES || 8 * 1024 * 1024);

const RAW_RW_TOKEN = (process.env.BLOB_READ_WRITE_TOKEN || '').trim();
const RAW_LEGACY_TOKEN = (process.env.BLOB_TOKEN || '').trim();
const EFFECTIVE_BLOB_TOKEN = RAW_RW_TOKEN || RAW_LEGACY_TOKEN;

if (!RAW_RW_TOKEN && RAW_LEGACY_TOKEN) {
  process.env.BLOB_READ_WRITE_TOKEN = RAW_LEGACY_TOKEN;
}

const BLOB_TOKEN = EFFECTIVE_BLOB_TOKEN;

export const blobUploadsEnabled = Boolean(BLOB_TOKEN);

export function normalizePreview(value) {
  const str = (value ?? '').toString().trim();
  if (!str) return undefined;
  return str.length > MAX_PREVIEW_CHARS ? str.slice(0, MAX_PREVIEW_CHARS) : str;
}

function normalizeUrl(value) {
  const raw = (value ?? '').toString().trim();
  if (!raw) return undefined;
  if (!/^https?:\/\//i.test(raw)) return undefined;
  return raw;
}

function normalizeUploadedAt(value) {
  if (value == null) return undefined;
  if (typeof value === 'number') {
    const int = Math.trunc(value);
    return int > 0 ? int : undefined;
  }
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (!trimmed) return undefined;
    const numeric = Number(trimmed);
    if (Number.isFinite(numeric)) {
      const int = Math.trunc(numeric);
      return int > 0 ? int : undefined;
    }
    const parsed = Date.parse(trimmed);
    if (!Number.isNaN(parsed) && parsed > 0) return parsed;
  }
  return undefined;
}

function normalizeSize(value) {
  if (typeof value === 'number') {
    const int = Math.trunc(value);
    return int > 0 ? int : 0;
  }
  if (typeof value === 'string') {
    const num = Number(value.trim());
    if (Number.isFinite(num)) {
      const int = Math.trunc(num);
      return int > 0 ? int : 0;
    }
  }
  return 0;
}

function sanitizeFilename(name) {
  const raw = (name ?? '').toString().split(/[\\/]/).pop() || 'upload';
  return raw.replace(/[^a-z0-9._-]+/gi, '-').replace(/-+/g, '-').replace(/^-+|-+$/g, '').slice(0, 80) || 'file';
}

function buildBlobPath(ticket, filename) {
  const safeTicket = (ticket ?? '').toString().replace(/[^a-z0-9]/gi, '').slice(-10).toLowerCase();
  const prefix = safeTicket ? `complaints/${safeTicket}` : 'complaints/general';
  const stamp = Date.now();
  const suffix = randomUUID().replace(/-/g, '');
  return `${prefix}/${stamp}-${suffix}-${filename}`;
}

function blobPathFromUrl(input) {
  const raw = (input ?? '').toString().trim();
  if (!raw) return null;
  try {
    const { pathname } = new URL(raw);
    const cleaned = (pathname || '').replace(/^\/+/, '').trim();
    return cleaned || null;
  } catch {
    return null;
  }
}

function collectBlobPaths(uploads = []) {
  const paths = [];
  for (const entry of uploads) {
    if (!entry) continue;
    if (typeof entry === 'string') {
      const urlPath = blobPathFromUrl(entry);
      if (urlPath) paths.push(urlPath);
      continue;
    }

    const raw = entry?.blobPath || entry?.blobpath || '';
    const normalized = (raw || '').toString().trim();
    if (normalized) {
      paths.push(normalized);
      continue;
    }

    const urlPath = blobPathFromUrl(entry?.downloadUrl || entry?.url);
    if (urlPath) paths.push(urlPath);
  }

  return Array.from(new Set(paths.filter(Boolean)));
}

async function resolveTicket(ticket) {
  if (typeof ticket === 'function') return await ticket();
  return ticket;
}

async function uploadBuffer(buffer, { ticket, filename, mime }) {
  if (!blobUploadsEnabled || !buffer?.length) return null;
  const safeName = sanitizeFilename(filename);
  const resolvedTicket = await resolveTicket(ticket);
  const key = buildBlobPath(resolvedTicket, safeName);
  const blob = await put(key, buffer, {
    access: 'public',
    contentType: (mime || 'application/octet-stream').toString(),
  });
  if (!blob) return null;
  const out = {};
  if (blob.url) out.url = blob.url;
  if (blob.downloadUrl) out.downloadUrl = blob.downloadUrl;
  else if (blob.url) out.downloadUrl = blob.url;
  if (blob.pathname) out.blobPath = blob.pathname;
  if (blob.size != null) out.size = blob.size;
  if (blob.uploadedAt != null) out.uploadedAt = blob.uploadedAt;
  return out;
}

export async function processIncomingFiles(filesInput, {
  ticket,
  includeMailAttachments = false,
  allowPreviewFallback = !blobUploadsEnabled,
  allowDataUrlFallback = !blobUploadsEnabled,
  maxTotalBytes = DEFAULT_MAX_TOTAL_BYTES,
} = {}) {
  const files = Array.isArray(filesInput) ? filesInput : [];
  const uploads = [];
  const attachments = [];
  let totalBytes = 0;

  for (let i = 0; i < files.length; i += 1) {
    const raw = files[i] || {};
    const base64 = ((raw.bytes || raw.data || '') + '').trim();
    if (!base64) continue;

    let buffer;
    try {
      buffer = Buffer.from(base64, 'base64');
    } catch (err) {
      const error = new Error('invalid file encoding');
      error.cause = err;
      throw error;
    }
    if (!buffer.length) continue;

    totalBytes += buffer.length;
    if (maxTotalBytes > 0 && totalBytes > maxTotalBytes) {
      const error = new Error('files too large');
      throw error;
    }

    const entry = {
      name: (raw.name || `attachment_${i + 1}`).toString(),
      mime: (raw.mime || 'application/octet-stream').toString(),
      size: buffer.length,
      uploadedAt: Date.now(),
    };

    try {
      const blob = await uploadBuffer(buffer, { ticket, filename: entry.name, mime: entry.mime });
      if (blob?.url) entry.url = blob.url;
      if (blob?.downloadUrl) entry.downloadUrl = blob.downloadUrl;
      if (blob?.blobPath) entry.blobPath = blob.blobPath;
    } catch (err) {
      console.error('[uploads] blob upload failed', err?.message || err);
      // Erlaube einen Fallback, damit Admin-Uploads nicht mit 500 enden, wenn
      // das Blob-Backend nicht erreichbar oder falsch konfiguriert ist.
      if (!allowDataUrlFallback) {
        throw new Error('blob upload failed');
      }
    }

    // Fallback für Umgebungen ohne oder mit defektem Blob-Storage: stelle einen
    // Data-URL-Download bereit, damit Admin-Uploads dennoch funktionieren. Die
    // Upload-Größe wird upstream durch maxTotalBytes begrenzt, sodass die Data-URL
    // handhabbar bleibt.
    if (allowDataUrlFallback && !entry.downloadUrl) {
      entry.downloadUrl = `data:${entry.mime};base64,${base64}`;
    }

    if (!entry.url && allowPreviewFallback) {
      const preview = normalizePreview(raw.preview);
      if (preview) entry.preview = preview;
    }

    uploads.push(entry);

    if (includeMailAttachments) {
      attachments.push({
        filename: entry.name || `attachment_${i + 1}.bin`,
        content: buffer,
        contentType: entry.mime || 'application/octet-stream',
      });
    }
  }

  return { uploads, attachments, totalBytes };
}

export async function storeGeneratedFile(buffer, {
  ticket,
  filename,
  mime = 'application/octet-stream',
  allowDataUrlFallback = true,
  preferDataUrlFallback = false,
} = {}) {
  if (!buffer || !buffer.length) return null;

  const entry = {
    name: filename || 'file.bin',
    mime,
    size: buffer.length,
    uploadedAt: Date.now(),
  };

  if (!preferDataUrlFallback) {
    try {
      const blob = await uploadBuffer(buffer, { ticket, filename, mime });
      if (blob?.url) entry.url = blob.url;
      if (blob?.downloadUrl) entry.downloadUrl = blob.downloadUrl;
      if (blob?.blobPath) entry.blobPath = blob.blobPath;
      if (blob?.size != null) entry.size = blob.size;
      if (blob?.uploadedAt != null) entry.uploadedAt = blob.uploadedAt;
      if (entry.downloadUrl) return entry;
    } catch (err) {
      console.error('[uploads] storeGeneratedFile blob upload failed', err?.message || err);
      if (!allowDataUrlFallback) return null;
    }
  }

  if (allowDataUrlFallback) {
    const base64 = buffer.toString('base64');
    entry.downloadUrl = `data:${mime};base64,${base64}`;
    return entry;
  }

  return null;
}

export async function deleteUploadsFromBlob(uploads = []) {
  if (!blobUploadsEnabled) return false;
  const paths = collectBlobPaths(uploads);
  if (!paths.length) return false;
  try {
    await del(paths);
    return true;
  } catch (err) {
    console.error('[uploads] failed to delete blob files', err?.message || err);
    return false;
  }
}

export function normalizeProvidedUploads(input) {
  const list = Array.isArray(input) ? input : [];
  const uploads = [];
  for (const raw of list) {
    if (!raw) continue;
    const entry = {
      name: (raw.name || '').toString(),
      mime: (raw.mime || 'application/octet-stream').toString(),
      size: normalizeSize(raw.size),
    };
    const uploadedAt = normalizeUploadedAt(raw.uploadedAt || raw.createdAt);
    if (uploadedAt) entry.uploadedAt = uploadedAt;
    const url = normalizeUrl(raw.url || raw.previewUrl);
    if (url) entry.url = url;
    const downloadUrl = normalizeUrl(raw.downloadUrl || raw.downloadURL);
    if (downloadUrl) entry.downloadUrl = downloadUrl;
    const blobPath = (raw.blobPath || raw.pathname || '').toString().trim();
    if (blobPath) entry.blobPath = blobPath;
    const preview = normalizePreview(raw.preview);
    if (preview) entry.preview = preview;
    uploads.push(entry);
  }
  return uploads;
}
