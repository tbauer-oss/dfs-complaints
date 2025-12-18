// /api/chat/v1/admin/avatar.js
export const config = { runtime: 'nodejs' };

import { put } from '@vercel/blob';
import {
  bad,
  handlePreflight,
  methodNotAllowed,
  noContent,
  ok,
  readJsonBody,
  setCors,
} from '../../../_lib/http.js';
import { normalizeRole, portalUserFromRequest, PORTAL_ROLES } from '../../../_lib/portalAuth.js';
import { createTrackedRedis, logRedisUsage } from '../_lib/redisTracker.js';
import { createRedisAdapter } from '../_lib/redisAdapter.js';
import { keyAvatarMap, normalizeUserId } from '../_lib/schema.js';

const MAX_AVATAR_BYTES = 2 * 1024 * 1024;
const ALLOWED_MIME = new Set(['image/png', 'image/jpeg', 'image/webp']);

function requireSuperuser(actor) {
  if (!actor) return false;
  return normalizeRole(actor.role) === PORTAL_ROLES.superuser;
}

function parseDataUrl(input) {
  const raw = (input ?? '').toString().trim();
  if (!raw) return null;

  const match = raw.match(/^data:(image\/(png|jpe?g|webp));base64,(.+)$/i);
  if (!match) return null;

  const mime = match[1].toLowerCase();
  if (!ALLOWED_MIME.has(mime)) return null;

  let buffer;
  try {
    buffer = Buffer.from(match[3], 'base64');
  } catch (err) {
    const error = new Error('invalid image encoding');
    error.cause = err;
    throw error;
  }

  if (!buffer?.length) return null;
  if (buffer.length > MAX_AVATAR_BYTES) {
    const error = new Error('avatar too large');
    error.code = 'LIMIT_EXCEEDED';
    throw error;
  }

  const ext = mime === 'image/png' ? 'png' : mime === 'image/webp' ? 'webp' : 'jpg';
  return { buffer, mime, ext };
}

async function uploadAvatar(uid, image) {
  const safeUid = uid.replace(/[^a-z0-9@._+-]+/gi, '-');
  const filename = `chat/avatars/${safeUid}-${Date.now()}.${image.ext}`;
  const uploaded = await put(filename, image.buffer, { access: 'public', contentType: image.mime });
  return uploaded?.url || null;
}

async function handlePost(req, res) {
  let body = {};
  try {
    body = await readJsonBody(req, { limitBytes: MAX_AVATAR_BYTES * 2 });
  } catch (err) {
    console.error('[chat/admin/avatar] invalid json', err);
    return bad(res, err?.statusCode === 413 ? 'payload too large' : 'invalid payload', err?.statusCode || 400);
  }

  const email = normalizeUserId(body?.email);
  if (!email) return bad(res, 'invalid email', 400);

  let parsed;
  try {
    parsed = parseDataUrl(body?.croppedImage);
  } catch (err) {
    console.error('[chat/admin/avatar] parse error', err);
    return bad(res, 'invalid image', 400);
  }

  if (!parsed) return bad(res, 'invalid image', 400);

  try {
    const url = await uploadAvatar(email, parsed);
    if (!url) return bad(res, 'upload failed', 500);

    const { client, counters } = createTrackedRedis();
    const rdb = createRedisAdapter(client);
    await rdb.hset(keyAvatarMap(), { [email]: url });
    logRedisUsage('[chat/admin/avatar] upload', counters, { email });

    return ok(res, { ok: true, url });
  } catch (err) {
    console.error('[chat/admin/avatar] upload error', err);
    return bad(res, 'upload failed', 500);
  }
}

async function handleDelete(req, res) {
  const email = normalizeUserId(req.query?.email);
  if (!email) return bad(res, 'invalid email', 400);

  try {
    const { client, counters } = createTrackedRedis();
    const rdb = createRedisAdapter(client);
    await rdb.hdel(keyAvatarMap(), email);
    logRedisUsage('[chat/admin/avatar] delete', counters, { email });
    return noContent(res);
  } catch (err) {
    console.error('[chat/admin/avatar] delete error', err);
    return bad(res, 'server error', 500);
  }
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await portalUserFromRequest(req);
  if (!actor) return bad(res, 'unauthorized', 401);
  if (!requireSuperuser(actor)) return bad(res, 'forbidden', 403);

  if (req.method === 'POST') return handlePost(req, res);
  if (req.method === 'DELETE') return handleDelete(req, res);

  return methodNotAllowed(res);
}
