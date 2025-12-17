// api/_lib/userDirectory.js
import { portalUsersList } from './store.js';

function normalizeUserId(raw) {
  const value = String(raw || '').trim();
  if (!value) return null;
  const lowered = value.toLowerCase();
  if (!lowered.includes('@')) return lowered;
  return Buffer.from(lowered, 'utf8').toString('base64url').replace(/=+$/, '');
}

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
  const picked = pickName(user.displayName, fullName, composedName, username, user.contact, user.company);
  if (picked) return picked;

  const email = (user.email || '').toString();
  if (email.includes('@')) {
    const local = email.split('@')[0]
      .replace(/[._-]+/g, ' ')
      .trim();
    if (local) return local;
  }

  return '';
}

export async function buildPortalUserDirectory() {
  const directory = new Map();
  const users = await portalUsersList();
  for (const user of users) {
    const aliases = new Set();
    const email = (user.email || '').toString().trim().toLowerCase();
    if (email) aliases.add(email);
    const emailId = normalizeUserId(email);
    if (emailId) {
      aliases.add(emailId);
      aliases.add(emailId.toLowerCase());
    }

    const username = (user.username || user.userName || user.login || '').toString().trim().toLowerCase();
    if (username) aliases.add(username);
    const usernameId = normalizeUserId(username);
    if (usernameId) {
      aliases.add(usernameId);
      aliases.add(usernameId.toLowerCase());
    }

    for (const alias of Array.from(aliases.values())) {
      aliases.add(alias.toLowerCase());
    }

    const displayName = resolvePortalDisplayName(user);
    if (!displayName) continue;

    for (const alias of aliases) {
      directory.set(alias, displayName);
    }
  }
  return directory;
}
