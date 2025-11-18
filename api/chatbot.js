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

function buildSearchQuery(question, history) {
  const userTurns = history.filter((entry) => entry.role === 'user').map((entry) => entry.content);
  const context = userTurns.slice(-3); // keep only the last few prompts to preserve context
  return [...context, question].filter(Boolean).join(' ');
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

function fallbackAnswer(question, docs, lang = 'de') {
  const isEnglish = lang?.toLowerCase().startsWith('en');
  if (!docs.length) {
    return isEnglish
      ? 'No knowledge articles are available right now. Please try again later.'
      : 'Aktuell sind keine Wissensartikel verfügbar. Bitte versuche es später erneut.';
  }

  const intro = isEnglish
    ? 'The AI service was temporarily unavailable, so I searched the internal knowledge base for you.'
    : 'Der KI-Dienst war gerade nicht erreichbar. Ich habe stattdessen die Wissensbasis durchsucht.';

  const contextLine = question
    ? isEnglish
      ? `Regarding "${question}" I found the following hints:`
      : `Zur Anfrage „${question}“ habe ich diese Hinweise gefunden:`
    : isEnglish
      ? 'Here are the most relevant hints:'
      : 'Hier sind die relevantesten Hinweise:';

  const bulletList = docs
    .map((doc) => `• ${doc.title}: ${doc.summary}`)
    .join('\n');

  const closing = isEnglish
    ? 'Let me know if you need more detail or have another question.'
    : 'Melde dich, wenn du weitere Details brauchst oder eine andere Frage hast.';

  return [intro, contextLine, bulletList, closing].filter(Boolean).join('\n\n');
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

  const searchQuery = buildSearchQuery(question, history);
  const docs = retrieveDocuments(searchQuery, { limit: 4 });

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
      answer = fallbackAnswer(question, docs, lang);
      meta.fallback = true;
    }
  } else {
    answer = fallbackAnswer(question, docs, lang);
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
