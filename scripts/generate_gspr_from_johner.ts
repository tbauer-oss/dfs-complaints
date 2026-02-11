import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import cheerio from './vendor/cheerio.js';

type GsprItem = {
  id: string;
  ref: string;
  chapter: number;
  title: string;
  sortKey: string;
  parentId: string | null;
  level: number;
  text: string;
  isAssessable: boolean;
  contextIds: string[];
  contextText: string | null;
};

type GsprItemRaw = {
  id: string;
  ref: string;
  chapter: number;
  title: string;
  sortKey: string;
  parentId: string | null;
  level: number;
  fullText: string;
};

type Summary = {
  total: number;
  byChapter: Record<number, number>;
  byLevel: Record<number, number>;
};

const SOURCE_URL = 'https://eur-lex.europa.eu/legal-content/de/ALL/?uri=CELEX:32017R0745';
const START_MARKERS = [
  'ANHANG I\nGRUNDLEGENDE SICHERHEITS- UND LEISTUNGSANFORDERUNGEN',
  'ANHANG I: GRUNDLEGENDE SICHERHEITS- UND LEISTUNGSANFORDERUNGEN',
  '## ANHANG I: GRUNDLEGENDE SICHERHEITS- UND LEISTUNGSANFORDERUNGEN',
] as const;
const END_MARKERS = [
  'ANHANG II\nTECHNISCHE DOKUMENTATION',
  'ANHANG II: TECHNISCHE DOKUMENTATION',
  '## ANHANG II: TECHNISCHE DOKUMENTATION',
] as const;

const TOP_LEVEL_TITLES: Record<string, string> = {
  '1': 'Allgemeine Anforderungen',
  '2': 'Risikominimierung',
  '3': 'Risikomanagementsystem',
  '4': 'Risikokontrolle',
  '5': 'Anwendungsfehler',
  '6': 'Lebensdauer',
  '7': 'Transport und Lagerung',
  '8': 'Bekannte Risiken',
  '9': 'Produkte gemäß Anhang XVI',
  '10': 'Chemische, physikalische und biologische Eigenschaften',
  '11': 'Infektion und mikrobielle Kontamination',
  '12': 'Produkte, die Stoffe enthalten',
  '13': 'Produkte mit Materialien biologischen Ursprungs',
  '14': 'Herstellung von Produkten und Wechselwirkungen mit ihrer Umgebung',
  '15': 'Produkte mit Diagnose- oder Messfunktion',
  '16': 'Schutz vor Strahlung',
  '17': 'Programmierbare Elektroniksysteme und Software',
  '18': 'Aktive Produkte und mit diesen verbundene Produkte',
  '19': 'Besondere Anforderungen für aktive implantierbare Produkte',
  '20': 'Schutz vor mechanischen und thermischen Risiken',
  '21': 'Schutz vor Risiken durch Produkte, die Energie oder Stoffe abgeben',
  '22': 'Schutz vor Risiken bei Anwendung durch Laien',
  '23': 'Kennzeichnung und Gebrauchsanweisung',
};

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(__dirname, '..');
const OUTPUT_TS = path.join(ROOT_DIR, 'src/compliance/gspr/gspr_items.generated.ts');
const OUTPUT_JS = path.join(ROOT_DIR, 'api/_lib/gspr_items.generated.js');

