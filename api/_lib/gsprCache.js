import crypto from 'crypto';

function normalizeWhitespace(text) {
  return String(text || '').replace(/\r/g, '').replace(/[ \t]+/g, ' ').replace(/\n{3,}/g, '\n\n').trim();
}

export function requirementHash(text) {
  return crypto.createHash('sha256').update(normalizeWhitespace(text), 'utf8').digest('hex');
}

export function extractGsprRequirements(annexText) {
  const text = normalizeWhitespace(annexText);
  const headingRegex = /^\s*(\d+(?:\.\d+)*)(?:\.)?\s+(\S.*)$/gm;
  const hits = [];
  let match;

  while ((match = headingRegex.exec(text)) !== null) {
    hits.push({
      code: String(match[1] || '').trim(),
      firstLine: String(match[2] || '').trim(),
      index: match.index,
      fullMatch: match[0],
    });
  }

  if (!hits.length) return [];

  const rows = [];
  for (let i = 0; i < hits.length; i += 1) {
    const current = hits[i];
    const next = hits[i + 1];
    const start = current.index;
    const end = next ? next.index : text.length;
    const block = text.slice(start, end).trim();
    const withoutCode = block.replace(/^\s*\d+(?:\.\d+)*(?:\.)?\s*/m, '').trim();
    if (!withoutCode) continue;

    const firstSentence = withoutCode.split(/(?<=[\.!?])\s+/)[0] || withoutCode;
    rows.push({
      gspr_code: current.code,
      title: firstSentence.slice(0, 240),
      requirement_text: withoutCode,
      requirement_hash: requirementHash(withoutCode),
      sort_order: i + 1,
    });
  }

  return rows;
}
