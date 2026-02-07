// api/_lib/pushDevices.js – helpers for admin push device management
import crypto from 'node:crypto';

export function hashPushToken(token) {
  const value = (token || '').toString().trim();
  if (!value) return '';
  return crypto.createHash('sha256').update(value).digest('hex');
}

export function normalizePushTokenEntry(entry) {
  if (!entry) return null;
  if (typeof entry === 'object') {
    const token = (entry.token || entry.deviceToken || entry.id || '').toString().trim();
    if (!token) return null;
    return { ...entry, token };
  }
  const token = entry.toString().trim();
  if (!token) return null;
  return { token };
}

export function deviceIdForEntry(entry) {
  const token = (entry?.token || '').toString().trim();
  if (!token) return '';
  const hash = hashPushToken(token);
  return (entry?.deviceId || entry?.device_id || entry?.id || hash).toString();
}

export function fingerprintForEntry(entry) {
  const token = (entry?.token || '').toString().trim();
  if (!token) return '';
  return (entry?.tokenHash || entry?.tokenFingerprint || hashPushToken(token)).toString();
}

export function deviceLabelForEntry(entry) {
  return (entry?.deviceLabel || entry?.deviceName || entry?.device_name || entry?.label || '')
    .toString()
    .trim();
}

export function mapDeviceEntry(entry) {
  const deviceId = deviceIdForEntry(entry);
  const tokenHashOrFingerprint = fingerprintForEntry(entry);
  return {
    deviceId,
    platform: (entry?.platform || '').toString(),
    deviceLabel: deviceLabelForEntry(entry),
    createdAt: Number(entry?.createdAt) || null,
    lastSeenAt: Number(entry?.updatedAt) || null,
    tokenHashOrFingerprint,
    isDisabled: entry?.isDisabled === true,
  };
}
