import { GSPR_ITEMS, GSPR_ITEMS_BY_ID, gsprItemsByChapter, gsprChildren } from './gspr_items.generated.js';

export { GSPR_ITEMS, GSPR_ITEMS_BY_ID, gsprItemsByChapter, gsprChildren };

export const GSPR_SOURCE_PERMALINK = '/api/regulatory/mdr-2017-745/outline';
export const GSPR_SOURCE_NAME = 'Regulatory Cache (Supabase)';
export const GSPR_LAST_SYNC_AT = null;

export const GSPR_REQUIREMENTS = GSPR_ITEMS.filter((item) => item.level === 0);
export const GSPR_REQUIREMENTS_BY_ID = GSPR_ITEMS_BY_ID;

export function gsprAssessableItems() {
  return GSPR_ITEMS.filter((item) => item.isAssessable);
}

export function gsprAssessableItemsByChapter(chapter) {
  return gsprItemsByChapter(chapter).filter((item) => item.isAssessable);
}

export function gsprRequirementsByChapter(chapter) {
  return gsprItemsByChapter(chapter);
}

export function gsprRequirementsTreeByChapter(chapter) {
  const list = gsprItemsByChapter(chapter);
  const byParent = new Map();
  for (const item of list) {
    const key = item.parentId || null;
    if (!byParent.has(key)) byParent.set(key, []);
    byParent.get(key).push(item);
  }
  for (const children of byParent.values()) {
    children.sort((a, b) => a.sortKey.localeCompare(b.sortKey));
  }
  return { list, byParent };
}
