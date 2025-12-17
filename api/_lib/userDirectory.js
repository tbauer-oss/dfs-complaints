// api/_lib/userDirectory.js
import { normalizeUserId } from './chat.js';
import { portalUsersList } from './store.js';

function pickName(...candidates) {
  for (const candidate of candidates) {
    const value = (candidate ?? '').toString().trim();
    if (value && !value.includes('@')) return value;
  }
  return '';
}

function combinedName(firstName, lastName) {
  return [firstName, lastName].filter((v) => (v ?? '').toString().trim()).join(' ').trim();
}

export function resolvePortalDisplayName(user) {
  if (!user || typeof user !== 'object') return '';
  const firstName = user.firstName || user.firstname || user.first_name || '';
  const lastName = user.lastName || user.lastname || user.last_name || '';
  const fullName = user.fullName || user.full_name || user.name || '';
  const username = user.username || user.userName || '';

  const composedName = combinedName(firstName, lastName);

  return pickName(user.displayName, fullName, composedName, username, user.contact, user.company);
}

export async function buildPortalUserDirectory() {
  const directory = new Map();
  const users = await portalUsersList();
  for (const user of users) {
    const userId = normalizeUserId(user.email);
    if (!userId) continue;
    const displayName = resolvePortalDisplayName(user);
    if (!displayName) continue;
    directory.set(userId, displayName);
  }
  return directory;
}
