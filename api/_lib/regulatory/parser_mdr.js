import { load } from 'cheerio';
import { normalizeText } from './normalize.js';

function keyFromHeading(text, fallback) {
  const value = String(text || '').trim();
  const article = value.match(/^article\s+([0-9a-z]+)/i);
  if (article) return `Art_${article[1]}`;
  const annex = value.match(/^annex\s+([ivx0-9a-z\-]+)/i);
  if (annex) return `Annex_${annex[1].toUpperCase()}`;
  return fallback;
}

export function parseMdrSections(html = '') {
  const $ = load(html);
  const nodes = $('h1, h2, h3, h4, p, li');
  const sections = [];
  let current = null;
  let order = 0;

  nodes.each((_, node) => {
    const tag = node.tagName?.toLowerCase();
    const text = normalizeText($(node).text());
    if (!text) return;
    if (['h1', 'h2', 'h3', 'h4'].includes(tag)) {
      const sectionKey = keyFromHeading(text, `Section_${sections.length + 1}`);
      current = {
        section_type: sectionKey.startsWith('Art_') ? 'article' : sectionKey.startsWith('Annex_') ? 'annex' : 'other',
        section_key: sectionKey,
        heading: text,
        content_html: '',
        content_text: '',
        sort_order: order += 1,
      };
      sections.push(current);
      return;
    }
    if (!current) {
      current = {
        section_type: 'other',
        section_key: `Preamble_${sections.length + 1}`,
        heading: 'Preamble',
        content_html: '',
        content_text: '',
        sort_order: order += 1,
      };
      sections.push(current);
    }
    current.content_html += `<${tag}>${$(node).html() || ''}</${tag}>`;
    current.content_text = `${current.content_text}\n${text}`.trim();
  });

  return sections.filter((entry) => entry.content_text || entry.heading);
}
