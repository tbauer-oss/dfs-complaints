export function normalizeText(input = '') {
  return String(input || '')
    .replace(/\r\n/g, '\n')
    .replace(/[\u00a0\u202f]/g, ' ')
    .replace(/[\u200b-\u200d\ufeff]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}
