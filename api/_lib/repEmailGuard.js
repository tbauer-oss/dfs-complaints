// api/_lib/repEmailGuard.js
// Helper to prevent representative accounts from being treated as customers

import { loadRepByEmail } from './repsStore.js';

const normalize = (value) => (value ?? '').toString().trim().toLowerCase();

/**
 * Checks whether the given email belongs to a representative.
 * Fails safe: returns false if the lookup cannot be performed (e.g. missing Redis).
 */
export async function isRepEmail(email) {
  const normalized = normalize(email);
  if (!normalized) return false;

  try {
    const rep = await loadRepByEmail(normalized);
    return !!rep;
  } catch (err) {
    // In preview/local environments Redis might be missing; do not block registration
    console.warn('[repEmailGuard] rep lookup failed:', err?.message || err);
    return false;
  }
}

