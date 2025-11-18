// api/chatbot.js
export const config = { runtime: 'nodejs' };

import { handlePreflight, methodNotAllowed, bad, ok, readJson, setCors } from './_lib/http.js';
import { retrieveDocuments } from './_lib/chatbot-store.js';
import { hasOpenAI, runChatCompletion } from './_lib/openai.js';

function sanitizeHistory(history = []) {
  return history
    .filter((entry) => entry && typeof entry.message === 'string')
    .slice(-8)
    .map((entry) => ({
      role: entry.role === 'assistant' ? 'assistant' : 'user',
      content: entry.message.trim(),
    }))
    .filter((entry) => entry.content.length > 0);
}

function buildSystemPrompt(lang = 'de') {
  const langName = lang?.toLowerCase().startsWith('en') ? 'English' : 'German';
  return [
    'Du bist der DFS-Beschwerdeassistent.',
    'Antworte präzise, freundlich und mit Bezug zur Plattform.',
    'Wenn der Kontext keine Antwort enthält, gib ehrlich an, dass dir Informationen fehlen.',
    `Beantworte alle Antworten bevorzugt in ${langName}.`,
  ].join(' ');
}

function buildUserPrompt(question, docs) {
  const contextBlock = docs
    .map((doc) => `Titel: ${doc.title}\nTags: ${doc.tags.join(', ')}\nText: ${doc.text}`)
    .join('\n---\n');
  return [
    'Verwende ausschließlich den bereitgestellten Kontext, um zu antworten.',
    'Ignoriere Themen außerhalb der Beschwerdeplattform.',
    'Kontext:',
    contextBlock,
    `Frage: ${question}`,
  ].join('\n\n');
}

function fallbackAnswer(docs, lang = 'de') {
  if (!docs.length) {
    return lang.startsWith('en')
      ? 'Aktuell sind keine Wissensartikel verfügbar. Bitte versuche es später erneut.'
      : 'Aktuell sind keine Wissensartikel verfügbar. Bitte versuche es später erneut.';
  }
  const top = docs[0];
  if (lang.startsWith('en')) {
    return `Ich kann dir gerade nur statische Informationen liefern. Hier ist die relevanteste Notiz: ${top.summary}`;
  }
  return `Ich kann dir gerade nur statische Informationen liefern. Wichtigster Treffer: ${top.summary}`;
}

export default async function handler(req, res) {
  setCors(req, res);
  if (handlePreflight(req, res)) return;
  if (req.method !== 'POST') return methodNotAllowed(res);

  const body = readJson(req);
  const question = String(body.question || '').trim();
  const history = sanitizeHistory(Array.isArray(body.history) ? body.history : []);
  const lang = String(body.lang || 'de');

  if (!question) return bad(res, 'question required', 400);

  const docs = retrieveDocuments(question, { limit: 4 });

  let answer;
  let meta = { usedOpenAI: false };

  if (hasOpenAI()) {
    try {
      const messages = [
        { role: 'system', content: buildSystemPrompt(lang) },
        ...history,
        { role: 'user', content: buildUserPrompt(question, docs) },
      ];
      answer = await runChatCompletion(messages, { maxTokens: 600 });
      meta.usedOpenAI = true;
    } catch (err) {
      console.error('chatbot completion failed', err);
      answer = fallbackAnswer(docs, lang);
      meta.fallback = true;
    }
  } else {
    answer = fallbackAnswer(docs, lang);
    meta.fallback = true;
  }

  return ok(res, {
    answer,
    sources: docs.map((doc) => ({
      id: doc.id,
      title: doc.title,
      tags: doc.tags,
      score: doc.score,
    })),
    metadata: meta,
  });
}
