import { normalizeText } from './normalize.js';
import { sha256 } from './hash.js';

function excerpt(text = '', maxLen = 200) {
  const value = normalizeText(text);
  return value.length <= maxLen ? value : `${value.slice(0, maxLen)}…`;
}

function normalizedHash(section) {
  const normalizedText = normalizeText(section?.content_text || '');
  return {
    normalized_text: normalizedText,
    hash: sha256(normalizedText),
  };
}

function changeRow(sectionKey, type, beforeSection, afterSection) {
  const before = beforeSection ? normalizedHash(beforeSection) : null;
  const after = afterSection ? normalizedHash(afterSection) : null;
  return {
    section_key: sectionKey,
    type,
    before_hash: before?.hash || null,
    after_hash: after?.hash || null,
    before_excerpt: excerpt(before?.normalized_text || ''),
    after_excerpt: excerpt(after?.normalized_text || ''),
    section_type: afterSection?.section_type || beforeSection?.section_type || 'other',
    change_type: type,
    old_hash: before?.hash || null,
    new_hash: after?.hash || null,
    diff_summary: type === 'added' ? 'Section added' : type === 'removed' ? 'Section removed' : 'Section content changed',
  };
}

export function computeSectionDiff(oldSections = [], newSections = [], options = {}) {
  const limit = Number.isFinite(Number(options.limit)) ? Number(options.limit) : 200;
  const oldByKey = new Map(oldSections.map((s) => [s.section_key, s]));
  const newByKey = new Map(newSections.map((s) => [s.section_key, s]));
  const keys = [...new Set([...oldByKey.keys(), ...newByKey.keys()])].sort();
  const changes = [];

  for (const key of keys) {
    const prev = oldByKey.get(key);
    const next = newByKey.get(key);

    if (!prev && next) {
      changes.push(changeRow(key, 'added', null, next));
      continue;
    }

    if (prev && !next) {
      changes.push(changeRow(key, 'removed', prev, null));
      continue;
    }

    const prevHash = normalizedHash(prev).hash;
    const nextHash = normalizedHash(next).hash;
    if (prevHash !== nextHash) {
      changes.push(changeRow(key, 'modified', prev, next));
    }
  }

  const counts = {
    added: changes.filter((c) => c.type === 'added').length,
    removed: changes.filter((c) => c.type === 'removed').length,
    modified: changes.filter((c) => c.type === 'modified').length,
  };
  counts.total = counts.added + counts.removed + counts.modified;

  return {
    counts,
    changes: changes.slice(0, limit),
    oldByKey: Object.fromEntries(oldByKey),
    newByKey: Object.fromEntries(newByKey),
  };
}
