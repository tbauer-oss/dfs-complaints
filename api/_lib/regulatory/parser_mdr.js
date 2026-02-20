import { load } from 'cheerio';
import { normalizeText } from './normalize.js';
import { sha256 } from './hash.js';

function classifyHeading(text = '') {
  const value = normalizeText(text);
  const article = value.match(/^(artikel|article)\s+([0-9]+[a-z]?)/i);
  if (article) {
    return {
      section_type: 'article',
      section_key: `Art_${article[2].toUpperCase()}`,
      heading: value,
    };
  }

  const annex = value.match(/^(anhang|annex)\s+([ivxlcdm0-9a-z\-]+)/i);
  if (annex) {
    return {
      section_type: 'annex',
      section_key: `Annex_${annex[2].toUpperCase()}`,
      heading: value,
    };
  }

  const recital = value.match(/^\((\d+)\)\s+/);
  if (recital) {
    return {
      section_type: 'recital',
      section_key: `Recital_${recital[1]}`,
      heading: `Recital ${recital[1]}`,
      initialText: value,
    };
  }

  return null;
}

function pushLine(section, text = '', html = '') {
  const normalized = normalizeText(text);
  if (!normalized) return;
  section.content_text = normalizeText(`${section.content_text}\n${normalized}`);
  section.content_html = `${section.content_html}${html || ''}`;
}

export function parseMdrSections(html = '') {
  const $ = load(html);
  const root = $('main, #document1, #text, body').first();
  const nodes = (root.length ? root : $('body')).find('h1, h2, h3, h4, p, li, div').toArray();

  const sections = [];
  let current = null;
  let sortOrder = 0;

  for (const node of nodes) {
    const $node = $(node);
    const text = normalizeText($node.text());
    if (!text) continue;

    const classified = classifyHeading(text);
    if (classified) {
      current = {
        section_type: classified.section_type,
        section_key: classified.section_key,
        heading: classified.heading,
        content_html: '',
        content_text: '',
        sort_order: sortOrder += 1,
      };
      sections.push(current);
      if (classified.initialText) pushLine(current, classified.initialText, $.html(node));
      continue;
    }

    if (!current) continue;
    pushLine(current, text, $.html(node));
  }

  return sections
    .map((entry) => {
      const contentText = normalizeText(entry.content_text || entry.heading || '');
      return {
        ...entry,
        content_text: contentText,
        content_hash: sha256(contentText),
      };
    })
    .filter((entry) => entry.content_text);
}
