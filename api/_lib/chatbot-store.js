// api/_lib/chatbot-store.js
// Lädt die Wissensbasis und ermöglicht eine leichte semantische Suche.

import fs from 'node:fs';

const KNOWLEDGE_FILE = new URL('../_assets/chatbot/knowledge.json', import.meta.url);
let cache;

function readKnowledgeFile() {
  try {
    const raw = fs.readFileSync(KNOWLEDGE_FILE, 'utf8');
    return JSON.parse(raw);
  } catch (err) {
    console.error('chatbot knowledge could not be loaded', err);
    return [];
  }
}

function tokenize(text = '') {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9äöüß\s]+/gi, ' ')
    .split(/\s+/)
    .filter(Boolean);
}

function vectorize(text) {
  const tokens = tokenize(text);
  const counts = new Map();
  for (const tok of tokens) {
    counts.set(tok, (counts.get(tok) || 0) + 1);
  }
  const norm = Math.sqrt(Array.from(counts.values()).reduce((acc, v) => acc + v * v, 0)) || 1;
  return { counts, norm };
}

function cosineSimilarity(a, b) {
  let dot = 0;
  for (const [token, weight] of a.counts) {
    const other = b.counts.get(token);
    if (other) dot += weight * other;
  }
  return dot / (a.norm * b.norm);
}

function buildStore() {
  const docs = readKnowledgeFile().map((doc, idx) => {
    const text = [doc.summary, doc.details].filter(Boolean).join('\n');
    return {
      id: doc.id || `doc-${idx + 1}`,
      title: doc.title || `Artikel ${idx + 1}`,
      tags: doc.tags || [],
      text,
      summary: doc.summary || text.slice(0, 180),
      vector: vectorize(text),
    };
  });
  return { docs, createdAt: Date.now() };
}

function ensureStore() {
  if (!cache) cache = buildStore();
  return cache;
}

export function reloadChatbotStore() {
  cache = buildStore();
  return cache;
}

export function retrieveDocuments(query, { limit = 3, minScore = 0.05 } = {}) {
  const { docs } = ensureStore();
  if (!docs.length) return [];
  const queryVector = vectorize(query);
  const scored = docs
    .map((doc) => ({
      ...doc,
      score: Number(cosineSimilarity(queryVector, doc.vector).toFixed(4)),
    }))
    .filter((doc) => doc.score >= minScore)
    .sort((a, b) => b.score - a.score)
    .slice(0, limit)
    .map((doc) => ({
      id: doc.id,
      title: doc.title,
      tags: doc.tags,
      summary: doc.summary,
      text: doc.text,
      score: doc.score,
    }));

  if (scored.length) return scored;
  const best = docs[0];
  return [
    {
      id: best.id,
      title: best.title,
      tags: best.tags,
      summary: best.summary,
      text: best.text,
      score: 0,
    },
  ];
}
