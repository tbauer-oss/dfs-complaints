export function computeSectionDiff(oldSections = [], newSections = []) {
  const oldByKey = new Map(oldSections.map((s) => [s.section_key, s]));
  const newByKey = new Map(newSections.map((s) => [s.section_key, s]));
  const keys = [...new Set([...oldByKey.keys(), ...newByKey.keys()])].sort();
  const changes = [];

  for (const key of keys) {
    const prev = oldByKey.get(key);
    const next = newByKey.get(key);
    if (!prev && next) {
      changes.push({ section_key: key, section_type: next.section_type, change_type: 'added', old_hash: null, new_hash: next.content_hash, diff_summary: 'Section added' });
      continue;
    }
    if (prev && !next) {
      changes.push({ section_key: key, section_type: prev.section_type, change_type: 'removed', old_hash: prev.content_hash, new_hash: null, diff_summary: 'Section removed' });
      continue;
    }
    if (prev.content_hash !== next.content_hash) {
      changes.push({ section_key: key, section_type: next.section_type, change_type: 'modified', old_hash: prev.content_hash, new_hash: next.content_hash, diff_summary: 'Section content changed' });
    }
  }

  return {
    counts: {
      added: changes.filter((c) => c.change_type === 'added').length,
      removed: changes.filter((c) => c.change_type === 'removed').length,
      modified: changes.filter((c) => c.change_type === 'modified').length,
    },
    changes,
    oldByKey: Object.fromEntries(oldByKey),
    newByKey: Object.fromEntries(newByKey),
  };
}
