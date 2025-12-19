// api/chat/v1/_lib/groupIcons.js

export const GROUP_ICON_IDS = Object.freeze([
  'groups',
  'shipping',
  'build',
  'science',
  'assignment',
  'support',
  'inventory',
  'medical',
  'factory',
  'security',
  'chat',
]);

const GROUP_ICON_SET = new Set(GROUP_ICON_IDS);

export function isValidGroupIconId(value) {
  if (value === null) return true;
  if (value === undefined) return false;
  const trimmed = String(value).trim();
  if (!trimmed) return false;
  return GROUP_ICON_SET.has(trimmed);
}

export function normalizeGroupIconId(value) {
  if (value === null || value === undefined) return null;
  const trimmed = String(value).trim();
  if (!trimmed || !GROUP_ICON_SET.has(trimmed)) return null;
  return trimmed;
}