function normalizeWhitespace(input: string): string {
  return input
    .replace(/\r\n?/g, '\n')
    .replace(/[ \t]+$/gm, '')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

function cleanMarkers(input: string): string {
  return input.replace(/【\d+†/g, '').replace(/】/g, '');
}

function findFirstMarker(text: string, markers: readonly string[]): { marker: string; index: number } | null {
  for (const marker of markers) {
    const index = text.indexOf(marker);
    if (index !== -1) {
      return { marker, index };
    }
  }
  return null;
}

function sliceBetween(text: string, startMarkers: readonly string[], endMarkers: readonly string[]): string {
  const start = findFirstMarker(text, startMarkers);
  if (!start) {
    throw new Error(`Annex start marker not found. Tried: ${startMarkers.join(' | ')}`);
  }

  const afterStart = start.index + start.marker.length;
  const tail = text.slice(afterStart);
  const end = findFirstMarker(tail, endMarkers);
  if (!end) {
    throw new Error(`Annex end marker not found. Tried: ${endMarkers.join(' | ')}`);
  }

  return text.slice(start.index, afterStart + end.index);
}

function letterOrder(letter: string): number {
  let value = 0;
  for (const char of letter) {
    value = value * 26 + (char.charCodeAt(0) - 96);
  }
  return value;
}

function buildSortKey(id: string): string {
  const parts = id.split('.');
  const tokens: string[] = [];
  for (const part of parts) {
    if (part.startsWith('--')) {
      const dash = Number(part.replace('--', ''));
      tokens.push(`D${String(dash).padStart(3, '0')}`);
      continue;
    }
    if (/^\d+$/.test(part)) {
      tokens.push(`N${String(part).padStart(6, '0')}`);
      continue;
    }
    if (/^[a-z]{1,2}$/.test(part)) {
      const order = letterOrder(part);
      tokens.push(`L${String(order).padStart(3, '0')}`);
      continue;
    }
    tokens.push(`X${part}`);
  }
  return tokens.join('.');
}

function buildTitle(item: { id: string; level: number }): string {
  if (item.level === 0) {
    return TOP_LEVEL_TITLES[item.id] || `Kapitel ${item.id}`;
  }
  if (item.level === 3) {
    const letter = item.id.split('.').slice(-1)[0];
    return `Buchstabe ${letter})`;
  }
  if (item.level === 4) {
    const dash = item.id.split('.').slice(-1)[0].replace('--', '');
    return `Spiegelstrich ${dash}`;
  }
  return `Abschnitt ${item.id}`;
}

function getParentId(id: string, level: number, currentNumberId: string | null, currentLetterId: string | null): string | null {
  if (level === 0) return null;
  if (level === 1 || level === 2) {
    const parts = id.split('.');
    return parts.slice(0, -1).join('.') || null;
  }
  if (level === 3) return currentNumberId;
  if (level === 4) return currentLetterId;
  return null;
}

function finalizeText(lines: string[]): string {
  const text = normalizeWhitespace(cleanMarkers(lines.join('\n')));
  return text;
}

function createSummary(items: GsprItemRaw[]): Summary {
  const byChapter: Record<number, number> = {};
  const byLevel: Record<number, number> = {};
  for (const item of items) {
    byChapter[item.chapter] = (byChapter[item.chapter] || 0) + 1;
    byLevel[item.level] = (byLevel[item.level] || 0) + 1;
  }
  return { total: items.length, byChapter, byLevel };
}

async function fetchSourceText(): Promise<string> {
  const response = await fetch(SOURCE_URL);
  if (!response.ok) {
    throw new Error(`Failed to fetch source: ${response.status} ${response.statusText}`);
  }
  const html = await response.text();
  const $ = cheerio.load(html);
  const text = $('body').text();
  return normalizeWhitespace(cleanMarkers(text));
}

async function generate() {
  const rawText = await fetchSourceText();
  const slice = sliceBetween(rawText, START_MARKERS, END_MARKERS);
  const lines = slice.split('\n');

  const items: GsprItemRaw[] = [];
  let currentChapter: number | null = null;
  let currentNumberId: string | null = null;
  let currentLetterId: string | null = null;
  let dashCounter = 0;
  let buffer: string[] = [];
  let currentItem: GsprItemRaw | null = null;

  const flushCurrent = () => {
    if (!currentItem) return;
    currentItem.fullText = finalizeText(buffer);
    items.push(currentItem);
    currentItem = null;
    buffer = [];
  };

  const startItem = (item: GsprItemRaw, initialText?: string) => {
    flushCurrent();
    currentItem = item;
    buffer = [];
    if (initialText && initialText.trim()) {
      buffer.push(initialText.trim());
    }
  };

  for (const line of lines) {
    const chapterMatch = line.match(/^\s*KAPITEL\s+(I|II|III)\s*:/);
    if (chapterMatch) {
      flushCurrent();
      const roman = chapterMatch[1];
      currentChapter = roman === 'I' ? 1 : roman === 'II' ? 2 : 3;
      currentNumberId = null;
      currentLetterId = null;
      dashCounter = 0;
      continue;
    }

    const decimalMatch = line.match(/^\s*(\d+(?:\.\d+)+)\.\s*(.*)$/);
    if (decimalMatch) {
      const id = decimalMatch[1];
      const depth = id.split('.').length;
      const level = depth === 2 ? 1 : 2;
      const ref = id;
      currentNumberId = id;
      currentLetterId = null;
      dashCounter = 0;
      if (!currentChapter) {
        throw new Error(`Chapter not set before item ${id}`);
      }
      startItem({
        id,
        ref,
        chapter: currentChapter,
        title: buildTitle({ id, level }),
        sortKey: buildSortKey(id),
        parentId: getParentId(id, level, currentNumberId, currentLetterId),
        level,
        fullText: '',
      }, decimalMatch[2]);
      continue;
    }

    const topMatch = line.match(/^\s*(\d+)\.\s*(.*)$/);
    if (topMatch) {
      const id = topMatch[1];
      currentNumberId = id;
      currentLetterId = null;
      dashCounter = 0;
      if (!currentChapter) {
        throw new Error(`Chapter not set before item ${id}`);
      }
      startItem({
        id,
        ref: id,
        chapter: currentChapter,
        title: buildTitle({ id, level: 0 }),
        sortKey: buildSortKey(id),
        parentId: null,
        level: 0,
        fullText: '',
      }, topMatch[2]);
      continue;
    }

    const letterMatch = line.match(/^\s*([a-z]{1,2})\)\s*(.*)$/);
    if (letterMatch && currentNumberId) {
      const letter = letterMatch[1];
      const id = `${currentNumberId}.${letter}`;
      currentLetterId = id;
      dashCounter = 0;
      startItem({
        id,
        ref: `${currentNumberId} ${letter})`,
        chapter: currentChapter || 0,
        title: buildTitle({ id, level: 3 }),
        sortKey: buildSortKey(id),
        parentId: getParentId(id, 3, currentNumberId, currentLetterId),
        level: 3,
        fullText: '',
      }, letterMatch[2]);
      continue;
    }

    const dashMatch = line.match(/^\s*—\s*(.*)$/);
    if (dashMatch && currentLetterId) {
      dashCounter += 1;
      const id = `${currentLetterId}.--${dashCounter}`;
      startItem({
        id,
        ref: `${currentLetterId.replace(/\.(\w+)$/, ' $1)')} — ${dashCounter}`,
        chapter: currentChapter || 0,
        title: buildTitle({ id, level: 4 }),
        sortKey: buildSortKey(id),
        parentId: getParentId(id, 4, currentNumberId, currentLetterId),
        level: 4,
        fullText: '',
      }, dashMatch[1]);
      continue;
    }

    if (currentItem) {
      const trimmed = line.trim();
      if (!trimmed) {
        buffer.push('');
      } else {
        buffer.push(trimmed);
      }
    }
  }

  flushCurrent();

  const filtered = items.filter((item) => item.id && item.fullText !== '');

  if (filtered.length < 200) {
    throw new Error(`Suspiciously low item count: ${filtered.length}`);
  }

  const summary = createSummary(filtered);
  console.log('GSPR items generated:', summary);

  await fs.mkdir(path.dirname(OUTPUT_TS), { recursive: true });
  await fs.mkdir(path.dirname(OUTPUT_JS), { recursive: true });

  const timestamp = new Date().toISOString();
  const header = `// Generated from ${SOURCE_URL} at ${timestamp}`;

  const tsOutput = `${header}\n\nexport type GsprItemRaw = {\n  id: string;\n  ref: string;\n  chapter: number;\n  title: string;\n  sortKey: string;\n  parentId: string | null;\n  level: number;\n  fullText: string;\n};\n\nexport type GsprItem = {\n  id: string;\n  ref: string;\n  chapter: number;\n  title: string;\n  sortKey: string;\n  parentId: string | null;\n  level: number;\n  text: string;\n  isAssessable: boolean;\n  contextIds: string[];\n  contextText: string | null;\n};\n\nconst GSPR_ITEMS_RAW: GsprItemRaw[] = ${JSON.stringify(filtered, null, 2)} as const;\n\nfunction buildGsprItems(raw: GsprItemRaw[]) {\n  const rawById = new Map(raw.map((item) => [item.id, item]));\n  const childrenByParent = new Map<string, GsprItemRaw[]>();\n  for (const item of raw) {\n    if (!item.parentId) continue;\n    if (!childrenByParent.has(item.parentId)) childrenByParent.set(item.parentId, []);\n    childrenByParent.get(item.parentId)?.push(item);\n  }\n\n  const isAssessable = new Map<string, boolean>();\n  for (const item of raw) {\n    const children = childrenByParent.get(item.id) || [];\n    if (children.length === 0) {\n      isAssessable.set(item.id, true);\n      continue;\n    }\n    const hasListChildren = children.some((child) => child.level >= 3);\n    const endsWithColon = item.fullText.trim().endsWith(':');\n    isAssessable.set(item.id, !(hasListChildren || endsWithColon));\n  }\n\n  const items = raw.map((item) => {\n    const assessable = isAssessable.get(item.id) ?? true;\n    const contextIds: string[] = [];\n    const contextTexts: string[] = [];\n    if (assessable) {\n      let current = item.parentId;\n      while (current) {\n        const parent = rawById.get(current);\n        if (!parent) break;\n        if (isAssessable.get(parent.id) === false) {\n          contextIds.unshift(parent.id);\n          if (parent.fullText.trim()) {\n            contextTexts.unshift(parent.fullText);\n          }\n        }\n        current = parent.parentId;\n      }\n    }\n    return {\n      id: item.id,\n      ref: item.ref,\n      chapter: item.chapter,\n      title: item.title,\n      sortKey: item.sortKey,\n      parentId: item.parentId,\n      level: item.level,\n      text: item.fullText,\n      isAssessable: assessable,\n      contextIds,\n      contextText: contextTexts.length ? contextTexts.join('\\n\\n') : null,\n    };\n  });\n\n  const itemsById = new Map(items.map((item) => [item.id, item]));\n  return { items, itemsById };\n}\n\nconst { items: GSPR_ITEMS, itemsById: GSPR_ITEMS_BY_ID } = buildGsprItems(GSPR_ITEMS_RAW);\n\nexport { GSPR_ITEMS, GSPR_ITEMS_BY_ID };\n\nexport function gsprItemsByChapter(chapter: number) {\n  return GSPR_ITEMS.filter((item) => item.chapter === chapter).sort((a, b) => a.sortKey.localeCompare(b.sortKey));\n}\n\nexport function gsprChildren(parentId: string) {\n  return GSPR_ITEMS.filter((item) => item.parentId === parentId).sort((a, b) => a.sortKey.localeCompare(b.sortKey));\n}\n`;

  const jsOutput = `${header}\n\nconst GSPR_ITEMS_RAW = ${JSON.stringify(filtered, null, 2)};\n\nfunction buildGsprItems(raw) {\n  const rawById = new Map(raw.map((item) => [item.id, item]));\n  const childrenByParent = new Map();\n  for (const item of raw) {\n    if (!item.parentId) continue;\n    if (!childrenByParent.has(item.parentId)) childrenByParent.set(item.parentId, []);\n    childrenByParent.get(item.parentId).push(item);\n  }\n\n  const isAssessable = new Map();\n  for (const item of raw) {\n    const children = childrenByParent.get(item.id) || [];\n    if (children.length === 0) {\n      isAssessable.set(item.id, true);\n      continue;\n    }\n    const hasListChildren = children.some((child) => child.level >= 3);\n    const endsWithColon = item.fullText.trim().endsWith(':');\n    isAssessable.set(item.id, !(hasListChildren || endsWithColon));\n  }\n\n  const items = raw.map((item) => {\n    const assessable = isAssessable.get(item.id) ?? true;\n    const contextIds = [];\n    const contextTexts = [];\n    if (assessable) {\n      let current = item.parentId;\n      while (current) {\n        const parent = rawById.get(current);\n        if (!parent) break;\n        if (isAssessable.get(parent.id) === false) {\n          contextIds.unshift(parent.id);\n          if (parent.fullText.trim()) {\n            contextTexts.unshift(parent.fullText);\n          }\n        }\n        current = parent.parentId;\n      }\n    }\n    return {\n      id: item.id,\n      ref: item.ref,\n      chapter: item.chapter,\n      title: item.title,\n      sortKey: item.sortKey,\n      parentId: item.parentId,\n      level: item.level,\n      text: item.fullText,\n      isAssessable: assessable,\n      contextIds,\n      contextText: contextTexts.length ? contextTexts.join('\\n\\n') : null,\n    };\n  });\n\n  const itemsById = new Map(items.map((item) => [item.id, item]));\n  return { items, itemsById };\n}\n\nconst { items: GSPR_ITEMS, itemsById: GSPR_ITEMS_BY_ID } = buildGsprItems(GSPR_ITEMS_RAW);\n\nexport { GSPR_ITEMS, GSPR_ITEMS_BY_ID };\n\nexport function gsprItemsByChapter(chapter) {\n  return GSPR_ITEMS.filter((item) => item.chapter === chapter).sort((a, b) => a.sortKey.localeCompare(b.sortKey));\n}\n\nexport function gsprChildren(parentId) {\n  return GSPR_ITEMS.filter((item) => item.parentId === parentId).sort((a, b) => a.sortKey.localeCompare(b.sortKey));\n}\n`;

  await fs.writeFile(OUTPUT_TS, tsOutput, 'utf8');
  await fs.writeFile(OUTPUT_JS, jsOutput, 'utf8');
}

generate().catch((error) => {
  console.error('[generate_gspr_from_johner] failed:', error);
  process.exit(1);
});
